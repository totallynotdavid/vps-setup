#!/usr/bin/env bash
# Input validation, run against the source fragments.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source-path=SCRIPTDIR/..
source lib/log.sh
source steps/install/00-config.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
: >"$tmp/key"
failures=0

# Runs the step in a subshell with the given VAR=value pairs; prints the
# resulting inputs on success. Sets status and output.
run_config() {
	local pair
	status=0
	output=$(
		exec 2>&1
		unset ADMIN_USER TS_HOSTNAME TS_TAGS TS_AUTHKEY_FILE
		for pair in "$@"; do
			export "${pair?}"
		done
		install_00_config
		printf 'ADMIN_USER=%s TS_HOSTNAME=%s TS_TAGS=%s TS_AUTHKEY_FILE=%s\n' \
			"$ADMIN_USER" "$TS_HOSTNAME" "$TS_TAGS" "$TS_AUTHKEY_FILE"
	) || status=$?
}

report() {
	if [[ $1 == ok ]]; then
		printf 'PASS %s\n' "$2"
	else
		printf 'FAIL %s\n     got status %s: %s\n' "$2" "$status" "$output"
		failures=$((failures + 1))
	fi
}

# expect_ok <description> <expected inputs line> [VAR=value ...]
expect_ok() {
	local description=$1 expected=$2
	shift 2
	run_config "$@"
	if ((status == 0)) && [[ $output == "$expected" ]]; then
		report ok "$description"
	else
		report fail "$description"
	fi
}

# expect_error <description> <expected error prefix> [VAR=value ...]
expect_error() {
	local description=$1 expected=$2
	shift 2
	run_config "$@"
	if ((status == 1)) && [[ $output == "error: $expected"* ]]; then
		report ok "$description"
	else
		report fail "$description"
	fi
}

expect_ok "defaults with only TS_HOSTNAME set" \
	"ADMIN_USER=admin TS_HOSTNAME=web1 TS_TAGS= TS_AUTHKEY_FILE=" \
	TS_HOSTNAME=web1
expect_ok "all inputs set" \
	"ADMIN_USER=ops_1 TS_HOSTNAME=web-01 TS_TAGS=tag:a,tag:b-2 TS_AUTHKEY_FILE=$tmp/key" \
	ADMIN_USER=ops_1 TS_HOSTNAME=web-01 TS_TAGS=tag:a,tag:b-2 "TS_AUTHKEY_FILE=$tmp/key"

expect_error "ADMIN_USER with uppercase" "ADMIN_USER 'Admin' is invalid" ADMIN_USER=Admin
expect_error "ADMIN_USER starting with a digit" "ADMIN_USER '1abc' is invalid" ADMIN_USER=1abc
expect_error "ADMIN_USER with a space" "ADMIN_USER 'a b' is invalid" "ADMIN_USER=a b"

expect_error "TS_HOSTNAME unset" "TS_HOSTNAME is required, for example TS_HOSTNAME=web1"
expect_error "TS_HOSTNAME empty" "TS_HOSTNAME is required, for example TS_HOSTNAME=web1" TS_HOSTNAME=
expect_error "TS_HOSTNAME with a dot" "TS_HOSTNAME 'a.b' is invalid" TS_HOSTNAME=a.b
expect_error "TS_HOSTNAME with a leading dash" "TS_HOSTNAME '-a' is invalid" TS_HOSTNAME=-a
expect_error "TS_HOSTNAME with uppercase" "TS_HOSTNAME 'Web' is invalid" TS_HOSTNAME=Web
expect_error "TS_HOSTNAME over 63 characters" "TS_HOSTNAME '" "TS_HOSTNAME=$(printf 'a%.0s' {1..64})"

expect_error "TS_TAGS without the tag: prefix" "TS_TAGS 'web' is invalid" TS_HOSTNAME=web1 TS_TAGS=web
expect_error "TS_TAGS with an empty tag name" "TS_TAGS 'tag:' is invalid" TS_HOSTNAME=web1 TS_TAGS=tag:
expect_error "TS_TAGS with one bad entry" "TS_TAGS 'tag:a,web' is invalid" TS_HOSTNAME=web1 TS_TAGS=tag:a,web
expect_error "TS_TAGS with uppercase" "TS_TAGS 'tag:A' is invalid" TS_HOSTNAME=web1 TS_TAGS=tag:A

expect_error "TS_AUTHKEY_FILE missing" "TS_AUTHKEY_FILE '$tmp/none' is not a readable regular file" \
	TS_HOSTNAME=web1 "TS_AUTHKEY_FILE=$tmp/none"
expect_error "TS_AUTHKEY_FILE is a directory" "TS_AUTHKEY_FILE '$tmp' is not a readable regular file" \
	TS_HOSTNAME=web1 "TS_AUTHKEY_FILE=$tmp"

((failures == 0))
