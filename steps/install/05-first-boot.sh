install_05_first_boot() {
	command -v cloud-init >/dev/null || return 0
	log "waiting for the provider's first-boot setup to finish"
	# The exit status is the provider's own config health, not ours to judge.
	# The timeout keeps a stuck provider from hanging install.
	timeout 600 cloud-init status --wait >/dev/null || true
}
