# shellcheck shell=bash
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

# Install a fake ssh that runs the remote command in a local shell, as ssh would
# on the other server.
install_local_ssh() {
	cat >"$1/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
while [[ $1 == -o ]]; do shift 2; done
shift
exec bash -c "$*"
FAKE_SSH
	chmod +x "$1/ssh"
}
