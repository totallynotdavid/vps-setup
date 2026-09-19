# Design

The goal is a server reachable only through Tailscale SSH, reached without ever cutting the operator off. Every ordering rule below follows from that. The operator workflow is in the [README](../README.md).

## The script

`build` concatenates the fragments in glob order: `lib/*.sh`, then `steps/install/*.sh`, then `steps/close-ssh/*.sh`. Fragments hold only function definitions and the file ends with `main "$@"`, so a truncated download is a set of definitions and runs nothing. The dispatcher runs the functions named `<phase>_<NN>_<name>` in sorted order, which is why helpers must not start with `install_` or `close_ssh_`. Nothing generated is committed, and two builds of one tree are byte-identical so the published checksum can be trusted.

Each phase checks the OS first, then root. The OS gate comes first so that a wrong system is refused for the right reason, whoever is running it.

## install

**Config first.** Inputs are validated in step 00, before any change. A typo in `TS_TAGS` should cost nothing, not a half-configured server.

**User before Tailscale.** Tailscale SSH logs you in as a local account, so `ADMIN_USER` must exist and have sudo before the node can be tested. The sudoers entry is validated with `visudo -cf` on a temporary copy first: a broken file in `/etc/sudoers.d` can disable sudo for everyone.

**Tailscale before the firewall.** If joining the tailnet fails or times out, the script stops with the firewall untouched and root plus password still working. Only a node that has joined gets locked down. `tailscale up` always receives the full flag set because it refuses to change a running node unless every non-default flag is repeated, and that is what makes re-runs converge. The apt repository is added, and `apt-get update` run once, only when Tailscale is not yet installed.

**Firewall rules before enable.** Every rule goes in before `ufw --force enable`, so the live root session is never dropped by a default-deny with no allow behind it. The sshd port comes from `sshd -T`, not an assumption of 22. With sshd absent there is no SSH rule at all, which is also what makes a re-run after `close-ssh` change nothing.

**Updates last.** They are hygiene, not part of the access path, so a failure there cannot affect it.

**No sshd configuration.** Root and password over public SSH is the deliberate fallback until `close-ssh`, and `close-ssh` removes sshd entirely. `/etc/ssh/sshd_config.d/50-cloud-init.conf` sets `PasswordAuthentication yes` and wins over later files, so a drop-in would not hold anyway.

**One apt helper.** A fresh box often has unattended-upgrades holding the dpkg lock and needrestart printing prompts. The helper waits for the lock, runs non-interactively and lets needrestart act automatically.

## close-ssh

**Session check first.** Removing OpenSSH from inside an OpenSSH session ends it, and closing SSH without a working Tailscale session leaves no way in. The check walks the process parents: a `tailscaled` ancestor is a Tailscale SSH session, an `sshd` ancestor or reaching PID 1 first is not. A `100.x` source address proves nothing, because OpenSSH over the tailnet has one too. tmux and screen re-parent the shell and break the chain, so they are refused rather than guessed at.

**Firewall rule before the package.** The port is read from `sshd -T`, which needs sshd still installed. Deleting an absent rule exits 0, so a re-run is harmless.

**Remove, never purge.** Tailscale SSH serves the host keys in `/etc/ssh/ssh_host_*`. Purging deletes them, the host key changes and every client warns. Removing keeps them and the fingerprint is unchanged. Removing the package also removes `ssh.socket`, which owns port 22.

**Root lock last.** Once sshd is gone, locking root leaves nothing to lock out. If an earlier step fails, root and its password still work.

## Not covered

- Ubuntu 24.04 and other releases: the OS gate refuses them.
- Cloud-init user data that changes users, SSH or the firewall.
- Docker publishing ports around ufw, which bypasses the firewall rules.
