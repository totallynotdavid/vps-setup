# Tailnet policy

`bin/provision` logs in over Tailscale SSH, so your
[tailnet policy file](https://tailscale.com/kb/1337/policy-syntax) has to allow
it. Edit the file under Access controls in the admin console.

## Example

`web1` carries `tag:server`. You run `bin/provision` from a machine that is
either a member of `group:ops` or tagged `tag:ops`.

```jsonc
"tagOwners": {
  "tag:server": ["group:ops"],
  "tag:ops":    ["group:ops"],
},
"grants": [
  {"src": ["group:ops", "tag:ops"], "dst": ["tag:server"], "ip": ["22"]},
],
"ssh": [
  {
    "action": "accept",
    "src":    ["group:ops", "tag:ops"],
    "dst":    ["tag:server"],
    "users":  ["autogroup:nonroot"],
  },
],
```

## What each rule does

- **`tagOwners`** defines each tag and who may assign it. Every tag you pass in
  `TS_TAGS`, and the tag on your own machine if it has one, must be defined
  here.
- **`grants`** opens the network path from your machine to the server on port
  22, which is the port `ssh` connects to. A bare port in `ip` covers TCP, UDP
  and ICMP. `tcp:22` narrows it to TCP
  ([Tailscale: grants syntax](https://tailscale.com/docs/reference/syntax/grants)).
- **`ssh`** authorizes the session. `autogroup:nonroot` lets you log in as any
  user except `root`, which includes `ADMIN_USER`.

You need both `grants` and `ssh`. The grant opens the network path and the ssh
rule authorizes the session
([Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh)).

Use `accept`, not `check`. `check` asks you to authenticate again in a browser,
and `bin/provision` cannot do that. Tailscale does not allow `check` in a rule
whose source is a tagged device at all.

Legacy `acls` still work and can coexist with grants. There the port goes in
`dst`, as `tag:server:22`
([Tailscale: ACLs](https://tailscale.com/kb/1018/acls)).

## A tagged operator machine

A machine that joined the tailnet with a tag has no user identity. It is not a
member of `group:ops`, so a rule whose `src` lists only `group:ops` does not
match it. List the machine's tag in `src` of both the grant and the ssh rule, as
the example does with `tag:ops`.

## When it does not match

`bin/provision` waits 90 seconds for `ADMIN_USER@name` to answer over the
tailnet. If the policy does not match your machine, `ssh` fails until the wait
ends. `bin/provision` then stops with public SSH still open and prints ssh's last
error line. Check that both rules list your machine's user or tag in `src`, and
the server's tag in `dst`.

## The test harness

The [end-to-end harness](./testing.md) tags its servers `tag:vps-test`. Use that
tag in place of `tag:server` for them.
