install_30_firewall() {
	local port
	apt_get install ufw
	ufw default deny incoming
	ufw default allow outgoing
	ufw allow in on tailscale0
	if sshd_installed; then
		port=$(sshd_port)
		ufw limit "$port/tcp"
	fi
	ufw --force enable
}
