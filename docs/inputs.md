# Inputs

## `install`

`install` reads these environment variables. It checks all of them before it
changes anything, and a bad value exits with status 1 and a message that names
the variable.

| Variable          | Default  | Rule                                                     |
| ----------------- | -------- | -------------------------------------------------------- |
| `ADMIN_USER`      | `admin`  | matches `^[a-z_][a-z0-9_-]*$`                            |
| `TS_HOSTNAME`     | required | one DNS label: `a-z`, `0-9` and `-`, 1 to 63 characters, not starting or ending with `-` |
| `TS_TAGS`         | none     | comma-separated tags, each matching `tag:[a-z0-9-]+`     |
| `TS_AUTHKEY_FILE` | none     | a readable regular file. Its content is not checked      |
| `AUTO_REBOOT`     | `04:00`  | a 24-hour `HH:MM`, from `00:00` to `23:59`, or `off`     |

`TS_HOSTNAME` has no default, because a provider's host name would land on your
tailnet.

`AUTO_REBOOT` is the time, on the server's clock, at which
`unattended-upgrades` reboots the server after an update that needs it. It does
not reboot every day. See [How it works](./how-it-works.md#install) for what it
writes.

The server's clock follows the server's timezone. vps-setup does not set a
timezone, so the server keeps the one its image ships. Check it with
`timedatectl`. A Contabo Ubuntu 26.04 image shipped `Europe/Berlin` on
2026-09-21. That zone follows daylight saving time, so a fixed `HH:MM` moves by
an hour against UTC twice a year. `sudo timedatectl set-timezone UTC` pins it.
On a UTC server, `AUTO_REBOOT=09:00` is 04:00 at UTC-5.

`install.sh` takes exactly one argument: `install` or `close-ssh`. `-h` and
`--help` print the usage and exit 0. Any other call prints the usage and exits 2.
`close-ssh` reads no variables.

Every run fails with status 1 before it changes anything unless the OS is one of
the releases that `supported_os` lists in [`lib/os.sh`](../lib/os.sh) and the
caller is root.

## `bin/provision`

```text
bin/provision [--key FILE] <root@host> <name>
```

| Argument or variable | Meaning |
| -------------------- | ------- |
| `<root@host>` | where to log in. The user must be `root` |
| `<name>` | the Tailscale node name. It is passed as `TS_HOSTNAME` |
| `--key FILE` | an auth key, or an OAuth client secret. See [Auth key](./auth-key.md). The file must exist |
| `ADMIN_USER` | passed on to `install`. Default `admin` |
| `TS_TAGS` | passed on to `install`. Required with an OAuth client secret |
| `AUTO_REBOOT` | passed on to `install` when set. Default `04:00` |
| `TS_EPHEMERAL` | `1` makes a key minted from an OAuth client secret ephemeral. Default: not ephemeral |
| `-h`, `--help` | print the usage and exit 0 |

A wrong call prints the usage and exits 2.

## `bin/resolve-key`

`bin/provision` calls it. You can run it alone to test a key file:

```text
bin/resolve-key FILE
```

It prints an auth key on stdout. The first line of `FILE` is either a plain
auth key, printed unchanged, or an OAuth client secret that starts with
`tskey-client-`, which is traded for a one-use key. For an OAuth client
secret it reads `TS_TAGS` and `TS_EPHEMERAL` as `bin/provision` does, and
`TS_HOSTNAME`, which only appears in the key's description.
