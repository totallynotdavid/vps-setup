# How it works

The goal is a server reachable only through Tailscale SSH, reached without ever
cutting you off. Every ordering rule below follows from that.

`install.sh` has two phases, and `bin/provision` drives both from your machine:

```text
install     on the server, over root SSH: prepare it, leave public SSH open
verify      from your machine: log in over the tailnet
close-ssh   on the server, inside that tailnet session: remove public SSH
verify      from your machine: public SSH is gone, the tailnet still works
```

The server has a way in at every point. Until `close-ssh` finishes, root and its
password still work over public SSH.

## install

Each step is a function named `install_<NN>_<name>`. They run in order, and the
first failure stops the run.

**00 config.** Every input is checked first, so a typo costs nothing and no
half-configured server is left. See [Inputs](./inputs.md).

**10 user.** Tailscale SSH logs you in as a local account, so the admin user
must exist, with sudo, before the node can be tested. The user has no password.
`adduser` fails when a group named like the user already exists, and Ubuntu 26.04
images ship an `admin` group, so the user joins an existing group of that name.
The sudoers entry is `NOPASSWD:ALL`, written to `/etc/sudoers.d/$ADMIN_USER`. It
is checked with `visudo -cf` on a temporary copy first, because a broken file in
that directory can disable sudo for everyone. Ubuntu 26.04 uses `sudo-rs`, and
`visudo -cf` parses this file with it.

**20 tailscale.** The apt repository is added, and `apt-get update` run once,
only when Tailscale is not installed. The node joins with `tailscale up --ssh`,
`--hostname`, `--timeout=10m`, and `--advertise-tags` and `--auth-key=file:...`
when you set them. The key is a file path, so it is never in a command line.
Every run passes the full flag set, because `tailscale up` refuses to change a
running node unless every non-default flag is repeated. That is why running
`install` again with the same inputs converges.

This step is before the firewall on purpose. If joining fails or times out, the
run stops with the firewall untouched and root and its password still working.
Only a node that has joined gets locked down.

**30 firewall.** ufw denies incoming, allows outgoing, allows everything on
`tailscale0`, and rate-limits the sshd port while sshd is installed. The port
comes from `sshd -T`, not from an assumption of 22. With sshd absent there is no
SSH rule, which is why running `install` again after `close-ssh` changes
nothing. `ufw --force enable` comes last, so the root session that is running
the script is never dropped by a default-deny with no allow behind it.

**40 updates.** It installs `unattended-upgrades`, writes
`/etc/apt/apt.conf.d/20auto-upgrades` to turn on the package-list update and the
upgrade, and enables the service. It is last because it is hygiene, not part of
the way in. A failure here stops `install` after everything the way in needs is
already in place.

**90 next steps.** It prints the `ssh` command to try and says that public SSH
stays open.

Two helpers shape the output. `apt_get` waits up to two minutes for the dpkg lock,
which `unattended-upgrades` can hold on a fresh server, runs without prompts, and
lets `needrestart` restart services on its own. `quiet` runs a command and
prints nothing on success, and everything the command wrote on failure. Only
`tailscale up` streams, because it prints the login or approval prompt and then
waits.

## close-ssh

**10 session.** Closing public SSH cannot be undone, so this step refuses to run
unless it is inside a Tailscale SSH session. It walks up the process parents. A
`tailscaled` ancestor means a Tailscale SSH session. An `sshd` ancestor, or
reaching PID 1 first, means it is not one, and the step exits. A `100.x` source
address proves nothing, because OpenSSH over the tailnet has one too. tmux and
screen re-parent the shell and break the chain, so they are refused, not guessed
at. The end-to-end harness checks the refusal over a root OpenSSH session.

**20 firewall.** It deletes the ufw rule for the sshd port. The port comes from
`sshd -T`, which needs sshd installed, so this step comes before the package is
removed. Deleting a rule that is absent does not fail, which makes a repeat run
harmless.

**30 openssh.** It runs `apt-get remove` on `openssh-server` and
`openssh-sftp-server`. It removes and never purges. Tailscale SSH serves the host
keys in `/etc/ssh/ssh_host_*`. Purging deletes them, the host key changes, and
every client prints "REMOTE HOST IDENTIFICATION HAS CHANGED". Removing keeps
them, and the fingerprint clients see stays the same.

**40 root.** It locks the root password with `passwd -l root`. It is last
because, with sshd gone, there is nothing left to lock you out of, and if an
earlier step fails root and its password still work.

## What remains

After `close-ssh`, the server has:

- `ssh.socket` and `ssh.service` inactive, no `/usr/sbin/sshd`, and nothing
  listening on port 22;
- root locked, and the admin user reachable only through Tailscale SSH;
- ufw active, denying incoming traffic except on `tailscale0`;
- the same SSH host key as before.

`tests/e2e/verify.sh closed` checks each of these. systemd's ssh generator can
leave `sshd-unix-local.socket` listening on a Unix socket. It is not reachable
from the network.

## Recovery

Until `close-ssh` runs, root and its password work over public SSH. After it,
there is no public way in. If Tailscale SSH stops working, reinstall the server
from the provider's panel. The design assumes a server can be rebuilt, so it keeps
no standing root password.

## bin/provision

**Verify, then close.** `bin/provision` runs `close-ssh` only after
`tests/e2e/verify.sh installed` has logged in over the tailnet from your machine,
so a Tailscale problem shows up while public SSH still exists. It runs
`close-ssh` through that same tailnet session, which is the one place the
session check accepts.

**The key is deleted.** An auth key is one-use, so a leftover file is a secret
with no purpose. `bin/provision` deletes it from the server as soon as `install`
is done, and on any exit. See [Auth key](./auth-key.md).

**Root's host key is private to the run.** A reinstalled server keeps its address
and gets a new host key, so the root host key goes in a temporary file that lasts
one run. `~/.ssh/known_hosts` is untouched.

**A cold path can be slow.** The first tailnet connection after the firewall
reload can time out. `bin/provision` waits for the login to work, up to 90
seconds, and the checks retry it up to four times.
