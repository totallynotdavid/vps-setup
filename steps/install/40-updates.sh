install_40_updates() {
	apt_get install unattended-upgrades
	printf '%s\n' \
		'APT::Periodic::Update-Package-Lists "1";' \
		'APT::Periodic::Unattended-Upgrade "1";' \
		>/etc/apt/apt.conf.d/20auto-upgrades
	systemctl enable --now unattended-upgrades
}
