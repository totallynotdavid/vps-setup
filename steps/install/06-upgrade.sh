install_06_upgrade() {
	# Restarting tailscaled ends the Tailscale SSH session that runs the script.
	if command -v tailscale >/dev/null; then
		log "skipping the upgrade; unattended-upgrades keeps this server current"
		return 0
	fi
	log "upgrading installed packages"
	apt_repair
	apt_get update
	apt_get full-upgrade
}
