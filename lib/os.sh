# Every release this installer is tested on, as "ID VERSION_ID", one per line.
supported_os() {
	printf '%s\n' "ubuntu 20.04" "ubuntu 22.04" "ubuntu 24.04" "ubuntu 26.04"
}

# /etc/os-release belongs to the target host, so ShellCheck cannot follow it.
os_field() {
	# shellcheck source=/dev/null
	(. /etc/os-release && printf '%s' "${!1:-}")
}

host_os() {
	printf '%s %s' "$(os_field ID)" "$(os_field VERSION_ID)"
}

os_is_supported() {
	local supported
	while read -r supported; do
		if [[ $1 == "$supported" ]]; then
			return 0
		fi
	done < <(supported_os)
	return 1
}

require_supported_os() {
	local found list
	found=$(host_os)
	os_is_supported "$found" && return 0
	list=$(supported_os | paste -sd, - | sed 's/,/, /g')
	die "unsupported OS '$found'; supported: $list"
}
