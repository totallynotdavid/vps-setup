# vps-setup

Turns a fresh Ubuntu 26.04 VPS that only offers root and a password into a server reachable only through [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh). One script, two phases: `install` prepares the server and leaves public SSH open as a fallback, `close-ssh` removes OpenSSH once you have proven the Tailscale path works. Why the steps run in this order is in [docs/design.md](docs/design.md).

## Requirements

- Ubuntu 26.04 on the server, with root access. Other releases are refused.
- A Tailscale account whose ACL lets you SSH to the node as the admin user.
- For `bin/provision`: a Linux machine on the same tailnet, with `bash` and OpenSSH.

## Usage

**Recommended: `bin/provision`.** Clone the repo and run it from your own machine:

```sh
git clone https://github.com/totallynotdavid/vps-setup && cd vps-setup
ADMIN_USER=ops TS_TAGS=tag:server bin/provision --key ./ts.key root@203.0.113.7 web1
```

`root@203.0.113.7` is where to log in, `web1` becomes the Tailscale node name, and `ADMIN_USER` and `TS_TAGS` are optional. It builds the script, asks for the root password once, runs `install`, and checks the Tailscale path before it closes anything: if that check fails it stops with public SSH still open. Then it runs `close-ssh` through the tailnet session, checks again and prints the `ssh` command to use from now on. Without `--key`, `tailscale up` prints a login URL and waits ten minutes for you to open it. With `--key`, the auth key is copied to the server and removed again, whether or not the run succeeds. See [Auth key](#auth-key).

**Manually.** Each step of the same flow, without the driver.

**1. Install.** On the server, as root:

```sh
curl -fsSLO https://github.com/totallynotdavid/vps-setup/releases/latest/download/install.sh
curl -fsSLO https://github.com/totallynotdavid/vps-setup/releases/latest/download/install.sh.sha256
sha256sum -c install.sh.sha256
ADMIN_USER=ops TS_HOSTNAME=web1 bash install.sh install
```

Without `TS_AUTHKEY_FILE`, `tailscale up` prints a login URL and waits ten minutes for you to open it. To skip the browser, see [Auth key](#auth-key). Running it again is safe: every step converges. A successful run prints the step names and Tailscale's own prompts; a failing command prints its full output.

`curl -fsSL https://github.com/totallynotdavid/vps-setup/releases/latest/download/install.sh | bash -s install` does the same without the checksum check.

**2. Verify.** From your own machine:

```sh
ssh ops@web1
```

**3. Close SSH.** Inside that session, download and verify the script again, then run:

```sh
sudo bash install.sh close-ssh
```

It refuses to run anywhere but a Tailscale SSH session. Run it directly there: tmux and screen hide the session from it.

## Auth key

Create a one-use, tagged, short-expiry key in the Tailscale admin console, and mark it pre-approved if your tailnet uses device approval. `bin/provision --key FILE` handles the rest. By hand, copy it to the server without argv or shell history:

```sh
ssh root@<server-ip> 'umask 077; cat > /root/ts.key' < key
```

Run install with `TS_AUTHKEY_FILE=/root/ts.key` and `TS_TAGS` set to the tags the key carries, then delete it: `ssh root@<server-ip> rm /root/ts.key`.

Without pre-approval on such a tailnet, the node stays held until an admin approves it under Machines. `tailscale up` prints "To approve your machine, visit (as admin)" and waits, and `install` gives up after 10 minutes with the firewall untouched and root plus password still working. Approve the node and run `install` again: it continues where it stopped.

## Inputs

Environment variables for `install`, all validated before anything changes.

| Variable          | Default       | Allowed                                          |
| ----------------- | ------------- | ------------------------------------------------ |
| `ADMIN_USER`      | `admin`       | `^[a-z_][a-z0-9_-]*$`                            |
| `TS_HOSTNAME`     | required      | one DNS label: `a-z`, `0-9`, `-`, 1-63 characters |
| `TS_TAGS`         | none          | comma-separated `tag:[a-z0-9-]+`                 |
| `TS_AUTHKEY_FILE` | none          | a readable regular file holding an auth key      |

## What changes on the server

`install`:

- creates `ADMIN_USER` with no password, in group `sudo`, with passwordless sudo through `/etc/sudoers.d/$ADMIN_USER`
- installs Tailscale from its apt repository and joins the tailnet with `--ssh`
- enables ufw: deny incoming, allow outgoing, allow everything on `tailscale0`, and rate-limit the sshd port while sshd is installed
- enables unattended upgrades

`close-ssh`:

- deletes the ufw rule for the sshd port
- removes `openssh-server` and `openssh-sftp-server` (removed, not purged, so the host key stays)
- locks the root password

## Recovery

Until `close-ssh` runs, root and its password still work over public SSH. After it, there is no public way in. If Tailscale SSH stops working, reinstall the server from the provider's panel.

## Development

`mise run check` builds, lints, checks formatting and runs the tests. `./build` writes `dist/install.sh` and `dist/install.sh.sha256`; nothing generated is committed.

`tests/e2e/run.sh <root@host> <name> [--key FILE]` is the end-to-end run for a freshly reinstalled server. It calls `bin/provision`, runs `install` and `close-ssh` again through the tailnet session, reboots, and checks the closed state once more. `tests/e2e/verify.sh installed|closed <tailnet-host> <admin-user> <public-ip>` checks a real server. Neither is part of `check`.

Release with `mise run release vX.Y.Z`. It refuses unless the tree is clean, the branch is `master` and matches `origin/master`, the tag is new and `mise run check` passes. Then it creates a signed tag, so `git tag -s` needs a signing key, and pushes it. The workflow builds and attaches the two files to a GitHub release.
