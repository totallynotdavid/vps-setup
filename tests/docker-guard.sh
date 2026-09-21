#!/usr/bin/env bash
# The docker guard step, run against the source fragments on temporary files
# with fake ufw, iptables and ip6tables. Needs no root and no network.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source-path=SCRIPTDIR/..
source lib/log.sh
source lib/quiet.sh
source steps/install/35-docker-guard.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
system_path=$PATH

# The fakes log their arguments. The fake iptables and ip6tables list the guard
# unless $FAKE_NOT_LOADED names them, and then fail as the real ones do for a
# chain that does not exist. With $FAKE_FIX_ON_RELOAD set they list it once the
# fake ufw has seen a reload, which leaves a marker file.
mkdir "$tmp/bin"
cat >"$tmp/bin/ufw" <<'FAKE'
#!/bin/sh
echo "ufw $*" >>"$FAKE_CALLS"
[ "$1" != reload ] || touch "$FAKE_RELOADED"
FAKE
cat >"$tmp/bin/iptables" <<'FAKE'
#!/bin/sh
echo "$(basename "$0") $*" >>"$FAKE_CALLS"
missing=$FAKE_NOT_LOADED
[ -z "$FAKE_FIX_ON_RELOAD" ] || [ ! -e "$FAKE_RELOADED" ] || missing=
case " $missing " in
*" $(basename "$0") "*)
	echo "$(basename "$0"): No chain/target/match by that name." >&2
	exit 1
	;;
esac
printf '%s\n' '-N DOCKER-USER' '-A DOCKER-USER -j RETURN' '-A DOCKER-USER -m conntrack --ctstate NEW -j DROP'
FAKE
cp "$tmp/bin/iptables" "$tmp/bin/ip6tables"
chmod +x "$tmp/bin/ufw" "$tmp/bin/iptables" "$tmp/bin/ip6tables"
export FAKE_CALLS=$tmp/calls FAKE_RELOADED=$tmp/reloaded FAKE_NOT_LOADED='' FAKE_FIX_ON_RELOAD=''
FAKE_FIX_ON_RELOAD=''
export PATH=$tmp/bin:$system_path

assert() {
	local description=$1
	shift
	if "$@"; then
		printf 'PASS %s\n' "$description"
	else
		printf 'FAIL %s\n' "$description"
		failures=$((failures + 1))
	fi
}

stock_file() {
	cat >"$1" <<'STOCK'
#
# rules.input-after
#
# Rules that should be run after the ufw command line added rules.
#
# Don't delete these required lines, otherwise there will be errors
*filter
:ufw-after-input - [0:0]
# End required lines

# don't log noisy services by default
-A ufw-after-input -p udp --dport 137 -j ufw-skip-to-policy-input

# don't delete the 'COMMIT' line or these rules won't be processed
COMMIT
STOCK
	chmod 0640 "$1"
}

# The text that step 35 promises. iptables takes one -i per rule, and ufw restores
# after.rules before its user chains exist, so each block declares its own.
IFS= read -r -d '' expected_block <<'BLOCK' || true
# BEGIN vps-setup docker guard
*filter
:ufw-user-forward - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -i lo -j RETURN
-A DOCKER-USER -i tailscale0 -j RETURN
-A DOCKER-USER -i docker0 -j RETURN
-A DOCKER-USER -i br-+ -j RETURN
-A DOCKER-USER -i docker_gwbridge -j RETURN
-A DOCKER-USER -j ufw-user-forward
-A DOCKER-USER -m conntrack --ctstate NEW -j DROP
COMMIT
# END vps-setup docker guard
BLOCK
expected_block=${expected_block%$'\n'}
expected_block6=${expected_block//ufw-user-forward/ufw6-user-forward}

count_lines() {
	grep -cxF -- "$2" "$1" || true
}

file=$tmp/after.rules
stock_file "$file"
cp "$file" "$tmp/stock"
docker_guard_write "$file" ufw-user-forward
assert "the block is appended after the stock content" [ "$(<"$file")" == "$(<"$tmp/stock")"$'\n'"$expected_block" ]
assert "the IPv4 block is the promised text, with one rule per interface" [ "$(docker_guard_block ufw-user-forward)" == "$expected_block" ]
assert "the IPv6 block is the same but for the two lines that name the user-forward chain" \
	[ "$(docker_guard_block ufw6-user-forward)" == "$expected_block6" ]
assert "the IPv4 block declares and jumps to ufw-user-forward" \
	[ "$(docker_guard_block ufw-user-forward | grep -cx -e ':ufw-user-forward - \[0:0\]' -e '-A DOCKER-USER -j ufw-user-forward')" -eq 2 ]
assert "the IPv6 block declares and jumps to ufw6-user-forward" \
	[ "$(docker_guard_block ufw6-user-forward | grep -cx -e ':ufw6-user-forward - \[0:0\]' -e '-A DOCKER-USER -j ufw6-user-forward')" -eq 2 ]
assert "the IPv4 block does not name the IPv6 chain" [ "$(docker_guard_block ufw-user-forward | grep -c ufw6)" -eq 0 ]
assert "the IPv6 block does not name the IPv4 chain" [ "$(docker_guard_block ufw6-user-forward | grep -c 'ufw-user-forward')" -eq 0 ]
assert "the mode of the file is kept" [ "$(stat -c %a "$file")" == 640 ]
assert "no temporary file is left behind" [ "$(printf '%s\n' "$tmp"/after.rules* | wc -l)" -eq 1 ]

cp "$file" "$tmp/first"
docker_guard_write "$file" ufw-user-forward
assert "a second run leaves the file byte-identical" cmp -s "$file" "$tmp/first"

# An older block sits in the middle, with more rules after it.
{
	sed '$d' "$tmp/stock"
	printf '%s\n' '# BEGIN vps-setup docker guard' '*filter' ':DOCKER-USER - [0:0]' '-A DOCKER-USER -j RETURN' 'COMMIT' '# END vps-setup docker guard' 'COMMIT'
} >"$file"
docker_guard_write "$file" ufw-user-forward
assert "an outdated block is replaced, not duplicated" [ "$(count_lines "$file" '# BEGIN vps-setup docker guard')" -eq 1 ]
assert "an outdated block leaves none of its old rules" [ "$(count_lines "$file" '-A DOCKER-USER -j RETURN')" -eq 0 ]
assert "the current block is at the end" [ "$(tail -n "$(wc -l <<<"$expected_block")" "$file")" == "$expected_block" ]
assert "the stock rules before the block stay" grep -qxF -- '-A ufw-after-input -p udp --dport 137 -j ufw-skip-to-policy-input' "$file"

printf 'COMMIT' >"$file"
docker_guard_write "$file" ufw-user-forward
assert "a file without a final newline keeps its last line whole" [ "$(head -n 1 "$file")" == COMMIT ]
assert "a file without a final newline gets the block on its own lines" [ "$(count_lines "$file" '# BEGIN vps-setup docker guard')" -eq 1 ]

printf '%s\n' 'COMMIT' '# BEGIN vps-setup docker guard' 'rules that are not ours' >"$file"
cp "$file" "$tmp/lone"
status=0
(docker_guard_check "$file") 2>/dev/null || status=$?
assert "a lone begin marker is refused" [ "$status" -ne 0 ]
assert "and the file is untouched" cmp -s "$file" "$tmp/lone"
status=0
(docker_guard_check "$tmp/missing") 2>/dev/null || status=$?
assert "a missing file is refused" [ "$status" -ne 0 ]

# Both files, through the step's own loop and the fakes.
apply_both() {
	docker_guard_apply "$tmp/after.rules" ufw-user-forward "$tmp/after6.rules" ufw6-user-forward
}

stock_file "$tmp/after.rules"
stock_file "$tmp/after6.rules"
rm -f "$FAKE_CALLS"
apply_both 2>/dev/null
assert "files that changed: ufw reloads once, then both chains are read" \
	[ "$(<"$FAKE_CALLS")" == $'ufw reload\niptables -S DOCKER-USER\nip6tables -S DOCKER-USER' ]
assert "after.rules carries the IPv4 block" [ "$(tail -n "$(wc -l <<<"$expected_block")" "$tmp/after.rules")" == "$expected_block" ]
assert "after6.rules carries the IPv6 block" [ "$(tail -n "$(wc -l <<<"$expected_block6")" "$tmp/after6.rules")" == "$expected_block6" ]

rm -f "$FAKE_CALLS"
apply_both
assert "nothing changed and the guard is loaded: ufw is not reloaded" [ "$(grep -c '^ufw' "$FAKE_CALLS" || true)" -eq 0 ]
assert "nothing changed and the guard is loaded: both chains are read" \
	[ "$(<"$FAKE_CALLS")" == $'iptables -S DOCKER-USER\nip6tables -S DOCKER-USER' ]

stock_file "$tmp/after6.rules"
docker_guard_write "$tmp/after.rules" ufw-user-forward
rm -f "$FAKE_CALLS"
apply_both 2>/dev/null
assert "one file changed: ufw reloads once" [ "$(grep -c '^ufw reload$' "$FAKE_CALLS")" -eq 1 ]

for family in iptables ip6tables; do
	stock_file "$tmp/after6.rules"
	FAKE_NOT_LOADED=$family
	status=0
	stderr=$(apply_both 2>&1) || status=$?
	FAKE_NOT_LOADED=''
	assert "$family shows no guard afterwards: the step fails" [ "$status" -ne 0 ]
	assert "$family shows no guard afterwards: the message says the restore failed and SSH is open" \
		grep -qF 'did not restore: ufw kept its old rules and the docker guard is not loaded. Root SSH is still open' <<<"$stderr"
done

# The files are already current, as after a run that wrote them and could not restore them.
cp "$tmp/after.rules" "$tmp/kept" && cp "$tmp/after6.rules" "$tmp/kept6"
FAKE_NOT_LOADED="iptables ip6tables"
rm -f "$FAKE_CALLS" "$FAKE_RELOADED"
status=0
stderr=$(apply_both 2>&1) || status=$?
assert "current files, guard not loaded, still not loaded after: ufw reloads once" [ "$(grep -c '^ufw reload$' "$FAKE_CALLS")" -eq 1 ]
assert "current files, guard not loaded, still not loaded after: the step fails" [ "$status" -ne 0 ]
assert "current files, guard not loaded, still not loaded after: the message says the restore failed" \
	grep -qF 'did not restore: ufw kept its old rules and the docker guard is not loaded' <<<"$stderr"

FAKE_FIX_ON_RELOAD=1
rm -f "$FAKE_CALLS" "$FAKE_RELOADED"
status=0
apply_both 2>/dev/null || status=$?
FAKE_NOT_LOADED=''
FAKE_FIX_ON_RELOAD=''
assert "current files, guard not loaded, loaded after the reload: ufw reloads once" [ "$(grep -c '^ufw reload$' "$FAKE_CALLS")" -eq 1 ]
assert "current files, guard not loaded, loaded after the reload: the step succeeds" [ "$status" -eq 0 ]
assert "current files, guard not loaded, loaded after the reload: after.rules stays as it was" cmp -s "$tmp/after.rules" "$tmp/kept"
assert "current files, guard not loaded, loaded after the reload: after6.rules stays as it was" cmp -s "$tmp/after6.rules" "$tmp/kept6"

((failures == 0))
