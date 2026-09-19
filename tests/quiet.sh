#!/usr/bin/env bash
# The quiet helper, run against the source fragment. Needs no root.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source-path=SCRIPTDIR/..
source lib/quiet.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
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

# Sets status, stdout and stderr for the command.
run() {
	status=0
	stdout=$("$@" 2>"$tmp/stderr") || status=$?
	stderr=$(<"$tmp/stderr")
}

noisy_success() {
	echo "to stdout"
	echo "to stderr" >&2
}

noisy_failure() {
	echo "to stdout"
	echo "to stderr" >&2
	return 3
}

run quiet noisy_success
assert "success exits 0" [ "$status" -eq 0 ]
assert "success prints nothing on stdout" [ -z "$stdout" ]
assert "success prints nothing on stderr" [ -z "$stderr" ]

run quiet noisy_failure
assert "failure keeps the exit status" [ "$status" -eq 3 ]
assert "failure prints nothing on stdout" [ -z "$stdout" ]
assert "failure prints the command's stdout and stderr on stderr" \
	[ "$stderr" == $'to stdout\nto stderr' ]

run quiet no-such-command-vpssetup
assert "a missing command fails" [ "$status" -ne 0 ]
assert "a missing command reports why" grep -q 'no-such-command-vpssetup' <<<"$stderr"

# Under set -e a failing call must not abort the caller before it can react.
run bash -c 'set -e; source lib/quiet.sh; quiet false || echo handled'
assert "callers can handle a failure" [ "$stdout" == handled ]

((failures == 0))
