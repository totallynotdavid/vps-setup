#!/usr/bin/env bash
# Scenario: a sidecar that joins another container's network namespace is up
# after a reboot.
#   sidecar.sh <root@host> <name> --key FILE
# Runs nginx and a network_mode: service:web sidecar under systemd/compose@.service,
# reboots, and checks that both run and still share one namespace.
set -euo pipefail

cd "$(dirname "$0")/../.."
# shellcheck source-path=SCRIPTDIR/../../bin/lib
source bin/lib/known-hosts.sh
# shellcheck source-path=SCRIPTDIR/../..
source tests/e2e/install-docker.sh

usage() {
	echo "usage: sidecar.sh <root@host> <name> --key FILE" >&2
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
((${#args[@]} == 2 && ${#key_args[@]} > 0)) || usage
target=${args[0]} name=${args[1]}

admin=${ADMIN_USER:-admin}
public_ip=${target#*@}
known_hosts=$(known_hosts_file "$name")
stack=sidecar-test

tailnet_ssh() {
	ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=yes \
		-o "UserKnownHostsFile=$known_hosts" "$admin@$name" "$@"
}

on_server() {
	tailnet_ssh "sudo $*" </dev/null
}

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

container_running() {
	[[ $(on_server "docker inspect --format '{{.State.Running}}' $stack-$1-1") == true ]]
}

shares_namespace() {
	[[ $(on_server "docker exec $stack-web-1 readlink /proc/1/ns/net") == "$(on_server "docker exec $stack-sidecar-1 readlink /proc/1/ns/net")" ]]
}

sidecar_reaches_web() {
	on_server "docker exec $stack-sidecar-1 wget -qO /dev/null http://127.0.0.1:80/"
}

unit_active() {
	[[ $(on_server "systemctl is-active compose@$stack.service" || true) == active ]]
}

wait_for_reboot() {
	local boot_before=$1 boot_now deadline=$((SECONDS + 180))
	while ((SECONDS < deadline)); do
		boot_now=$(tailnet_ssh 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null </dev/null) || boot_now=
		if [[ -n $boot_now && $boot_now != "$boot_before" ]]; then
			return 0
		fi
		sleep 3
	done
	return 1
}

# The unit finishes when `docker compose up --wait` does, so active means both are up.
wait_for_unit() {
	local deadline=$((SECONDS + 300))
	until unit_active 2>/dev/null; do
		((SECONDS < deadline)) || return 1
		sleep 3
	done
}

check_stack() {
	local when=$1
	assert "$when: compose@$stack is active" unit_active
	assert "$when: the web container runs" container_running web
	assert "$when: the sidecar runs" container_running sidecar
	assert "$when: the sidecar shares the web container's network namespace" shares_namespace
	assert "$when: the sidecar reaches nginx on 127.0.0.1" sidecar_reaches_web
}

log "provision"
bin/provision "${key_args[@]}" "$target" "$name"

log "install Docker"
install_docker >&2 || fail "could not install Docker"

log "install the unit and the stack"
tailnet_ssh 'sudo tee /etc/systemd/system/compose@.service >/dev/null' <systemd/compose@.service
tailnet_ssh "sudo mkdir -p /srv/compose/$stack" </dev/null
tailnet_ssh "sudo tee /srv/compose/$stack/compose.yaml >/dev/null" <<'EOF_COMPOSE'
services:
  web:
    image: nginx:alpine
    restart: unless-stopped
  sidecar:
    image: nginx:alpine
    entrypoint: ["sleep", "infinity"]
    network_mode: service:web
    depends_on: [web]
    restart: unless-stopped
EOF_COMPOSE
on_server "docker compose --project-directory /srv/compose/$stack pull -q" >&2
on_server 'systemctl daemon-reload'
on_server "systemctl enable --now compose@$stack.service" >&2
check_stack "at first"

log "reboot"
boot_id=$(tailnet_ssh 'cat /proc/sys/kernel/random/boot_id' </dev/null)
on_server 'systemctl reboot' || true
wait_for_reboot "$boot_id" || fail "$name did not come back within three minutes"
wait_for_unit || fail "compose@$stack did not become active within five minutes of the reboot"
check_stack "after a reboot"

log "verify the closed state"
bin/verify closed "$name" "$admin" "$public_ip" || failures=$((failures + 1))

((failures == 0))
