# How it works

The goal is a server reachable only through Tailscale SSH, reached without ever
cutting you off. Every ordering rule below follows from that.

`install.sh` has two phases, and `bin/provision` drives both from your machine:

```text
install     on the server, over root SSH: prepare it, leave public SSH open
reboot      only if the upgrade asks for it: wait for root SSH to answer again
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

**05 first boot.** A server that has just booted can still be running the
provider's first-boot setup, whose package upgrade holds the apt locks for a
few minutes. The step runs `cloud-init status --wait`, which returns when that
setup is done, and gives up after ten minutes so a stuck provider cannot hang
`install`. It ignores the exit status. The Contabo image ends every first boot
with an error, because its own bootcmd fails, so the status says nothing about
our install. Without cloud-init it does nothing.

**06 upgrade.** An image ships with updates pending, some of them security
fixes. The step runs `apt-get update` and `apt-get full-upgrade`, so the server
is current before Tailscale joins and the firewall goes up. A failure stops
`install`. Kernel and libc updates create `/var/run/reboot-required`, which step
90 and `bin/provision` act on. A run cut off during the upgrade leaves dpkg
unfinished. When `dpkg --audit` reports that, the step runs
`dpkg --configure -a` first, so the next run repairs it. It asks `dpkg --audit`
because that takes no lock, and `dpkg --configure -a` does not wait for one.

Only the first run upgrades. When Tailscale is already installed, the step logs
one line and does nothing, because upgrading can restart `tailscaled`, which
ends the Tailscale SSH session that runs the script. `unattended-upgrades`
keeps the server current from then on.

**10 user.** Tailscale SSH logs you in as a local account, so the admin user
must exist, with sudo, before the node can be tested. The user has no password.
`adduser` fails when a group named like the user already exists, and the 26.04
image ships an `admin` group, so the user joins an existing group of that name.
The sudoers entry is `NOPASSWD:ALL`, written to `/etc/sudoers.d/$ADMIN_USER`. It
is checked with `visudo -cf` on a temporary copy first, because a broken file in
that directory can disable sudo for everyone. On 26.04, `sudo` is `sudo-rs`, and
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
comes from `sshd -T`, not from an assumption of 22. `sshd -T` refuses to run
without `/run/sshd`, and a stopped `ssh.service` leaves none behind, so the
script creates it first. With sshd absent there is no SSH rule, which is why
running `install` again after `close-ssh` changes nothing. `ufw --force enable`
comes last, so the root session that is running the script is never dropped by
a default-deny with no allow behind it.

**35 docker guard.** Docker publishes container ports with iptables rules that
run before ufw's input rules, so ufw's deny does not cover containers. The step
appends a block between `# BEGIN vps-setup docker guard` and
`# END vps-setup docker guard` to `/etc/ufw/after.rules` and
`/etc/ufw/after6.rules`. It fills `DOCKER-USER`, the chain Docker runs first:
new connections into a container are dropped, unless they arrive on loopback,
the tailnet or a container bridge, or a `ufw route allow` rule accepted them.
[Docker on this server](./docker.md) has the details and how to open a port.

The block lives in `after.rules` because ufw loads that file on every boot and
`ufw reload`, so the guard is there before Docker is installed, and Docker never
flushes `DOCKER-USER`, so a restart keeps it. ufw restores `after.rules` before
it creates its user chains, so each block declares the chain it jumps to first:
`ufw-user-forward` in the IPv4 file and `ufw6-user-forward` in the IPv6 one.
Those lines are all that differ between the two blocks.

A block already in a file is replaced, so a second run leaves both files
unchanged, and ufw reloads only when one changed. A file with a begin marker and
no end marker stops the run, because deleting from it to the end would drop
rules that are not ours.

ufw stays `active` on its old rules when it cannot restore a file, so after the
reload the step reads `DOCKER-USER` with `iptables` and `ip6tables`. If either
lacks the drop rule, it stops and says ufw kept its old rules. Root SSH is still
open then.

**40 updates.** It installs `unattended-upgrades`, writes
`/etc/apt/apt.conf.d/20auto-upgrades` to turn on the package-list update and the
upgrade, writes `/etc/apt/apt.conf.d/52vps-setup`, and enables the service. It
is last because it is hygiene, not part of the way in. A failure here stops
`install` after everything the way in needs is already in place.

`52vps-setup` sorts after `50unattended-upgrades`, so its lists add to the stock
ones. It does two things:

- The stock origins are Ubuntu and ESM, so the service never updates Tailscale,
  and Tailscale's own updater is unreliable on Ubuntu
  ([tailscale#17753](https://github.com/tailscale/tailscale/issues/17753),
  [#10400](https://github.com/tailscale/tailscale/issues/10400)). The file adds
  `origin=Tailscale,label=Tailscale` to `Unattended-Upgrade::Origins-Pattern`,
  the Origin and Label in the Tailscale repository's Release file. No other
  origin is added.
- It sets the reboot policy from `AUTO_REBOOT`. By default the server reboots at
  04:00, with users logged in, when an update needs it. The kernel is the
  isolation boundary for containers, and nobody logs in to notice
  `/var/run/reboot-required`. `off` turns the reboot off. See
  [Inputs](./inputs.md).

The file is the same on every run, so a second `install` changes nothing.

**90 next steps.** It prints the `ssh` command to try and says that public SSH
stays open. When `/var/run/reboot-required` exists, it also says to run `reboot`
before `close-ssh`.

Two helpers shape the output. `apt_get` waits up to ten minutes for the dpkg
lock, which `unattended-upgrades` can hold, runs without prompts, keeps the
existing file when a package asks about a changed config file, reads no stdin,
and lets `needrestart` restart services on its own. The script arrives on the
remote shell's stdin, so nothing apt starts may read it. `quiet` runs a command
and prints nothing on success, and everything the command wrote on failure. Only
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

**30 openssh.** It first runs `systemctl disable --now` on `ssh.socket` and then
on `ssh.service`, for each of them that exists. On 24.04, removing
`openssh-server` did not stop its units: after `close-ssh`, both were still
active and something still listened on port 22, although the package was gone
and the ufw rule deleted. The socket goes first so that it cannot start the
service again. Then it runs `apt-get remove` on `openssh-server` and
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
- `DOCKER-USER` dropping new connections into containers, IPv4 and IPv6, that no
  `ufw route allow` rule accepted;
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

**Reboot before close.** After `install`, `bin/provision` checks the server for
`/var/run/reboot-required`. If it exists, `bin/provision` notes
`/proc/sys/kernel/random/boot_id`, runs `systemctl reboot`, and waits up to five
minutes for root SSH to answer with a different boot id. The tailnet wait and
verify come next. This proves that the new kernel boots and that the server
returns on the tailnet while root SSH still works, before anything is closed. If
root SSH does not return, the run stops with public SSH open. The reboot ends
the reused root connection, so the wait opens new ones.

**The key is deleted.** An auth key is one-use, so a leftover file is a secret
with no purpose. `bin/provision` deletes it from the server as soon as `install`
is done, and on any exit. See [Auth key](./auth-key.md).

**A dead connection fails fast.** The root connection sends a keepalive every 15
seconds and gives up after four unanswered ones, so a dead network path stops
the run in about a minute, with public SSH still open, instead of hanging until
TCP gives up.

**Root's host key is private to the run.** A reinstalled server keeps its address
and gets a new host key, so the root host key goes in a temporary file that lasts
one run. `~/.ssh/known_hosts` is untouched.

**A cold path can be slow.** The first tailnet connection after the firewall
reload can time out. `bin/provision` waits for the login to work, up to 90
seconds, and the checks retry it up to four times.
