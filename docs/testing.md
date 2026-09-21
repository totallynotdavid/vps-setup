# Testing

`mise run check` needs nothing beyond the tools in `mise.toml`, and it is what
CI runs. It cannot prove the phases, which only mean something on a real server.
The end-to-end harness does that, so it is not part of `check`.

## The scripts

`tests/e2e/run.sh <root@host> <name> [--key FILE]` is the end-to-end run for a
freshly reinstalled server. It calls `bin/provision`, runs `install` and
`close-ssh` again through the tailnet session, compares the server's state before
and after to show the second run changed nothing, reboots, and checks the closed
state once more.

`tests/e2e/verify.sh installed|closed <tailnet-host> <admin-user> <public-ip>`
checks a real server from your machine: `installed` has 8 checks and `closed`
has 9. `bin/provision` uses it too.

`tests/e2e/refuse-close.sh <root@host> <name> --key FILE` installs as
`bin/provision` does, then runs `close-ssh` over the root SSH session. It checks
that `close-ssh` is refused, and that sshd stays installed and root stays
unlocked.

## On AWS

`mise run e2e:aws` makes the servers on AWS EC2. It starts a fresh Ubuntu
instance that looks like a Contabo one (26.04 unless `UBUNTU_VERSION` says
otherwise), with root login by password over SSH,
runs `run.sh` against it, then does the same for `refuse-close.sh`. Each
scenario gets its own instance, because `provision` closes SSH, and every
instance is destroyed on any exit. cloud-init makes the start state, and the
security group opens SSH to your public IP only.

### Prerequisites

- A dedicated IAM user for the harness with `tests/e2e/aws/iam-policy.json`
  attached. It allows EC2 and the Canonical AMI parameter in `us-east-1` only.
  Edit the region in the policy to test elsewhere. Give the harness its
  credentials with `AWS_PROFILE`, or `AWS_ACCESS_KEY_ID` and
  `AWS_SECRET_ACCESS_KEY`.
- `TS_TEST_KEY_FILE`: a file holding an OAuth client secret for `tag:vps-test`
  (scope `auth_keys`). Each scenario mints its own ephemeral, pre-approved key
  from it, so the test nodes leave the tailnet. A reusable, ephemeral,
  pre-approved auth key tagged `tag:vps-test` also works. Your
  [tailnet policy](./tailnet-policy.md) must let this machine SSH to that tag as
  the admin user, and this machine must be on the tailnet. Set `TS_TAGS` if the
  client or key carries other tags, and `ADMIN_USER` to change the admin account.
- OpenSSH 8.4 or later on this machine, for `SSH_ASKPASS_REQUIRE`. `mise install`
  provides `terraform` and `aws`.

### Commands

| Command                  | Does |
| ------------------------ | ---- |
| `mise run e2e:aws`       | both scenarios, each on its own instance. It exits non-zero if either fails |
| `mise run e2e:aws:releases` | `e2e:aws` once for every release in `supported_os`. It prints `release 22.04: passed` or `release 22.04: FAILED` for each, runs every release even if one fails, and exits non-zero if any failed |
| `mise run e2e:aws:up`    | creates one instance and prints its public IP |
| `mise run e2e:aws:down`  | destroys it. Safe to repeat |
| `mise run e2e:aws:sweep` | terminates leftover instances and security groups tagged `purpose=vps-setup-e2e` that are older than two hours |

`tests/e2e/aws.sh up|run|refuse|down|sweep|all|releases` is the same interface
without mise. Set `AWS_REGION` to change the region. A missing input exits with status 2
and names what to set, before any AWS call.

### Which release

`UBUNTU_VERSION` picks the release, for example
`UBUNTU_VERSION=24.04 mise run e2e:aws`. It defaults to `26.04`. Terraform takes
any release number, and only the OS gate in `lib/os.sh` decides which ones
`install` accepts, so `releases` reads the list from `supported_os` and keeps no
second one.

The server image comes from Canonical's AMI parameter under
`/aws/service/canonical/ubuntu/server/`. Canonical publishes it under `ebs-gp2`
for 20.04 and 22.04 and under `ebs-gp3` for 24.04 and 26.04, never both.
`tests/e2e/aws/main.tf` picks the segment with the local `ebs_type`: `ebs-gp2`
for 20.04 and 22.04, `ebs-gp3` for any other release. The newest 20.04 image was
built in June 2025 and the newest 22.04 image in September 2026.

### What has been verified

All measured on 2026-09-20, on AWS EC2 in `us-east-1` with a `t3.micro`:

| Release | Result of `mise run e2e:aws` |
| ------- | ---------------------------- |
| 20.04   | 30 PASS, 0 FAIL |
| 22.04   | 30 PASS, 0 FAIL |
| 24.04   | 30 PASS, 0 FAIL |
| 26.04   | 30 PASS, 0 FAIL |

`run` passes 26 checks: install 8, the first close 9, and after a reboot the
closed state again 9. `refuse` passes 4. The first 24.04 run failed after
`close-ssh`, because removing OpenSSH left `ssh.socket` and `ssh.service` active.
[How it works](./how-it-works.md#close-ssh) says what step 30 does about that.

The generated root password is kept only in Terraform state under
`tests/e2e/aws/`, which is gitignored. It reaches SSH through `SSH_ASKPASS` and
never appears in argv or in any other file. If a run crashes, run
`mise run e2e:aws:down`, or `mise run e2e:aws:sweep` when the state is gone.

### Cost

Each scenario runs one t3.micro instance with a 16 GB root volume and a public
IPv4 address, for the minutes the scenario takes. A full pass of one release, both
scenarios, took about six minutes, so `mise run e2e:aws:releases` takes about
four times that, because it runs the releases one after another. A leftover
instance keeps costing until `sweep` removes it.

## What it does not cover

- Releases outside `supported_os`. The OS gate refuses them.
- The login-URL mode. The AWS harness always passes `--key`.
- The ten-minute join timeout, and a node held by device approval.
- Providers other than AWS EC2.
