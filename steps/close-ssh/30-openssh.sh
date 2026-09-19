# remove, never purge: purge deletes the host keys Tailscale SSH serves.
close_ssh_30_openssh() {
	apt_get remove openssh-server openssh-sftp-server
}
