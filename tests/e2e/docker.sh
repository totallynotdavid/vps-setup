#!/usr/bin/env bash
# Scenario: ufw's promise holds for containers.
#   docker.sh <root@host> <name> --key FILE
# Provisions the server, installs Docker on it, publishes nginx three ways and
# checks that a client arriving on a public interface cannot reach any of them.
# The public interface is a veth pair with one end in a network namespace.
set -euo pipefail

cd "$(dirname "$0")/../.."
# shellcheck source-path=SCRIPTDIR/../..
source tests/e2e/known-hosts.sh

usage() {
	echo "usage: docker.sh <root@host> <name> --key FILE" >&2
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
known_hosts=$(e2e_known_hosts "$name")

# The RFC 5737 and ULA ranges below stand in for the public internet.
host_v4=203.0.113.1 client_v4=203.0.113.2
host_v6=fd00:203::1 client_v6=fd00:203::2
plain_port=8080 ingress_port=8081 host_mode_port=8082

tailnet_ssh() {
	ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=yes \
		-o "UserKnownHostsFile=$known_hosts" "$admin@$name" "$@"
}

# One command line on the server, as root, with no stdin.
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

# curl exit 28 is a timeout, which is what a DROP looks like. Any other failure
# (refused, unreachable, ssh itself) means the test did not measure the guard.
LOCAL_CURL='curl -fsS -m 4 -o /dev/null'
NS_CURL='ip netns exec ext curl -fsS -m 4 -o /dev/null'

answers_locally() {
	on_server "$LOCAL_CURL http://127.0.0.1:$1/"
}

answers_from_outside() {
	on_server "$NS_CURL http://$host_v4:$1/"
}

answers_from_outside_v6() {
	on_server "$NS_CURL -g -6 'http://[$host_v6]:$1/'"
}

timed_out() {
	local status=0
	"$@" 2>/dev/null || status=$?
	((status == 28))
}

# The same checks after every event that could rebuild Docker's rules. Answering
# on 127.0.0.1 shows the container is up, so a timeout elsewhere is the guard.
check_refused() {
	local when=$1 port
	for port in "$plain_port" "$ingress_port" "$host_mode_port"; do
		assert "$when: 127.0.0.1:$port answers on the server" answers_locally "$port"
		assert "$when: $host_v4:$port times out from the public interface" timed_out answers_from_outside "$port"
	done
	assert "$when: [$host_v6]:$plain_port times out from the public interface" timed_out answers_from_outside_v6 "$plain_port"
}

wait_for_local() {
	local port=$1 deadline=$((SECONDS + 240))
	until answers_locally "$port" 2>/dev/null; do
		((SECONDS < deadline)) || fail "port $port did not answer on 127.0.0.1 within four minutes"
		sleep 3
	done
}

wait_for_containers() {
	wait_for_local "$plain_port"
	wait_for_local "$ingress_port"
	wait_for_local "$host_mode_port"
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

# The veth pair and the namespace are gone after a reboot, so this runs again then.
# nodad skips IPv6 duplicate address detection, which would delay the first packet.
build_public_interface() {
	tailnet_ssh 'sudo bash -s' <<REMOTE
set -euo pipefail
ip netns del ext 2>/dev/null || true
ip link del pub0 2>/dev/null || true
ip netns add ext
ip link add pub0 type veth peer name ext0
ip link set ext0 netns ext
ip addr add $host_v4/24 dev pub0
ip addr add $host_v6/64 dev pub0 nodad
ip link set pub0 up
ip netns exec ext ip addr add $client_v4/24 dev ext0
ip netns exec ext ip addr add $client_v6/64 dev ext0 nodad
ip netns exec ext ip link set ext0 up
ip netns exec ext ip link set lo up
REMOTE
}

install_docker() {
	# On a release Docker no longer ships every package for (20.04), the script sets
	# up the repository and then fails on a missing plugin, so the engine is installed
	# by name. unattended-upgrades can hold the apt locks and its daemon never exits,
	# so the install is tried again instead of waited for.
	tailnet_ssh 'sudo bash -s' <<'REMOTE'
set -euo pipefail
mkdir -p /etc/docker
printf '%s\n' '{"ipv6": true, "fixed-cidr-v6": "fd00:d0c::/64", "ip6tables": true}' >/etc/docker/daemon.json
curl -fsSL https://get.docker.com | sh && exit 0
for _ in 1 2 3; do
	sleep 30
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io && exit 0
done
exit 1
REMOTE
}

# The plain container restarts after a reboot, so its port is still there to test.
start_containers() {
	local private_ip
	private_ip=$(on_server "ip -4 route get 192.0.2.1" | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')
	[[ -n $private_ip ]] || fail "could not read the server's private address"
	on_server "docker swarm init --advertise-addr $private_ip" >/dev/null
	on_server "docker run -d --name plain --restart unless-stopped -p $plain_port:80 nginx:alpine" >/dev/null
	on_server "docker service create --name ingress --publish published=$ingress_port,target=80 nginx:alpine" >/dev/null
	on_server "docker service create --name hostmode --publish published=$host_mode_port,target=80,mode=host nginx:alpine" >/dev/null
}

log "provision"
bin/provision "${key_args[@]}" "$target" "$name"

log "install Docker"
install_docker >&2 || fail "could not install Docker"
log "$(on_server 'docker version --format "Docker {{.Server.Version}}"')"

log "publish nginx three ways, and add a public interface"
start_containers
build_public_interface
wait_for_containers

log "a client on the public interface"
check_refused "at first"

# The control: with the chain empty, the same client gets in. It shows this test
# can see a bypass, so the timeouts above and below are the guard's doing.
# ufw reload fills the chain again, because the block declares it.
log "control: without the guard"
on_server 'iptables -F DOCKER-USER'
on_server 'ip6tables -F DOCKER-USER'
for port in "$plain_port" "$ingress_port" "$host_mode_port"; do
	assert "control: 127.0.0.1:$port answers on the server" answers_locally "$port"
	assert "control: $host_v4:$port answers from the public interface" answers_from_outside "$port"
done
if answers_from_outside_v6 "$plain_port" 2>/dev/null; then
	log "control: [$host_v6]:$plain_port answers from the public interface"
else
	log "control: [$host_v6]:$plain_port does not answer from the public interface"
fi
on_server 'ufw reload' >&2
check_refused "after the control"

log "container outbound"
assert "a container reaches the internet" \
	on_server 'docker run --rm curlimages/curl -fsS -m 8 -o /dev/null https://checkip.amazonaws.com'

# The rule names the container's port, because DNAT has already happened. That
# opens the plain and the host-mode container, which both listen on 80.
log "ufw route allow, the container's port"
on_server 'ufw route allow proto tcp from any to any port 80' >&2
assert "$host_v4:$plain_port answers after the route rule" answers_from_outside "$plain_port"
assert "[$host_v6]:$plain_port answers after the route rule" answers_from_outside_v6 "$plain_port"
assert "$host_v4:$host_mode_port answers after the route rule" answers_from_outside "$host_mode_port"
on_server 'ufw route delete allow proto tcp from any to any port 80' >&2
assert "$host_v4:$plain_port times out after the rule is deleted" timed_out answers_from_outside "$plain_port"
assert "[$host_v6]:$plain_port times out after the rule is deleted" timed_out answers_from_outside_v6 "$plain_port"
assert "$host_v4:$host_mode_port times out after the rule is deleted" timed_out answers_from_outside "$host_mode_port"

# For an ingress service the port that ufw sees is the published one.
log "ufw route allow, the published port of the ingress service"
on_server "ufw route allow proto tcp from any to any port $ingress_port" >&2
assert "$host_v4:$ingress_port answers after the route rule" answers_from_outside "$ingress_port"
on_server "ufw route delete allow proto tcp from any to any port $ingress_port" >&2
assert "$host_v4:$ingress_port times out after the rule is deleted" timed_out answers_from_outside "$ingress_port"

log "ufw reload"
on_server 'ufw reload' >&2
check_refused "after ufw reload"

log "restart Docker"
on_server 'systemctl restart docker'
wait_for_containers
check_refused "after systemctl restart docker"

log "reboot"
boot_id=$(tailnet_ssh 'cat /proc/sys/kernel/random/boot_id' </dev/null)
on_server 'systemctl reboot' || true
wait_for_reboot "$boot_id" || fail "$name did not come back within three minutes"
build_public_interface
wait_for_containers
check_refused "after a reboot"

log "verify the closed state, guard included"
tests/e2e/verify.sh closed "$name" "$admin" "$public_ip" || failures=$((failures + 1))

((failures == 0))
