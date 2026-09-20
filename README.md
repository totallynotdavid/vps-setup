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

`root@203.0.113.7` is where to log in, `web1` becomes the Tailscale node name, and `ADMIN_USER` and `TS_TAGS` are optional. It builds the script, asks for the root password once, runs `install`, and checks the Tailscale path before it closes anything: if that check fails it stops with public SSH still open. Then it runs `close-ssh` through the tailnet session, checks again and prints the `ssh` command to use from now on. Without `--key`, `tailscale up` prints a login URL and waits ten minutes for you to open it. With `--key`, an auth key is copied to the server and removed again, whether or not the run succeeds. See [Auth key](#auth-key).

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

Recommended: create an OAuth client once. In the admin console open Trust credentials, add a Credential, choose OAuth, give it the scope Auth Keys with Write, and set its tags to the ones you pass in `TS_TAGS`. Save the secret (`tskey-client-...`) in a file only you can read and pass it with `--key`:

```sh
(umask 077; cat > oauth.key)   # paste the secret, then Ctrl-D
TS_TAGS=tag:server bin/provision --key ./oauth.key root@203.0.113.7 web1
```

`bin/provision` mints a key on your machine and copies only that key to the server. It is one-use, pre-approved and expires in an hour. It is not ephemeral, because an ephemeral node leaves the tailnet when it goes offline and a real server must not; set `TS_EPHEMERAL=1` for a throwaway one. `TS_TAGS` is required and must equal the client's tags or be owned by them. The long-lived secret never leaves your machine, and it never appears in a command line.

The alternative is one key per server: create a one-use, tagged, short-expiry auth key in the admin console, and mark it pre-approved if your tailnet uses device approval. `bin/provision --key FILE` takes it the same way, and copies it as it is. By hand, copy it to the server without argv or shell history:

```sh
ssh root@<server-ip> 'umask 077; cat > /root/ts.key' < key
```

Run install with `TS_AUTHKEY_FILE=/root/ts.key` and `TS_TAGS` set to the tags the key carries, then delete it: `ssh root@<server-ip> rm /root/ts.key`. If you run the script by hand or with `curl | bash`, put an auth key there. An OAuth secret works in `TS_AUTHKEY_FILE` only in the tailscale CLI's own form, with `?ephemeral=false&preauthorized=true` after it, because the CLI defaults to ephemeral and a real server must not leave the tailnet when it goes offline. `bin/provision` is better because the server then never sees the long-lived secret.

Without pre-approval on a tailnet that uses device approval, the node stays held until an admin approves it under Machines. `tailscale up` prints "To approve your machine, visit (as admin)" and waits, and `install` gives up after 10 minutes with the firewall untouched and root plus password still working. Approve the node and run `install` again: it continues where it stopped.

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

`tests/e2e/run.sh <root@host> <name> [--key FILE]` is the end-to-end run for a freshly reinstalled server. It calls `bin/provision`, runs `install` and `close-ssh` again through the tailnet session, reboots, and checks the closed state once more. `tests/e2e/verify.sh installed|closed <tailnet-host> <admin-user> <public-ip>` checks a real server. Neither is part of `check`; [Testing](#testing) runs the first on AWS.

Release with `mise run release vX.Y.Z`. It refuses unless the tree is clean, the branch is `master` and matches `origin/master`, the tag is new and `mise run check` passes. Then it creates a signed tag, so `git tag -s` needs a signing key, and pushes it. The workflow builds and attaches the two files to a GitHub release.

## Testing

`mise run check` needs nothing beyond the tools in `mise.toml`. The end-to-end run needs a real server, and `mise run e2e:aws` makes one on AWS EC2, so it is not part of `check`. It starts a fresh Ubuntu 26.04 instance that looks like a Contabo one (root login with a password over SSH), runs `tests/e2e/run.sh` against it, then does the same for `tests/e2e/refuse-close.sh`, which checks that `close-ssh` over OpenSSH is refused and leaves sshd installed and root unlocked. Each scenario gets its own instance, because `provision` closes SSH, and every instance is destroyed on any exit.

**Prerequisites**

- A dedicated IAM user for the harness with `tests/e2e/aws/iam-policy.json` attached. It allows EC2 and the Canonical AMI parameter in `us-east-1` only; edit the region in the policy to test elsewhere. Give the harness its credentials with `AWS_PROFILE`, or `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
- `TS_TEST_KEY_FILE`: a file holding an OAuth client secret for `tag:vps-test` (scope Auth Keys with Write). Each scenario mints its own ephemeral, pre-approved key from it, so the test nodes leave the tailnet. A Tailscale auth key that is reusable (one run uses it twice), ephemeral, pre-approved and tagged `tag:vps-test` still works. Your ACL must let you SSH to that tag as the admin user, and this machine must be on the tailnet. Set `TS_TAGS` if the client or key carries other tags, and `ADMIN_USER` to change the admin account.
- OpenSSH 8.4 or later on this machine, for `SSH_ASKPASS_REQUIRE`; `mise install` provides `terraform` and `aws`.

**Commands**

| Command                   | Does                                                                        |
| ------------------------- | --------------------------------------------------------------------------- |
| `mise run e2e:aws`        | both scenarios, each on its own instance; exits non-zero if either fails    |
| `mise run e2e:aws:up`     | creates one instance and prints its public IP                               |
| `mise run e2e:aws:down`   | destroys it; safe to repeat                                                 |
| `mise run e2e:aws:sweep`  | terminates leftover instances and security groups tagged `purpose=vps-setup-e2e` older than two hours |

`tests/e2e/aws.sh up|run|refuse|down|sweep|all` is the same interface without mise. Set `AWS_REGION` to change the region. A missing input exits with status 2 and names what to set, before any AWS call.

The generated root password is kept only in Terraform state under `tests/e2e/aws/`, which is gitignored. It reaches SSH through `SSH_ASKPASS` and never appears in argv or in any other file. If a run crashes, run `mise run e2e:aws:down`, or `mise run e2e:aws:sweep` when the state is gone.

**Cost.** One t3.micro with a 16 GB root volume and a public IPv4 costs roughly 2 US cents an hour at on-demand list prices, and a full run takes under an hour, so a run costs a few cents. A leftover instance costs the same until `sweep` removes it.
