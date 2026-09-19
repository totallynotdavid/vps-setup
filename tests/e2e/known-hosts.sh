# shellcheck shell=bash
# The one place that decides where the tailnet host key of <name> is remembered.
e2e_known_hosts() {
	printf '%s\n' "${TMPDIR:-/tmp}/vps-setup-e2e/$1"
}
