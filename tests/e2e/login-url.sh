#!/usr/bin/env bash
# Scenario: the login-URL mode, and a node that never joins.
#   login-url.sh <root@host> <name>
# Runs bin/provision without --key and never opens the URL, as a node held for
# device approval waits. Checks that the URL is printed, the install gives up
# after ten minutes, and public SSH and root stay usable.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)

usage() {
	echo "usage: login-url.sh <root@host> <name>" >&2
	exit 2
}

log() {
	printf '==> %s\n' "$*" >&2
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

(($# == 2)) || usage
target=$1 name=$2
[[ $target == root@?* && $target != *@*@* && -n $name ]] || usage
public_ip=${target#root@}

tmp=$(mktemp -d)
provision_pid=
cleanup() {
	local status=$?
	if [[ -n $provision_pid ]]; then
		kill "$provision_pid" 2>/dev/null || true
		wait "$provision_pid" 2>/dev/null || true
	fi
	rm -rf "$tmp"
	exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

failures=0

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

# The join timeout is ten minutes. Allow it to end 90 seconds early or late for
# the time ssh and the earlier steps take.
min_wait=510 max_wait=690
login_url_re='https://login\.tailscale\.com/a/[A-Za-z0-9]+'

output_has() {
	grep -Eq -- "$1" "$tmp/output"
}

output_lacks() {
	! output_has "$1"
}

waited_about_ten_minutes() {
	((waited >= min_wait && waited <= max_wait))
}

provision_is_waiting() {
	kill -0 "$provision_pid" 2>/dev/null
}

wait_for_login_url() {
	local deadline=$((SECONDS + 300))
	until output_has "$login_url_re"; do
		provision_is_waiting || return 1
		((SECONDS < deadline)) || return 1
		sleep 2
	done
}

# The URL only shows once the server has installed Tailscale, so this is the
# start of the ten minutes.
log "bin/provision without --key"
(cd "$repo" && exec bin/provision "$target" "$name") >"$tmp/output" 2>&1 &
provision_pid=$!

log "wait for the login URL"
url_found=0
wait_for_login_url && url_found=1
assert "the login URL is printed" [ "$url_found" -eq 1 ]
((url_found)) || {
	cat "$tmp/output" >&2
	die "no login URL appeared"
}
url_seconds=$SECONDS

log "nobody opens the URL; wait for the join to time out"
status=0
wait "$provision_pid" || status=$?
provision_pid=
waited=$((SECONDS - url_seconds))
cat "$tmp/output" >&2

assert "provision exits non-zero (exit $status)" [ "$status" -ne 0 ]
assert "provision waited about ten minutes for the join (${waited}s)" waited_about_ten_minutes
assert "provision says public SSH is still open" output_has 'public SSH is still open and nothing was closed'
assert "provision did not go on to the tailnet check" output_lacks '==> wait for .* on the tailnet'

# The server is checked over root's password, as aws.sh set it up.
IFS= read -r -d '' remote_facts <<'REMOTE' || true
echo "sshd_installed=$([ -x /usr/sbin/sshd ] && echo yes || echo no)"
echo "root_password=$(passwd -S root | awk '{print $2}')"
echo "backend=$(tailscale status --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["BackendState"])')"
REMOTE
root_state=$(ssh -n -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -o ConnectTimeout=15 \
	-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
	"$target" "$remote_facts") || die "could not read the server state over root's SSH session"

state_has() {
	[[ $root_state == *"$1"* ]]
}

public_port_22_connects() {
	timeout 6 bash -c "exec 3<>/dev/tcp/$public_ip/22" 2>/dev/null
}

assert "sshd is still installed" state_has "sshd_installed=yes"
assert "root's password is not locked" state_has "root_password=P"
assert "Tailscale is waiting for a login, not running" state_has "backend=NeedsLogin"
assert "public port 22 accepts a connection" public_port_22_connects

((failures == 0))
