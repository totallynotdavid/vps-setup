# vps-setup

vps-setup turns a fresh Ubuntu VPS that offers only root and a password into a
server reachable only through
[Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh).

It supports Ubuntu 20.04, 22.04, 24.04 and 26.04 and nothing else. Public SSH
stays open while it installs, and closes only after your own machine has logged
in over the tailnet.

It fits when you have a new server with root access over SSH, and a machine that
is already on your tailnet to run it from.

## Get started

Clone the repository, then run `bin/provision` from the machine on the tailnet:

```sh
git clone https://github.com/totallynotdavid/vps-setup && cd vps-setup
bin/provision root@203.0.113.7 web1
```

`root@203.0.113.7` is where to log in. The address is a placeholder from a range
reserved for documentation, so use your own server's. `web1` becomes the
Tailscale node name. Tailscale prints a login URL and waits ten minutes for you
to open it. The last line of the output is the `ssh` command to use from now on:

```text
ssh admin@web1
```

[Get started](./docs/get-started.md) lists the requirements and everything the
run prints.

## Features

- Creates an admin user with no password and passwordless sudo.
- Installs Tailscale from its apt repository and joins the tailnet with
  Tailscale SSH on.
- Turns on the ufw firewall. Everything incoming is denied except traffic on the
  tailnet interface.
- Keeps that promise for Docker containers if you install Docker later. No
  published port is open to the internet unless you open it with
  `ufw route allow`. See [Docker on this server](./docs/docker.md).
- Upgrades the server once, keeps Tailscale updated through apt, and reboots at
  04:00 when an update needs it. [Inputs](./docs/inputs.md) explains how to turn
  the reboot off.
- Logs in as the admin user over the tailnet, and stops there if that fails.
- Removes OpenSSH and locks the root password. After that, public SSH cannot be
  used to access the server. If Tailscale SSH stops working, reinstall the
  server from the provider's panel.
- Converges at every step, so running it again is safe.

## Documentation

The [manual](./docs/readme.md) indexes every procedure. Start with
[Get started](./docs/get-started.md).

## Contributing

See [Contributing](./.github/contributing.md).
