usage() {
	cat <<'EOF_USAGE'
usage: install.sh install | close-ssh | -h|--help

  install      turn this server into one reachable only through Tailscale SSH
  close-ssh    remove OpenSSH and lock root; run it inside a Tailscale SSH session

environment for install:
  ADMIN_USER       admin account to create (default: admin)
  TS_HOSTNAME      Tailscale node name, required, e.g. web1
  TS_TAGS          comma-separated tags, e.g. tag:server (default: none)
  TS_AUTHKEY_FILE  file holding a Tailscale auth key (default: log in by URL)
  AUTO_REBOOT      time of the automatic reboot after updates, HH:MM, or off
                   (default: 04:00)
EOF_USAGE
}

run_phase() {
	local step
	require_supported_os
	require_root
	for step in "$@"; do
		log "$step"
		"$step"
	done
}

main() {
	if (($# != 1)); then
		usage >&2
		exit 2
	fi
	case $1 in
	install) run_phase "${install_steps[@]}" ;;
	close-ssh) run_phase "${close_ssh_steps[@]}" ;;
	-h | --help) usage ;;
	*)
		usage >&2
		exit 2
		;;
	esac
}
