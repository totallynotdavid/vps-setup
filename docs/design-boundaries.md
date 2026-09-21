# Design boundaries

vps-setup is narrow on purpose. Some of that is permanent, because a boundary
removes a way to lock yourself out or to leave a server half-configured. The
rest is scope it has not grown into yet.

## By design, not planned

- **Only Ubuntu 26.04.** `install` and `close-ssh` refuse any other release
  before they change anything. The steps were worked out on real 26.04 servers,
  where a release-specific detail decided the outcome: the `admin` group that
  the image ships, `sudo-rs`, and the order in which sshd reads its drop-ins. A
  release that has not been run on is refused, not guessed at.
- **Only Tailscale SSH as the way in.** `close-ssh` removes OpenSSH. There is no
  option to keep it, to move it to another port or to allow a second path.
- **No sshd configuration.** Root and its password over public SSH is the
  deliberate fallback until `close-ssh`, and `close-ssh` removes sshd entirely,
  so a hardening file would configure a program that is about to go. It would
  also be fragile: sshd keeps the first value it reads, and cloud-init's
  `50-cloud-init.conf` sets `PasswordAuthentication yes`, so a drop-in has to
  sort before it to take effect.
- **No fail2ban.** After the close there is no public SSH to guard. Before it,
  ufw rate-limits the SSH port.
- **No way back once it is closed.** There is no command that reopens public
  SSH. `close-ssh` locks root, and recovery is a reinstall from the provider's
  panel. A reopening path would be a standing way in that the design exists to
  remove.
- **No secrets in the server script.** `install` takes an auth key as a file
  path and passes the path on. It never reads the key, and it never puts it in
  a command line. Minting a key belongs to `bin/resolve-key`, on your machine.
- **No default node name.** `TS_HOSTNAME` is required. A provider's generated
  host name would otherwise land on your tailnet. The admin user defaults to
  `admin` and there are no default tags, so nothing specific to your tailnet is
  built in.
- **No generated file in the repository.** `dist/install.sh` is built from the
  fragments when needed, and by CI from a tag. A committed copy would be stale
  in every commit but the last.
- **No ephemeral keys by default.** A server must stay on the tailnet when it
  goes offline. See [Auth key](./auth-key.md).

## Not yet

These are gaps, not commitments to never build them.

- **Other Ubuntu releases.** 24.04 is the next release to run on and add.
- **Other providers.** The steps have been run on a Contabo server and on AWS EC2
  servers that start the same way, with root and a password over SSH. Provider
  images that change users, SSH or the firewall through cloud-init user data
  have not been tried.
- **The install as cloud-init user data.** A cloud-init file generated from the
  same steps would fit a server that is reinstalled with an auth key. It has not
  been built or run.
- **Harness coverage of the login URL, the ten-minute timeout and device
  approval.** See [Testing](./testing.md#what-it-does-not-cover).
