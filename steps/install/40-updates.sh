install_40_updates() {
	apt_get install unattended-upgrades
	printf '%s\n' \
		'APT::Periodic::Update-Package-Lists "1";' \
		'APT::Periodic::Unattended-Upgrade "1";' \
		>/etc/apt/apt.conf.d/20auto-upgrades
	updates_policy >/etc/apt/apt.conf.d/52vps-setup
	quiet systemctl enable --now unattended-upgrades
}

# Sorts after 50unattended-upgrades, so its lists add to the stock ones.
updates_policy() {
	printf '%s\n' 'Unattended-Upgrade::Origins-Pattern:: "origin=Tailscale,label=Tailscale";'
	if [[ $AUTO_REBOOT == off ]]; then
		printf '%s\n' 'Unattended-Upgrade::Automatic-Reboot "false";'
	else
		printf '%s\n' \
			'Unattended-Upgrade::Automatic-Reboot "true";' \
			"Unattended-Upgrade::Automatic-Reboot-Time \"$AUTO_REBOOT\";" \
			'Unattended-Upgrade::Automatic-Reboot-WithUsers "true";'
	fi
}
