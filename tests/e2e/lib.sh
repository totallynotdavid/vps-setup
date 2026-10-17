# shellcheck shell=bash
# shellcheck disable=SC2154 # admin, name and known_hosts come from the scenario.
failures=0

log() {
	printf '==> %s\n' "$*" >&2
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
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

tailnet_ssh() {
	ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=yes \
		-o "UserKnownHostsFile=$known_hosts" "$admin@$name" "$@"
}

# One command line on the server, as root, with no stdin.
on_server() {
	tailnet_ssh "sudo $*" </dev/null
}

wait_for_reboot() {
	local boot_before=$1 boot_now deadline=$((SECONDS + ${2:-180}))
	while ((SECONDS < deadline)); do
		boot_now=$(tailnet_ssh 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null </dev/null) || boot_now=
		if [[ -n $boot_now && $boot_now != "$boot_before" ]]; then
			return 0
		fi
		sleep 3
	done
	return 1
}
