close_ssh_20_firewall() {
	local port
	port=$(sshd_port)
	ufw delete limit "$port/tcp"
}
