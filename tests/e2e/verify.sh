#!/usr/bin/env bash
# Checks a real server from the operator's machine.
#   verify.sh installed|closed <tailnet-host> <admin-user> <public-ip>
set -euo pipefail

if (($# != 4)) || [[ $1 != installed && $1 != closed ]]; then
	echo "usage: verify.sh installed|closed <tailnet-host> <admin-user> <public-ip>" >&2
	exit 2
fi
mode=$1 host=$2 admin=$3 public_ip=$4

known_hosts=${TMPDIR:-/tmp}/vps-setup-e2e/$host
mkdir -p "$(dirname "$known_hosts")"
host_key_checking=yes
if [[ $mode == installed ]]; then
	# A new install starts a new cycle; drop any key from an earlier server with this name.
	rm -f "$known_hosts"
	host_key_checking=accept-new
fi

# Runs on the server; prints one key=value line per fact.
IFS= read -r -d '' remote_facts <<'REMOTE' || true
echo "sudo=$(sudo -n true 2>/dev/null && echo yes || echo no)"
echo "ufw_status=$(sudo -n ufw status verbose 2>&1 | grep -E '^(Status|Default):' | tr '\n' ' ')"
echo "unattended=$(systemctl is-active unattended-upgrades || true)"
echo "health=$(sudo -n tailscale status --json | python3 -c 'import json, sys; print("; ".join(json.load(sys.stdin).get("Health") or []))' || echo 'status unavailable')"
echo "sshd_installed=$([ -x /usr/sbin/sshd ] && echo yes || echo no)"
echo "ssh_socket=$(systemctl is-active ssh.socket || true)"
echo "ssh_service=$(systemctl is-active ssh.service || true)"
echo "listeners_22=$(ss -H -ltn 'sport = :22' | wc -l)"
echo "root_password=$(sudo -n passwd -S root | awk '{print $2}')"
REMOTE

declare -A facts
failures=0

collect_facts() {
	local output key value
	output=$(ssh -o BatchMode=yes -o ConnectTimeout=15 \
		-o "StrictHostKeyChecking=$host_key_checking" \
		-o "UserKnownHostsFile=$known_hosts" \
		"$admin@$host" "$remote_facts") || return 1
	while IFS='=' read -r key value; do
		[[ $key =~ ^[a-z0-9_]+$ ]] && facts[$key]=$value
	done <<<"$output"
	return 0
}

fact_is() {
	[[ -v facts[$1] && ${facts[$1]} == "$2" ]]
}

fact_has() {
	[[ -v facts[$1] && ${facts[$1]} == *"$2"* ]]
}

public_port_22_connects() {
	timeout 6 bash -c "exec 3<>/dev/tcp/$public_ip/22" 2>/dev/null
}

public_port_22_closed() {
	! public_port_22_connects
}

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

assert "tailnet ssh works ($host_key_checking host key checking)" collect_facts
assert "ufw is active" fact_has ufw_status "Status: active"
assert "ufw defaults to deny incoming" fact_has ufw_status "deny (incoming)"

case $mode in
installed)
	assert "sudo -n true works" fact_is sudo yes
	assert "unattended-upgrades is active" fact_is unattended active
	assert "Tailscale health is empty" fact_is health ""
	assert "sshd is installed" fact_is sshd_installed yes
	assert "public port 22 accepts a connection" public_port_22_connects
	;;
closed)
	assert "ssh.socket is inactive" fact_is ssh_socket inactive
	assert "ssh.service is inactive" fact_is ssh_service inactive
	assert "/usr/sbin/sshd is absent" fact_is sshd_installed no
	assert "nothing listens on :22" fact_is listeners_22 0
	assert "root password is locked" fact_is root_password L
	assert "public port 22 does not connect within 6 seconds" public_port_22_closed
	;;
esac

((failures == 0))
