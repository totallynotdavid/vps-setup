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

`TS_HOSTNAME` has no default, because a provider's host name would land on your
tailnet.

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
