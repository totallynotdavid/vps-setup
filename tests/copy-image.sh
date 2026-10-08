#!/usr/bin/env bash
# bin/copy-image with real images and a real registry. Only ssh is replaced: a
# stand-in on PATH runs the remote command in a local shell, as ssh would on the
# other server, so both "servers" share this machine's Docker.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! docker info &>/dev/null; then
	echo "SKIP copy-image tests: docker is not usable"
	exit 0
fi

tmp=$(mktemp -d)
suffix=$$
image=copy-image-test-$suffix:1
# The test picks a free port instead of assuming 5000 is unused.
port=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
registry=registry-$port
failures=0
cleanup() {
	docker rm -f "$registry" &>/dev/null || true
	docker volume rm -f "$registry" &>/dev/null || true
	docker rmi -f "$image" "127.0.0.1:$port/$image" &>/dev/null || true
	rm -rf "$tmp"
}
trap cleanup EXIT

mkdir "$tmp/bin"
cat >"$tmp/bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
while [[ $1 == -o ]]; do shift 2; done
shift
exec bash -c "$*"
FAKE_SSH
chmod +x "$tmp/bin/ssh"
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

copy() {
	bash -s -- "$@" <bin/copy-image
}

printf 'FROM alpine:3\nRUN echo %s >/marker\n' "$suffix" | docker build -q -t "$image" - >/dev/null

out=$tmp/out
status=0
copy localhost "$image" >"$out" 2>&1 || status=$?
assert "an image is copied (exit $status)" [ "$status" -eq 0 ]
((status == 0)) || cat "$out"
assert "the copy says it verified" grep -q 'copied and verified' "$out"

status=0
copy localhost "no-such-image-$suffix:1" >"$out" 2>&1 || status=$?
assert "a missing image is refused (exit $status)" [ "$status" -ne 0 ]
assert "the refusal names the image" grep -q "no-such-image-$suffix" "$out"

status=0
copy localhost 'bad image' >"$out" 2>&1 || status=$?
assert "an image name with a space is refused (exit $status)" [ "$status" -ne 0 ]

status=0
copy --registry --port "$port" localhost "$image" >"$out.stdout" 2>"$out" || status=$?
assert "an image is published (exit $status)" [ "$status" -eq 0 ]
((status == 0)) || cat "$out"
assert "the printed name is the loopback registry's" \
	[ "$(cat "$out.stdout")" = "127.0.0.1:$port/$image" ]

# The proof that Dokploy's pull would work: remove the local tag, pull it back.
docker rmi "127.0.0.1:$port/$image" >/dev/null
pull() {
	docker pull -q "$1" >/dev/null
}
assert "the image pulls from the registry" pull "127.0.0.1:$port/$image"
assert "the pulled image holds the same file" \
	[ "$(docker run --rm "127.0.0.1:$port/$image" cat /marker)" = "$suffix" ]

status=0
copy --registry --port "$port" localhost "$image" >"$out" 2>&1 || status=$?
assert "publishing again reuses the registry (exit $status)" [ "$status" -eq 0 ]

((failures == 0))
