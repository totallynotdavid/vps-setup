# Auth key

Without a key, `tailscale up` prints a login URL and waits ten minutes for you
to open it. A key removes the browser step. There are two kinds: an OAuth client
that mints a key for each server, and a key you create yourself in the admin
console. Pass either to `bin/provision` with `--key FILE`.

## OAuth client

Create one client, once. In the admin console open
[Trust credentials](https://console.tailscale.com/admin/settings/trust-credentials),
select Credential, then OAuth. Give it the `auth_keys` scope and choose its
tags. The tags on the client decide which tags the keys it mints may carry
([Tailscale: OAuth clients](https://tailscale.com/kb/1215/oauth-clients)), so
set `TS_TAGS` to them. Your [tailnet policy](./tailnet-policy.md) must define
them.

Save the secret, which starts with `tskey-client-`, in a file only you can read.
Then pass the file:

```sh
(umask 077; cat > oauth.key)   # paste the secret, then Ctrl-D
TS_TAGS=tag:server bin/provision --key ./oauth.key root@203.0.113.7 web1
```

`bin/provision` calls `bin/resolve-key`, which trades the secret for a key
through the Tailscale API. That happens on your machine, before the server is
touched, so a bad secret fails early. Only the minted key reaches the server.

The minted key:

- is one-use, so it is worthless once the node has joined;
- is pre-approved, so a tailnet with device approval does not hold the node;
- expires in one hour;
- carries the tags in `TS_TAGS`;
- has the description `vps-setup <name>`;
- is not ephemeral.

Ephemeral is off because Tailscale removes an ephemeral node 30 to 60 minutes
after its last activity ([Tailscale: ephemeral nodes](https://tailscale.com/kb/1111/ephemeral-nodes)),
and a real server must stay on the tailnet when it goes offline. Set
`TS_EPHEMERAL=1` for a throwaway server.

The long-lived secret stays on your machine. It goes to `curl` as a config on
standard input, so it never appears in a command line or in `ps`, and `curl -q`
ignores your `~/.curlrc`. Errors from the API are printed with the secret
replaced by `[redacted]`.

## Auth key from the console

Create a one-use, tagged, short-expiry auth key in the admin console. Mark it
pre-approved if your tailnet uses device approval. `bin/provision --key FILE`
takes it as it is.

`bin/provision` copies the key to `/root/ts.key` on the server with mode 0600,
hands it to `install` as `TS_AUTHKEY_FILE`, and deletes it as soon as `install`
finishes. It also deletes it on any exit, failed or not. If the deletion itself
fails, it says so and names the file to remove.

## By hand

Copy the key to the server without putting it in a command line or your shell
history:

```sh
ssh root@203.0.113.7 'umask 077; cat > /root/ts.key' < key
```

Run `install` with `TS_AUTHKEY_FILE=/root/ts.key`, and `TS_TAGS` set to the tags
the key carries. `install` passes the path to `tailscale up` as
`--auth-key=file:/root/ts.key`, so the key never appears in a command line.
Delete the file afterwards: `ssh root@203.0.113.7 rm /root/ts.key`.

Do not put an OAuth secret in `TS_AUTHKEY_FILE`. It is not a plain auth key:
`tailscale up` registers a node from it as ephemeral and not pre-approved unless
you append `?ephemeral=false&preauthorized=true`
([Tailscale: OAuth clients](https://tailscale.com/kb/1215/oauth-clients)), and a
real server must not leave the tailnet when it goes offline. `bin/provision` is
the better route anyway, because the server never sees the long-lived secret.

## When the node is held or the key is wrong

- **Device approval.** On a tailnet that uses it, a node joined with a key that
  is not pre-approved stays held. `tailscale up` prints "To approve your
  machine" and waits. Approve it under Machines in the admin console.
  `install` passes `--timeout=10m` to `tailscale up`, and the steps after it,
  which include the firewall, have not run. So root and its password still work.
  This wait was seen on a real tailnet. The timeout itself has not been run.
- **A bad key.** `install` stops at `tailscale up` with `invalid key`, before the
  firewall step. Root and its password still work.
