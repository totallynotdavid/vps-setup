#!/usr/bin/env bash
# bin/copy-volume on real Docker volumes. Only ssh is replaced: a stand-in on PATH
# runs the remote command in a local shell, as ssh would on the other server, so
# both "servers" share this machine's Docker and differ in volume names.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! docker info &>/dev/null; then
	echo "SKIP copy-volume tests: docker is not usable"
	exit 0
fi

tmp=$(mktemp -d)
suffix=$$
source_volume=copy-vol-source-$suffix target_volume=copy-vol-target-$suffix
big_volume=copy-vol-big-$suffix big_target=copy-vol-big-target-$suffix
holder=copy-vol-holder-$suffix
failures=0
cleanup() {
	docker rm -f "$holder" &>/dev/null || true
	docker ps -aq --filter name=copy-volume- | xargs -r docker rm -f &>/dev/null || true
	docker volume rm -f "$source_volume" "$target_volume" "$big_volume" "$big_target" &>/dev/null || true
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
	bash -s -- "$@" <bin/copy-volume
}

in_volume() {
	local volume=$1
	shift
	docker run --rm -v "$volume:/v" alpine:3 sh -c "$*"
}

# These fail when docker fails, so an error cannot pass for "nothing found".
none_listed() {
	local listed
	listed=$("$@") || return 1
	[[ -z $listed ]]
}
some_listed() {
	local listed
	listed=$("$@") || return 1
	[[ -n $listed ]]
}
helpers() {
	docker ps -aq --filter name=copy-volume-
}
senders() {
	docker ps -q --filter name=copy-volume-send-
}

in_volume "$source_volume" '
	mkdir -p /v/sub/deep
	echo hello >/v/a.txt
	echo secret >/v/sub/secret
	chmod 600 /v/sub/secret
	chown 1234:5678 /v/sub/deep
	ln -s a.txt /v/link
	mkfifo /v/fifo
	: >/v/empty
'

out=$tmp/out
status=0
copy "$source_volume" "localhost:$target_volume" >"$out" 2>&1 || status=$?
assert "a volume is copied (exit $status)" [ "$status" -eq 0 ]
((status == 0)) || cat "$out"
assert "the content came across" \
	[ "$(in_volume "$target_volume" 'cat /v/a.txt /v/sub/secret' | tr '\n' ' ')" = "hello secret " ]
assert "the mode came across" [ "$(in_volume "$target_volume" 'stat -c %a /v/sub/secret')" = 600 ]
assert "the numeric owner came across" [ "$(in_volume "$target_volume" 'stat -c %u:%g /v/sub/deep')" = 1234:5678 ]
assert "the symlink came across" [ "$(in_volume "$target_volume" 'readlink /v/link')" = a.txt ]
assert "the copy says it verified" grep -q 'copied and verified' "$out"
assert "no helper container is left" none_listed helpers

status=0
copy "$source_volume" "localhost:$target_volume" >"$out" 2>&1 || status=$?
assert "a target that holds files is refused (exit $status)" [ "$status" -ne 0 ]
assert "the refusal says it is not empty" grep -q 'not empty' "$out"

docker run -d --name "$holder" -v "$source_volume:/v" alpine:3 sleep 600 >/dev/null
status=0
copy "$source_volume" "localhost:$target_volume-other" >"$out" 2>&1 || status=$?
assert "a source in use is refused (exit $status)" [ "$status" -ne 0 ]
assert "the refusal names the container" grep -q "$holder" "$out"
docker rm -f "$holder" >/dev/null

status=0
copy "$source_volume" 'localhost:../etc' >"$out" 2>&1 || status=$?
assert "a target path with .. is refused (exit $status)" [ "$status" -ne 0 ]
status=0
copy "no-such-volume-$suffix" "localhost:$target_volume-other" >"$out" 2>&1 || status=$?
assert "a missing source is refused (exit $status)" [ "$status" -ne 0 ]
assert "a refused copy creates no target volume" \
	none_listed docker volume ls -q --filter "name=$target_volume-other"

status=0
copy --quick "$source_volume" "localhost:$target_volume-quick" >"$out" 2>&1 || status=$?
assert "--quick copies too (exit $status)" [ "$status" -eq 0 ]
docker volume rm -f "$target_volume-quick" >/dev/null

# A copy that is killed must not leave a container writing its stream into a log.
in_volume "$big_volume" 'dd if=/dev/zero of=/v/big bs=1M count=1500 2>/dev/null'
(copy "$big_volume" "localhost:$big_target" >"$out" 2>&1) &
copy_pid=$!
deadline=$((SECONDS + 60))
until some_listed senders; do
	((SECONDS < deadline)) || break
	sleep 0.2
done
assert "the sending container runs while copying" some_listed senders
pkill -TERM -f "bash -s -- $big_volume" || true
wait "$copy_pid" || true
deadline=$((SECONDS + 30))
until none_listed helpers; do
	((SECONDS < deadline)) || break
	sleep 0.5
done
assert "no helper container is left after the copy is killed" none_listed helpers

((failures == 0))
