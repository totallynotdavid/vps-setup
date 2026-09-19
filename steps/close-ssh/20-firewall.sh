close_ssh_20_firewall() {
	local port
	port=$(sshd_port)
	quiet ufw delete limit "$port/tcp"
}
