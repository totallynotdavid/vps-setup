close_ssh_40_root() {
	passwd -l root
	cat >&2 <<EOF_MSG

Public SSH is closed and root is locked. If Tailscale SSH stops working, the
only recovery is a reinstall from the provider's panel.
EOF_MSG
}
