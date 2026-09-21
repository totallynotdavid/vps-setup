# Architecture

This is the layout of the source, for people changing it. None of it is an
interface. [How it works](./docs/how-it-works.md) says what the script does on
the server, and why in that order.

## Code map

```text
build            concatenates the fragments into dist/install.sh and writes
                 dist/install.sh.sha256
lib/             helpers and the dispatcher: apt, dispatch, log, os, quiet, root, sshd
steps/install/   the install phase, one file per step: 00-config, 10-user,
                 20-tailscale, 30-firewall, 40-updates, 90-next-steps
steps/close-ssh/ the close-ssh phase: 10-session, 20-firewall, 30-openssh, 40-root
bin/             provision, resolve-key and release, which run on your machine
tests/           unit tests that run anywhere, and tests/e2e for real servers
tests/e2e/aws/   the Terraform module and IAM policy for the EC2 harness
mise.toml        the tasks: build, check, release and the e2e:aws family
.github/         check.yml runs `mise run check`; release.yml publishes a tag
```

## How `dist/install.sh` is assembled

`build` writes the two lines that start the script (`#!/usr/bin/env bash` and
`set -euo pipefail`), then appends `lib/*.sh`, `steps/install/*.sh` and
`steps/close-ssh/*.sh` in that order with a comment naming each file, then a last
line, `main "$@"`. It exports `LC_ALL=C` so the glob order does not depend on the
locale. It then writes the checksum next to the script.

Nothing generated is committed. `dist/` is gitignored, and CI builds the
published script from a tag. Two builds of one tree are byte-identical.

Fragments contain only function definitions. Only `main "$@"` runs anything, and
it is the last line, so a truncated download runs nothing. `tests/guards.sh`
checks this by cutting the last line off.

## The dispatcher

`main` in `lib/dispatch.sh` takes one argument. `run_phase` checks the OS, then
root, then runs every function whose name starts with `install_` or
`close_ssh_`, sorted by name. The `NN` in a step's file and function name is what
orders them.

This has three consequences:

- One phase's steps share a namespace with every other fragment, because it is
  one file. Helpers therefore carry the step's topic as a prefix (`config_`,
  `user_`, `tailscale_`, `session_`) and never start with `install_` or
  `close_ssh_`, or the dispatcher would run them as steps.
- ShellCheck cannot see that steps are called by name, so `.shellcheckrc`
  disables SC2329.
- The OS check comes before the root check, so a wrong system is refused for
  the right reason whoever runs it.

## Tests

`tests/guards.sh`, `tests/config.sh`, `tests/quiet.sh` and `tests/resolve-key.sh`
run anywhere and need no root. `guards.sh` runs the generated script. `config.sh`
and `quiet.sh` source the fragments. `resolve-key.sh` puts a fake `curl` first on
`PATH`. `tests/e2e/` needs a real server, and [Testing](./docs/testing.md)
describes it.

## Boundaries that are deliberate

- The server script never reads a secret. It gets a file path and passes it on.
- `bin/` is for your machine and `steps/` is for the server. `install.sh`
  never calls anything in `bin/`.
- `bin/provision` reuses `tests/e2e/verify.sh` and `tests/e2e/known-hosts.sh`,
  so the driver and the harness check the server the same way. That makes
  `tests/e2e` more than test code: do not move or rename those two files
  without changing `bin/provision`.
- `dist/` is never committed.

[Design boundaries](./docs/design-boundaries.md) lists what the tool will not do
and why.
