# Contributing to vps-setup

## Set up

```sh
git clone https://github.com/totallynotdavid/vps-setup
cd vps-setup
mise install
```

`mise.toml` pins `shellcheck`, `shfmt`, `terraform` and the AWS CLI.

## Layout

See [architecture.md](./architecture.md) for the code map and how
`dist/install.sh` is assembled.

## Checks

```sh
mise run build   # write dist/install.sh and dist/install.sh.sha256
mise run check   # everything below; required before submitting a change
```

`mise run check` builds the script, then runs:

- `shellcheck` on `dist/install.sh`, `build`, `bin/*`, `tests/*.sh` and
  `tests/e2e/*.sh`;
- `shfmt -ln bash -d .`, which fails on any formatting difference. The code
  uses tabs;
- `terraform fmt -check`, `init` and `validate` for the module in
  `tests/e2e/aws`, so a broken module fails without AWS credentials;
- `tests/guards.sh`, `tests/config.sh`, `tests/quiet.sh` and
  `tests/resolve-key.sh`.

CI runs the same task on every push and pull request. The end-to-end run needs a
real server and is not part of it. See [docs/testing.md](./docs/testing.md).

## Tests

- `tests/guards.sh`: the dispatcher and the refusals, through the generated
  `dist/install.sh`. The refusal tests skip only for root on Ubuntu 26.04,
  because that is the one caller that would really run `install`.
- `tests/config.sh`: input validation, against the source fragments.
- `tests/quiet.sh`: the `quiet` helper.
- `tests/resolve-key.sh`: `bin/resolve-key` against a fake `curl`, offline.
- `tests/e2e/`: the scripts that run against a real server, and the AWS harness.

What a step does to a server only shows on a real one, so run
`mise run e2e:aws` before you release.

## Commits

A commit body gives the reason on a line that starts with `Why:`, as in
`git log`.

## Releasing

See [docs/releasing.md](./docs/releasing.md).
