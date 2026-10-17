#!/usr/bin/env bash
# The unattended-upgrades policy step 40 writes, run against the source fragment.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source-path=SCRIPTDIR/..
source tests/lib/helpers.sh
source steps/install/40-updates.sh

AUTO_REBOOT=23:59
expected_on='Unattended-Upgrade::Origins-Pattern:: "origin=Tailscale,label=Tailscale";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "23:59";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";'
assert "a time turns the reboot on, at that time, with users" [ "$(updates_policy)" == "$expected_on" ]

AUTO_REBOOT=off
expected_off='Unattended-Upgrade::Origins-Pattern:: "origin=Tailscale,label=Tailscale";
Unattended-Upgrade::Automatic-Reboot "false";'
assert "off turns the reboot off and sets no time" [ "$(updates_policy)" == "$expected_off" ]

((failures == 0))
