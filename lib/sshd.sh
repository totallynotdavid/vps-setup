sshd_installed() {
	[[ -x /usr/sbin/sshd ]]
}

# Prints the first port sshd listens on, 22 when sshd is absent.
sshd_port() {
	local port=
	if sshd_installed; then
		# sshd -T refuses to run without /run/sshd, and a stopped ssh.service leaves none.
		install -d -m 0755 /run/sshd
		port=$(/usr/sbin/sshd -T | awk '$1 == "port" && !p {p = $2} END {print p}') ||
			die "could not read the sshd port with 'sshd -T'"
	fi
	printf '%s\n' "${port:-22}"
}
