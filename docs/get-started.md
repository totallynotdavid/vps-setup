# Get started

## Requirements

- A server running Ubuntu 20.04, 22.04, 24.04 or 26.04, and root access to it
  over SSH. Other releases are refused before anything changes.
  [Ubuntu 20.04 is past standard support](https://ubuntu.com/about/release-cycle):
  Canonical's release-cycle page lists its standard security maintenance as
  ended in May 2025 and covered by Ubuntu Pro since. The `unattended-upgrades`
  step installs and enables the service on 20.04 as on any release, but
  vps-setup does not attach Ubuntu Pro. That is yours to do.
- A Linux machine on the same tailnet, with `bash`, OpenSSH and `curl`. `curl`
  is used only to mint a key from an OAuth client, see [Auth key](./auth-key.md).
- A tailnet policy that lets that machine SSH to the server as the admin user.
  See [Tailnet policy](./tailnet-policy.md). Without it, the run stops at the
  first tailnet login.

## First run

Clone the repository and run `bin/provision` from your own machine:

```sh
git clone https://github.com/totallynotdavid/vps-setup && cd vps-setup
ADMIN_USER=ops TS_TAGS=tag:server bin/provision --key ./oauth.key root@203.0.113.7 web1
```

`root@203.0.113.7` is where to log in. That address is a placeholder from a
range reserved for documentation, so use your own server's address. `web1`
becomes the Tailscale node name.
`ADMIN_USER` and `TS_TAGS` are optional, and `ADMIN_USER` defaults to `admin`.
[Inputs](./inputs.md) lists every variable.

Without `--key`, `tailscale up` prints a login URL and waits ten minutes for
you to open it. With `--key`, the run needs no browser. See
[Auth key](./auth-key.md) for what the file holds.

`bin/provision` does this, in order:

1. Builds `dist/install.sh` from the source in this repository.
2. Connects as root. `ssh` asks for the root password once, and the connection
   is reused.
3. Runs `install` on the server.
4. If the upgrade left `/var/run/reboot-required`, reboots the server and waits
   up to five minutes for root SSH to answer again. `ssh` asks for the root
   password again.
5. Waits up to 90 seconds for `ops@web1` to answer over the tailnet, then checks
   the server from outside.
6. Runs `close-ssh` through that tailnet session, then checks that public SSH
   is closed.

On a server that has just booted, `install` waits for the provider's first-boot
setup to finish, then upgrades every package. Each can take a few minutes.
Nothing is wrong. See [How it works](./how-it-works.md) for the detail.

The checks in step 5 run before anything is closed. If one fails,
`bin/provision` stops with public SSH still open.
[How it works](./how-it-works.md) says what each step does on the server, and
why in that order.

## What it prints

Each step logs a line that starts with `==>`. The checks print `PASS` or `FAIL`
lines. The `reboot` line appears only when the upgrade asks for a reboot. A run
with `--key` looks like this, abbreviated:

```text
==> resolve the auth key
==> build dist/install.sh
==> connect to root@203.0.113.7
==> copy the auth key
==> install
==> install_00_config
==> install_05_first_boot
==> waiting for the provider's first-boot setup to finish
==> install_06_upgrade
==> upgrading installed packages
==> install_10_user
==> install_20_tailscale
==> install_30_firewall
==> install_40_updates
==> install_90_next_steps
==> reboot root@203.0.113.7
==> wait for ops@web1 on the tailnet
==> verify the tailnet path
PASS tailnet ssh works (accept-new host key checking)
...
==> close SSH through the tailnet session
==> close_ssh_10_session
==> close_ssh_20_firewall
==> close_ssh_30_openssh
==> close_ssh_40_root
==> verify SSH is closed
PASS tailnet ssh works (yes host key checking)
...
ssh ops@web1
```

Commands that only need to succeed print nothing unless they fail, and then
they print everything they wrote. `tailscale up` is the exception: it prints its
login or approval prompt and waits. `install` ends with a message written for
the [manual flow](./manual-setup.md). `bin/provision` does what it asks.

## If it stops

| Error message | Public SSH | What to do |
| ------------- | ---------- | ---------- |
| `install failed` | open | Read the output above it. Fix the cause and run again. |
| `did not answer root SSH after the reboot` | open | Check the server in the provider's panel. Then run again. |
| `ops@web1 did not answer over the tailnet` | open | The message shows ssh's last error. See [Tailnet policy](./tailnet-policy.md). |
| `verification failed` | open | The `FAIL` lines say which check. |
| `close-ssh failed` | may be closed | Run `close-ssh` again, as [Manual setup](./manual-setup.md) shows. Repeating it is safe. |

## Reach the server afterwards

```sh
ssh ops@web1
```

The root password is locked and OpenSSH is gone, so this is the only way in.
`bin/provision` records the host key under `$TMPDIR/vps-setup-e2e/web1`, or
`/tmp/vps-setup-e2e/web1`, and leaves `~/.ssh/known_hosts` alone. Closing SSH
keeps the host key, because OpenSSH is removed and not purged, so a key learned
before the close still matches after it.
