#!/usr/bin/env bash
# Dispatcher and guard refusals, run through the generated dist/install.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
script=dist/install.sh
[[ -f $script ]] || {
	echo "error: $script is missing; run ./build first" >&2
	exit 1
}

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

user_absent() {
	! id "$1" &>/dev/null
}

has_usage() {
	grep -q '^usage: install.sh' <<<"$1"
}

run bash "$script"
assert "no arguments exit 2" [ "$status" -eq 2 ]
assert "no arguments print usage on stderr" has_usage "$stderr"
assert "no arguments print nothing on stdout" [ -z "$stdout" ]

run bash "$script" frobnicate
assert "unknown command exits 2" [ "$status" -eq 2 ]
assert "unknown command prints usage on stderr" has_usage "$stderr"

run bash "$script" install extra
assert "extra argument exits 2" [ "$status" -eq 2 ]

run bash "$script" --help
assert "--help exits 0" [ "$status" -eq 0 ]
assert "--help prints usage" has_usage "$stdout"

# Refusals never change the host. Only root on the supported OS would really run install.
# shellcheck source=/dev/null
os=$(. /etc/os-release && echo "$ID $VERSION_ID")
if [[ $os == "ubuntu 26.04" ]]; then
	refusal="must run as root"
else
	refusal="unsupported OS"
fi
if ((EUID == 0)) && [[ $os == "ubuntu 26.04" ]]; then
	echo "SKIP refusal tests: running as root on the supported OS"
else
	user=vpssetup-guard-test
	for phase in install close-ssh; do
		run env ADMIN_USER="$user" bash "$script" "$phase"
		assert "$phase exits 1 with $refusal" [ "$status" -eq 1 ]
		assert "$phase reports error: $refusal" grep -q "^error: $refusal" <<<"$stderr"
	done
	assert "install created no user" user_absent "$user"
	assert "install wrote no sudoers file" [ ! -e "/etc/sudoers.d/$user" ]
fi

head -n -1 "$script" >"$tmp/truncated.sh"
run bash "$tmp/truncated.sh"
assert "truncated script exits 0" [ "$status" -eq 0 ]
assert "truncated script prints nothing" [ -z "$stdout$stderr" ]

((failures == 0))
