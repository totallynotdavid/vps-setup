# Testing

`mise run check` needs nothing beyond the tools in `mise.toml`, and it is what
CI runs. It cannot prove the phases, which only mean something on a real server.
The end-to-end harness does that, so it is not part of `check`.

## The scripts

`tests/e2e/run.sh <root@host> <name> [--key FILE]` is the end-to-end run for a
freshly reinstalled server. It calls `bin/provision`, runs `install` and
`close-ssh` again through the tailnet session, compares the server's state before
and after to show the second run changed nothing, reboots, and checks the closed
state once more. The state includes `/etc/ufw/after.rules` and
`/etc/ufw/after6.rules`, so it checks that the docker guard is written once.

`tests/e2e/verify.sh installed|closed <tailnet-host> <admin-user> <public-ip>`
checks a real server from your machine. `bin/provision` uses it too. Both modes
check that the tailnet login works and that ufw is active and denies incoming
traffic and that `DOCKER-USER` holds the rule that drops new connections, for
`iptables` and `ip6tables`. `installed` also checks that `sudo` works, that
`unattended-upgrades` is active and allows the Tailscale origin, that the
automatic-reboot setting matches `AUTO_REBOOT`, that Tailscale reports no health
problem, that sshd is installed and that public port 22 accepts a connection.
`closed` checks that `ssh.socket` and `ssh.service` are inactive, that sshd is
absent, that nothing listens on port 22, that the root password is locked and
that public port 22 does not connect.

`tests/e2e/refuse-close.sh <root@host> <name> --key FILE` installs as
`bin/provision` does, then runs `close-ssh` over the root SSH session. It checks
that `close-ssh` is refused, and that sshd stays installed and root stays
unlocked.

`tests/e2e/docker.sh <root@host> <name> --key FILE` provisions as `run.sh` does,
then installs Docker on the server and publishes nginx three ways: `docker run
-p`, a Swarm ingress service and a Swarm `mode=host` service. A network
namespace on a veth pair stands in for a public interface. The script checks
that a client in the namespace times out on all three ports while `127.0.0.1`
answers. As a control it then empties `DOCKER-USER` and checks that the same
client reaches all three, so the timeouts are the guard's doing, and `ufw reload`
fills the chain again. It checks that a container still reaches the internet,
that `ufw route allow` opens a port and deleting the rule closes it again (the
container's port for the `docker run -p` and host-mode services, the published
port for the ingress one), and that the ports stay closed after `ufw reload`,
`systemctl restart docker` and a reboot. It checks the `docker run -p` port over
IPv6 too. It ends with `verify.sh closed`.

## On AWS

`mise run e2e:aws` makes the servers on AWS EC2. It starts a fresh Ubuntu
instance that looks like a Contabo one (26.04 unless `UBUNTU_VERSION` says
otherwise), with root login by password over SSH, runs `run.sh` against it, then
does the same for `refuse-close.sh` and `docker.sh`. Each scenario gets its own
instance, because `provision` closes SSH, and every instance is destroyed on any
exit. cloud-init makes the start state, and the security group opens SSH to your
public IP only.

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
| `mise run e2e:aws`       | every scenario, each on its own instance. It exits non-zero if one fails |
| `mise run e2e:aws:docker` | the `docker` scenario alone, on its own instance |
| `mise run e2e:aws:releases` | `e2e:aws` once for every release in `supported_os`. It prints `release 22.04: passed` or `release 22.04: FAILED` for each, runs every release even if one fails, and exits non-zero if any failed |
| `mise run e2e:aws:up`    | creates one instance and prints its public IP |
| `mise run e2e:aws:down`  | destroys it. Safe to repeat |
| `mise run e2e:aws:sweep` | terminates leftover instances and security groups tagged `purpose=vps-setup-e2e` that are older than two hours |

`tests/e2e/aws.sh up|run|refuse|docker|down|sweep|all|releases` is the same
interface without mise. `all` takes scenario names, for example
`aws.sh all docker`, and runs every scenario when it gets none. Set
`AWS_REGION` to change the region. A missing input exits with status 2 and names
what to set, before any AWS call.

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

All measured on 2026-09-21, on AWS EC2 in `us-east-1` with a `t3.micro`:

| Release | `run` | `refuse` | `docker` |
| ------- | ----- | -------- | -------- |
| 20.04   | passed | passed | passed |
| 22.04   | passed | passed | passed |
| 24.04   | passed | passed | passed |
| 26.04   | passed | passed | passed |

`run` checks the installed state, the closed state, and the closed state again
after a reboot. `refuse` checks the refusal. `docker` checks the guard. The first
24.04 run failed after `close-ssh`, because removing OpenSSH left `ssh.socket`
and `ssh.service` active. [How it works](./how-it-works.md#close-ssh) says what
step 30 does about that. On 20.04 Docker's install script fails on a package
Docker no longer ships for that release, so `docker.sh` installs the engine
packages by name.

The generated root password is kept only in Terraform state under
`tests/e2e/aws/`, which is gitignored. It reaches SSH through `SSH_ASKPASS` and
never appears in argv or in any other file. If a run crashes, run
`mise run e2e:aws:down`, or `mise run e2e:aws:sweep` when the state is gone.

### Cost

Each scenario runs one t3.micro instance with a 16 GB root volume and a public
IPv4 address, for the minutes the scenario takes: about six for `run`, three for
`refuse` and nine for `docker`. `mise run e2e:aws:releases` runs the releases one
after another, so it takes about four times as long as one. A leftover instance
keeps costing until `sweep` removes it.

## What it does not cover

- Releases outside `supported_os`. The OS gate refuses them.
- The login-URL mode. The AWS harness always passes `--key`.
- The ten-minute join timeout, and a node held by device approval.
- Providers other than AWS EC2.
- Docker's nftables backend, and IPv6 for Swarm published ports. The `docker`
  scenario checks IPv6 for the `docker run -p` port only.
