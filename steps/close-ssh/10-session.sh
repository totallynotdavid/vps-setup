close_ssh_10_session() {
	local pid=$PPID comm
	while ((pid > 1)); do
		comm=$(<"/proc/$pid/comm") || break
		case $comm in
		tailscaled) return 0 ;;
		sshd*) break ;;
		esac
		pid=$(session_parent_pid "$pid") || break
	done
	die "close-ssh must run directly in a Tailscale SSH session (tmux and screen break the process chain, OpenSSH is not enough)"
}

session_parent_pid() {
	ps -o ppid= -p "$1" | tr -d ' '
}
