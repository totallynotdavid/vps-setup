# shellcheck shell=bash
# Installs Docker on the server through the caller's tailnet_ssh, with the IPv6
# settings the scenarios need.
install_docker() {
	# On a release Docker does not ship every package for (20.04). get.docker.com
	# sets up the repository and then fails on a missing plugin, so install the
	# engine by name. unattended-upgrades can hold the apt locks and its daemon
	# never exits, so retry the install instead of waiting for it.
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
