# shellcheck shell=bash
known_hosts_file() {
	printf '%s\n' "${TMPDIR:-/tmp}/vps-setup/known-hosts/$1"
}
