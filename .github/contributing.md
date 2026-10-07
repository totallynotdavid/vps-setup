# Contributing to vps-setup

## Set up

```sh
git clone https://github.com/totallynotdavid/vps-setup
cd vps-setup
mise install
```

`mise.toml` pins `shellcheck`, `shfmt`, `terraform` and the AWS CLI.

## The codebase

See [Architecture](../docs/architecture.md) for the code map, how
`dist/install.sh` is assembled and what each test covers.

## Checks

```sh
mise run build
mise run check
```

`mise run check` builds the script, then runs:

- `shellcheck` on `dist/install.sh`, `build`, `bin/*`, `tests/*.sh` and
  `tests/e2e/*.sh`;
- `shfmt -ln bash -d .`, which fails on any formatting difference. The code uses
  tabs;
- `terraform fmt -check`, `init` and `validate` for the module in
  `tests/e2e/aws`, so a broken module fails without AWS credentials;
- the unit tests in `tests/*.sh`.

CI runs the same task on every push and pull request. The end-to-end run needs a
real server and is not part of it. What a step does to a server only shows on a
real one, so run `mise run e2e:aws` before you release. See
[Testing](../docs/testing.md).

## Commits

A commit body gives the reason on a line that starts with `Why:`, as in
`git log`.

## Releasing

See [Releasing](../docs/releasing.md).
