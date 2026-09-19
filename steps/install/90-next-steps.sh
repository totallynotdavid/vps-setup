install_90_next_steps() {
	cat >&2 <<EOF_MSG

This node joined your tailnet as '$TS_HOSTNAME'.

Next, from your own machine, verify Tailscale SSH works:

    ssh $ADMIN_USER@$TS_HOSTNAME

Then run close-ssh inside that session, as the README describes. Public SSH
stays open until you do.
EOF_MSG
}
