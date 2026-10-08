#!/usr/bin/env bash
# What `tailscale up` is asked to do, with and without an auth key, against a
# fake tailscale that records its arguments.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source-path=SCRIPTDIR/..
source lib/log.sh
source steps/install/20-tailscale.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

mkdir "$tmp/bin"
cat >"$tmp/bin/tailscale" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_CALLS"
FAKE
chmod +x "$tmp/bin/tailscale"
export FAKE_CALLS=$tmp/calls
PATH=$tmp/bin:$PATH

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

join_with() {
	: >"$FAKE_CALLS"
	TS_HOSTNAME=web1 TS_TAGS=$1 TS_AUTHKEY_FILE=$2 tailscale_join
	calls=$(<"$FAKE_CALLS")
}

calls_are() {
	[[ $calls == "$1" ]]
}

join_with "" ""
assert "without a key or tags it asks for the login URL and waits ten minutes" \
	calls_are "up --ssh --hostname=web1 --timeout=10m"

join_with "tag:server,tag:web" ""
assert "tags are advertised and there is still no key" \
	calls_are "up --ssh --hostname=web1 --timeout=10m --advertise-tags=tag:server,tag:web"

join_with "tag:server" "/root/ts.key"
assert "a key file is passed by path and never read" \
	calls_are "up --ssh --hostname=web1 --timeout=10m --advertise-tags=tag:server --auth-key=file:/root/ts.key"

((failures == 0))
