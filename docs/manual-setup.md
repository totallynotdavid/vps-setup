# Manual setup

The same flow as `bin/provision`, one step at a time, without cloning the
repository. Use it when you cannot run `bin/provision` from a machine on the
tailnet. The variables are in [Inputs](./inputs.md).

## 1. Install

On the server, as root, download the script and its checksum, check it, and run
`install`:

```sh
curl -fsSLO https://github.com/totallynotdavid/vps-setup/releases/latest/download/install.sh
curl -fsSLO https://github.com/totallynotdavid/vps-setup/releases/latest/download/install.sh.sha256
sha256sum -c install.sh.sha256
ADMIN_USER=ops TS_HOSTNAME=web1 bash install.sh install
```

`TS_HOSTNAME` is required. Without `TS_AUTHKEY_FILE`, `tailscale up` prints a
login URL and waits ten minutes for you to open it. To skip the browser, see
[Auth key](./auth-key.md).

The checksum catches a truncated or corrupted download. It is published next to
the script, so it does not catch a compromised release.

`curl -fsSL https://github.com/totallynotdavid/vps-setup/releases/latest/download/install.sh | bash -s install`
does the same without the checksum. A truncated download runs nothing, because
the script's last line is the call that starts it.

`install` ends by telling you the `ssh` command to try next, and that public SSH
stays open until you close it. If it also says the server needs a reboot, run
`reboot` as root and wait until the server is back before you go on. The reboot
comes before `close-ssh`, so a server that does not return on the tailnet still
has root SSH.

## 2. Verify

From your own machine, which must be on the tailnet and allowed by your
[tailnet policy](./tailnet-policy.md):

```sh
ssh ops@web1
```

If this does not work, do not go on. Root and its password still work over
public SSH, so nothing is lost.

## 3. Close SSH

Inside that session, download and check the script again, then run:

```sh
sudo bash install.sh close-ssh
```

`close-ssh` refuses to run anywhere but a Tailscale SSH session. Run it directly
in the session: tmux and screen hide the session from it. It refuses to run
over OpenSSH, so the mistake that would lock you out fails instead.

It removes OpenSSH, deletes its firewall rule and locks the root password. Log
out and in again with `ssh ops@web1` to confirm.
