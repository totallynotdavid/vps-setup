#!/usr/bin/env bash
# systemd/compose@.service starts a sidecar that Docker could not start at boot.
# The test makes the boot failure by hand on a real Docker daemon, then runs the
# unit's own ExecStart command.
set -euo pipefail

cd "$(dirname "$0")/.."
unit=systemd/compose@.service

if ! docker compose version &>/dev/null || ! docker info &>/dev/null; then
	echo "SKIP compose unit tests: docker and its compose plugin are not usable"
	exit 0
fi

tmp=$(mktemp -d)
project=vps-setup-test-$$
export COMPOSE_PROJECT_NAME=$project
cleanup() {
	docker compose --project-directory "$tmp" down --timeout 1 &>/dev/null || true
	rm -rf "$tmp"
}
trap cleanup EXIT
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

cat >"$tmp/compose.yaml" <<'EOF_COMPOSE'
services:
  main:
    image: alpine
    command: sleep 3600
    restart: unless-stopped
  sidecar:
    image: alpine
    command: sleep 3600
    network_mode: service:main
    depends_on: [main]
    restart: unless-stopped
EOF_COMPOSE

running() {
	[[ $(docker inspect --format '{{.State.Running}}' "$project-$1-1") == true ]]
}

netns() {
	docker exec "$project-$1-1" readlink /proc/1/ns/net
}

# ExecStart= in the unit, run in the stack's directory, as systemd would run it.
start_stack() {
	local command
	command=$(sed -n 's/^ExecStart=//p' "$unit")
	(cd "$tmp" && ${command/\/usr\/bin\/docker/docker})
}

docker compose --project-directory "$tmp" up -d --wait >/dev/null 2>&1
assert "the stack starts" running sidecar
assert "the sidecar shares the main container's network namespace" \
	[ "$(netns main)" = "$(netns sidecar)" ]

docker stop --time 1 "$project-sidecar-1" "$project-main-1" >/dev/null
starts_alone=0
docker start "$project-sidecar-1" &>/dev/null && starts_alone=1
assert "Docker alone cannot start the sidecar while main is down" [ "$starts_alone" -eq 0 ]

start_stack >/dev/null 2>&1
assert "the unit's command starts main" running main
assert "the unit's command starts the sidecar" running sidecar
assert "the sidecar shares the new main container's network namespace" \
	[ "$(netns main)" = "$(netns sidecar)" ]

start_stack >/dev/null 2>&1
assert "running the unit's command again leaves the stack up" running sidecar

if command -v systemd-analyze >/dev/null; then
	assert "systemd accepts the unit" systemd-analyze verify "$unit"
fi

((failures == 0))
