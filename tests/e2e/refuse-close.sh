#!/usr/bin/env bash
# Scenario: close-ssh run over OpenSSH must be refused and change nothing.
#   refuse-close.sh <root@host> <name> --key FILE
# Installs as bin/provision does, then runs close-ssh over the same root SSH
# session, which is the operator mistake that would lock them out.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)

usage() {
	echo "usage: refuse-close.sh <root@host> <name> --key FILE" >&2
	exit 2
}

log() {
	printf '==> %s\n' "$*" >&2
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

key_file=
args=()
while (($#)); do
	case $1 in
	--key)
		(($# >= 2)) || usage
		key_file=$2
		shift 2
		;;
	-*) usage ;;
	*)
		args+=("$1")
		shift
		;;
	esac
done
((${#args[@]} == 2)) && [[ -n $key_file ]] || usage
target=${args[0]} name=${args[1]}
[[ $target == root@?* && $target != *@*@* && -n $name ]] || usage
[[ -f $key_file ]] || die "--key '$key_file' is not a file"

admin=${ADMIN_USER:-admin}

tmp=$(mktemp -d)
key_on_server=0
root_opts=(-o "ControlPath=$tmp/control" -o "UserKnownHostsFile=$tmp/known_hosts" -o StrictHostKeyChecking=accept-new)

root_ssh() {
	ssh "${root_opts[@]}" -o ControlMaster=no "$target" "$@"
}

remove_key() {
	((key_on_server)) || return 0
	if root_ssh 'rm -f /root/ts.key' </dev/null; then
		key_on_server=0
	else
		echo "error: could not remove /root/ts.key from $target; delete it by hand" >&2
		return 1
	fi
}

cleanup() {
	local status=$?
	remove_key || true
	ssh "${root_opts[@]}" -O exit "$target" &>/dev/null || true
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

close_status=0
close_output=
root_state=

IFS= read -r -d '' remote_facts <<'REMOTE' || true
echo "sshd_installed=$([ -x /usr/sbin/sshd ] && echo yes || echo no)"
echo "root_password=$(passwd -S root | awk '{print $2}')"
REMOTE

close_was_refused() {
	((close_status != 0 && close_status != 255))
}

close_output_names_tailscale_ssh() {
	[[ $close_output == *"Tailscale SSH session"* ]]
}

sshd_still_installed() {
	[[ $root_state == *"sshd_installed=yes"* ]]
}

root_password_unlocked() {
	[[ $root_state == *"root_password=P"* ]]
}

log "build dist/install.sh"
"$repo/build"

log "connect to $target"
ssh "${root_opts[@]}" -o ControlMaster=yes -o ControlPersist=30m "$target" true

log "copy the auth key"
key_on_server=1
root_ssh 'umask 077; cat >/root/ts.key' <"$key_file"

log "install"
remote_env=$(printf 'ADMIN_USER=%q TS_HOSTNAME=%q TS_TAGS=%q TS_AUTHKEY_FILE=/root/ts.key' "$admin" "$name" "${TS_TAGS:-}")
root_ssh "$remote_env bash -s install" <"$repo/dist/install.sh" || die "install failed"
remove_key

log "close-ssh over root's OpenSSH session"
close_output=$(root_ssh 'bash -s close-ssh' <"$repo/dist/install.sh" 2>&1) || close_status=$?
printf '%s\n' "$close_output" >&2

log "check what is left"
root_state=$(root_ssh "$remote_facts" </dev/null) ||
	die "could not read the server state over root's SSH session; close-ssh may have closed it"

assert "close-ssh exits non-zero (exit $close_status)" close_was_refused
assert "the message says to run it in a Tailscale SSH session" close_output_names_tailscale_ssh
assert "sshd is still installed" sshd_still_installed
assert "root's password is not locked" root_password_unlocked

((failures == 0))
