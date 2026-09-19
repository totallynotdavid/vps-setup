install_30_firewall() {
	local port
	apt_get install ufw
	quiet ufw default deny incoming
	quiet ufw default allow outgoing
	quiet ufw allow in on tailscale0
	if sshd_installed; then
		port=$(sshd_port)
		quiet ufw limit "$port/tcp"
	fi
	quiet ufw --force enable
}
