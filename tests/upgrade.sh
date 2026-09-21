#!/usr/bin/env bash
# The upgrade step, run against the source fragments with fake tailscale and
# apt-get. Needs no root and no network.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source-path=SCRIPTDIR/..
source lib/log.sh
source lib/quiet.sh
source lib/apt.sh
source steps/install/06-upgrade.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

# The PATH holds only env, which the helpers need, and the fakes, so a tailscale
# on this machine cannot leak in. The fake apt-get logs its last argument and
# the fake dpkg all of them; it prints $FAKE_AUDIT for --audit.
mkdir "$tmp/first" "$tmp/again"
cat >"$tmp/apt-get" <<'FAKE'
#!/bin/sh
for a; do :; done
echo "apt-get $a" >>"$FAKE_CALLS"
FAKE
cat >"$tmp/dpkg" <<'FAKE'
#!/bin/sh
echo "dpkg $*" >>"$FAKE_CALLS"
[ "$1" != --audit ] || printf '%s' "$FAKE_AUDIT"
FAKE
printf '#!/bin/sh\nexit 0\n' >"$tmp/tailscale"
chmod +x "$tmp/apt-get" "$tmp/dpkg" "$tmp/tailscale"
for dir in first again; do
	ln -s "$(command -v env)" "$tmp/$dir/env"
	cp "$tmp/apt-get" "$tmp/dpkg" "$tmp/$dir/"
done
cp "$tmp/tailscale" "$tmp/again/tailscale"
export FAKE_CALLS=$tmp/calls

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

# Sets status, stdout and stderr for the step on the given PATH.
run_step() {
	rm -f "$FAKE_CALLS"
	status=0
	stdout=$(PATH=$1 install_06_upgrade 2>"$tmp/stderr") || status=$?
	stderr=$(<"$tmp/stderr")
}

FAKE_AUDIT='The following packages are only half configured:
 tailscale  the tailnet client'
export FAKE_AUDIT
run_step "$tmp/first"
assert "no tailscale, dpkg broken: returns 0" [ "$status" -eq 0 ]
assert "no tailscale, dpkg broken: audits, repairs, updates, then upgrades" \
	[ "$(<"$FAKE_CALLS")" == $'dpkg --audit\ndpkg --force-confdef --force-confold --configure -a\napt-get update\napt-get full-upgrade' ]
assert "no tailscale, dpkg broken: says it is upgrading" [ "$stderr" == '==> upgrading installed packages' ]
assert "no tailscale, dpkg broken: keeps apt's output off stdout" [ -z "$stdout" ]

FAKE_AUDIT=
run_step "$tmp/first"
assert "no tailscale, dpkg healthy: returns 0" [ "$status" -eq 0 ]
assert "no tailscale, dpkg healthy: audits, does not repair, then updates and upgrades" \
	[ "$(<"$FAKE_CALLS")" == $'dpkg --audit\napt-get update\napt-get full-upgrade' ]

run_step "$tmp/again"
assert "tailscale installed: returns 0" [ "$status" -eq 0 ]
assert "tailscale installed: runs neither dpkg nor apt-get" [ ! -e "$FAKE_CALLS" ]
assert "tailscale installed: says it skips" \
	[ "$stderr" == '==> skipping the upgrade; unattended-upgrades keeps this server current' ]

((failures == 0))
