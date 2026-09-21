# remove, never purge: purge deletes the host keys Tailscale SSH serves.
# Removing the package does not stop its units on every release; the socket goes first so it cannot restart the service.
close_ssh_30_openssh() {
	local unit
	for unit in ssh.socket ssh.service; do
		if systemctl cat "$unit" &>/dev/null; then
			quiet systemctl disable --now "$unit"
		fi
	done
	apt_get remove openssh-server openssh-sftp-server
}
