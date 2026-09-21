#!/usr/bin/env bash
# The OS gate, run against the source fragments with os-release fields supplied by the test.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source-path=SCRIPTDIR/..
source lib/log.sh
source lib/os.sh

failures=0

# Sets status and output for the gate on a host with the given ID and VERSION_ID.
run_gate() {
	local id=$1 version=$2
	status=0
	output=$(
		exec 2>&1
		os_field() {
			case $1 in
			ID) printf '%s' "$id" ;;
			VERSION_ID) printf '%s' "$version" ;;
			esac
		}
		require_supported_os
	) || status=$?
}

expect_accepted() {
	run_gate "$1" "$2"
	if ((status == 0)) && [[ -z $output ]]; then
		printf 'PASS '\''%s %s'\'' is accepted\n' "$1" "$2"
	else
		printf 'FAIL '\''%s %s'\'' is accepted\n     got status %s: %s\n' "$1" "$2" "$status" "$output"
		failures=$((failures + 1))
	fi
}

expect_refused() {
	local expected="error: unsupported OS '$1 $2'; supported: ubuntu 20.04, ubuntu 22.04, ubuntu 24.04, ubuntu 26.04"
	run_gate "$1" "$2"
	if ((status == 1)) && [[ $output == "$expected" ]]; then
		printf 'PASS '\''%s %s'\'' is refused, naming all four\n' "$1" "$2"
	else
		printf 'FAIL '\''%s %s'\'' is refused, naming all four\n     got status %s: %s\n' "$1" "$2" "$status" "$output"
		failures=$((failures + 1))
	fi
}

expect_accepted ubuntu 20.04
expect_accepted ubuntu 22.04
expect_accepted ubuntu 24.04
expect_accepted ubuntu 26.04
expect_refused ubuntu 18.04
expect_refused ubuntu 25.10
expect_refused ubuntu 24.04.1
expect_refused debian 12
expect_refused debian 24.04
expect_refused "" ""

((failures == 0))
