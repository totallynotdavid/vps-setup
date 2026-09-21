install_90_next_steps() {
	cat >&2 <<EOF_MSG

This node joined your tailnet as '$TS_HOSTNAME'.
EOF_MSG
	if [[ -e /var/run/reboot-required ]]; then
		cat >&2 <<'EOF_MSG'

This server needs a reboot for its updates. Do it now, as root, before
close-ssh, while public SSH is still open:

    reboot
EOF_MSG
	fi
	cat >&2 <<EOF_MSG

Next, from your own machine, verify Tailscale SSH works:

    ssh $ADMIN_USER@$TS_HOSTNAME

Then run close-ssh inside that session, as docs/manual-setup.md in
https://github.com/totallynotdavid/vps-setup describes. Public SSH stays open
until you do.
EOF_MSG
}
