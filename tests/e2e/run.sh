#!/usr/bin/env bash
# Repeatable end-to-end run for a freshly reinstalled server:
#   run.sh <root@host> <name> [--key FILE]
# Provisions it, re-runs install and close-ssh through the tailnet session,
# reboots, and checks the closed state again.
set -euo pipefail

cd "$(dirname "$0")/../.."
# shellcheck source-path=SCRIPTDIR/../..
source tests/e2e/known-hosts.sh

usage() {
	echo "usage: run.sh <root@host> <name> [--key FILE]" >&2
	exit 2
}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

log() {
	printf '==> %s\n' "$*" >&2
}

key_args=()
args=()
while (($#)); do
	case $1 in
	--key)
		(($# >= 2)) || usage
		key_args=(--key "$2")
		shift 2
		;;
	-*) usage ;;
	*)
		args+=("$1")
		shift
		;;
	esac
done
((${#args[@]} == 2)) || usage
target=${args[0]} name=${args[1]}

admin=${ADMIN_USER:-admin}
public_ip=${target#*@}
known_hosts=$(e2e_known_hosts "$name")
remote_env=$(printf 'ADMIN_USER=%q TS_HOSTNAME=%q TS_TAGS=%q AUTO_REBOOT=%q' "$admin" "$name" "${TS_TAGS:-}" "${AUTO_REBOOT:-}")

tailnet_ssh() {
	ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=yes \
		-o "UserKnownHostsFile=$known_hosts" "$admin@$name" "$@"
}

# Everything install and close-ssh could touch, one line per fact.
IFS= read -r -d '' remote_state <<'REMOTE' || true
sudo -n ufw status verbose
sudo -n passwd -S root
sudo -n sh -c 'sha256sum /etc/sudoers.d/* /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/52vps-setup'
[ -x /usr/sbin/sshd ] && echo "sshd installed" || echo "sshd absent"
tailscale ip -4
dpkg-query -W | sha256sum
REMOTE

wait_for_reboot() {
	local boot_before=$1 boot_now deadline=$((SECONDS + 120))
	while ((SECONDS < deadline)); do
		boot_now=$(tailnet_ssh 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null) || boot_now=
		if [[ -n $boot_now && $boot_now != "$boot_before" ]]; then
			return 0
		fi
		sleep 3
	done
	return 1
}

log "provision"
bin/provision "${key_args[@]}" "$target" "$name"

log "state after provision"
before=$(tailnet_ssh "$remote_state")

log "install again through the tailnet"
tailnet_ssh "sudo env $remote_env bash -s install" <dist/install.sh || fail "the second install failed"
log "close-ssh again through the tailnet"
tailnet_ssh 'sudo bash -s close-ssh' <dist/install.sh || fail "the second close-ssh failed"

log "compare state"
after=$(tailnet_ssh "$remote_state")
if [[ $before != "$after" ]]; then
	diff <(echo "$before") <(echo "$after") >&2 || true
	fail "install and close-ssh changed the server on the second run"
fi

log "reboot"
boot_id=$(tailnet_ssh 'cat /proc/sys/kernel/random/boot_id')
tailnet_ssh 'sudo systemctl reboot' || true
wait_for_reboot "$boot_id" || fail "$name did not come back within two minutes"

log "verify SSH is still closed"
tests/e2e/verify.sh closed "$name" "$admin" "$public_ip"
