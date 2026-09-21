# vps-setup

vps-setup turns a fresh Ubuntu VPS that offers only root and a password
into a server reachable only through [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh).
It supports Ubuntu 20.04, 22.04, 24.04 and 26.04 and nothing else. Public SSH stays open while it
installs, and closes only after your own machine has logged in over the tailnet.

Clone the repository, then run `bin/provision` from a machine on the same
tailnet:

```sh
git clone https://github.com/totallynotdavid/vps-setup && cd vps-setup
bin/provision root@203.0.113.7 web1
```

`root@203.0.113.7` is where to log in, and it is a placeholder from a range
reserved for documentation, so use your own server's address. `web1` becomes the
Tailscale node name. Tailscale prints a login URL and waits ten minutes for you
to open it. The last line of the output is the `ssh` command to use from now on.

## What it does

- Creates an admin user with no password and passwordless sudo.
- Installs Tailscale from its apt repository and joins the tailnet with
  Tailscale SSH on.
- Turns on the ufw firewall: everything incoming is denied except traffic on
  the tailnet interface.
- Upgrades the server once, keeps Tailscale updated through apt, and reboots at
  04:00 when an update needs it. [Inputs](./docs/inputs.md) says how to turn the
  reboot off.
- Logs in as the admin user over the tailnet, and stops there if that fails.
- Removes OpenSSH and locks the root password.

Every step converges, so running it again is safe.

## Where it stops

There is no other Ubuntu release, no other way in than Tailscale SSH, no sshd
hardening, no fail2ban and no way back in through public SSH once it is closed.
If Tailscale SSH stops working, you reinstall the server from the provider's
panel. [Design boundaries](./docs/design-boundaries.md) gives the reason for
each.

## Documentation

The [manual](./docs/readme.md) covers the first run, the same flow by hand, the
inputs, auth keys, the tailnet policy, what happens on the server and how to
test it. Start with [Get started](./docs/get-started.md).

## Contributing

See [contributing.md](./contributing.md).
