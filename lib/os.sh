# /etc/os-release belongs to the target host, so ShellCheck cannot follow it.
os_field() {
	# shellcheck source=/dev/null
	(. /etc/os-release && printf '%s' "${!1:-}")
}

require_supported_os() {
	local found
	found="$(os_field ID) $(os_field VERSION_ID)"
	[[ $found == "ubuntu 26.04" ]] || die "unsupported OS '$found'; only ubuntu 26.04 is supported"
}
