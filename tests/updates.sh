#!/usr/bin/env bash
# The unattended-upgrades policy step 40 writes, run against the source fragment.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source-path=SCRIPTDIR/..
source steps/install/40-updates.sh

failures=0

assert() {
	local description=$1
	shift
	if "$@"; then
		printf 'PASS %s\n' "$description"
	else
		printf 'FAIL %s\n' "$description"
		failures=$((failures + 1))
	fi
}

AUTO_REBOOT=04:00
on=$(updates_policy)
expected_on='Unattended-Upgrade::Origins-Pattern:: "origin=Tailscale,label=Tailscale";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";'
assert "a time turns the reboot on, at that time, with users" [ "$on" == "$expected_on" ]

AUTO_REBOOT=23:59
assert "the time is the one asked for" grep -qxF 'Unattended-Upgrade::Automatic-Reboot-Time "23:59";' <<<"$(updates_policy)"

AUTO_REBOOT=off
expected_off='Unattended-Upgrade::Origins-Pattern:: "origin=Tailscale,label=Tailscale";
Unattended-Upgrade::Automatic-Reboot "false";'
assert "off turns the reboot off and sets no time" [ "$(updates_policy)" == "$expected_off" ]

AUTO_REBOOT=04:00
assert "the same input gives the same file" [ "$(updates_policy)" == "$on" ]

((failures == 0))
