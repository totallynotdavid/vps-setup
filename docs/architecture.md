# Architecture

This is the layout of the source, for people changing it. None of it is an
interface. [How it works](./how-it-works.md) says what the script does on the
server, and why in that order.

## Code map

```text
build            concatenates the fragments into dist/install.sh and writes
                 dist/install.sh.sha256
lib/             helpers and the dispatcher: apt, dispatch, log, os, quiet, root, sshd
steps/install/   the install phase, one file per step: 00-config,
                 05-first-boot, 06-upgrade, 10-user, 20-tailscale, 30-firewall,
                 35-docker-guard, 40-updates, 90-next-steps
steps/close-ssh/ the close-ssh phase: 10-session, 20-firewall, 30-openssh, 40-root
bin/             provision, resolve-key, verify, check-release-notes and
                 release, which run on your machine, and the copy and move
                 tools for Dokploy servers
tests/           unit tests that run anywhere, and tests/e2e for real servers
tests/e2e/aws/   the Terraform module and IAM policy for the EC2 harness
mise.toml        the tasks: build, check, release and the e2e:aws family
.github/         check.yml runs `mise run check`; release.yml dry-runs on
                 pull requests and publishes a tag
```

## How `dist/install.sh` is assembled

`build` writes the two lines that start the script (`#!/usr/bin/env bash` and
`set -euo pipefail`), then appends `lib/*.sh`, `steps/install/*.sh` and
`steps/close-ssh/*.sh` in that order with a comment naming each file. Then it
writes two arrays, `install_steps` and `close_ssh_steps`, and a last line,
`main "$@"`. It exports `LC_ALL=C` so the glob order does not depend on the
locale. It then writes the checksum next to the script.

`dist/` is gitignored, and CI builds the published script from a tag. Two builds
of one tree are byte-identical.

Fragments contain only function definitions. Only `main "$@"` runs anything, and
it is the last line, so a truncated download runs nothing.

## The dispatcher

`main` in `lib/dispatch.sh` takes one argument. `run_phase` checks the OS, then
root, then runs the steps of the phase in the order of its array. `build` fills
each array from the file names of the phase, so a step runs only when it has a
file, and the `NN` in the file name orders it. A step's function is the file
name with the phase as a prefix and dashes as underscores: `20-tailscale.sh`
defines `install_20_tailscale`.

This has two consequences:

- One phase's steps share a namespace with every other fragment, because it is
  one file. Helpers therefore carry the step's topic as a prefix (`config_`,
  `user_`, `tailscale_`, `session_`).
- The OS check comes before the root check, so a wrong system is refused for the
  right reason whoever runs it.

The OS gate is `require_supported_os` in `lib/os.sh`. `supported_os` there is
the one list of releases, a function that prints one per line, because fragments
hold only definitions. `tests/os.sh` tests the gate with os-release fields it
supplies, so it does not depend on the host, and `tests/e2e/aws.sh releases`
reads the same list.

A new release goes into `supported_os` after the AWS scenarios pass on it. See
[Testing](./testing.md#which-release).

## Tests

Each file in `tests/` is named for the code it tests, runs anywhere and needs no
root. `mise run check` runs them all. A test either sources the fragments or
runs `dist/install.sh` or a script in `bin/`, with fake commands placed first on
`PATH`. The tests for `bin/copy-*`, `bin/move-*` and `systemd/compose@.service`
use a real Docker daemon, replace only `ssh`, and skip when Docker is not
usable. `tests/guards.sh` skips its refusal tests only for root on a supported
release, because that is the one caller that would really run `install`.

`tests/lib/helpers.sh` holds what the unit tests share: `assert`, the failure
count, and a local `ssh` stand-in. `tests/e2e/lib.sh` does the same for the
end-to-end scenarios.

`tests/e2e/` needs a real server, and [Testing](./testing.md) describes it.

## Boundaries between the parts

- The server script never reads a secret. It gets a file path and passes it on.
- `bin/` is for your machine and `steps/` is for the server. `install.sh` never
  calls anything in `bin/`.
- `bin/provision` and the end-to-end scenarios both run `bin/verify` and source
  `bin/lib/known-hosts.sh`, so the driver and the harness check the server the
  same way.
