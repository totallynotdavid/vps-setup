#!/usr/bin/env bash
# bin/move-dokploy up to the point where the dashboard should stop, against a real
# Postgres container. Only ssh is replaced: a stand-in on PATH runs the remote command
# in a local shell started in a home directory, and answers the Swarm commands, which
# need a Swarm. The stand-in's `docker ps` for the dashboard fails, as a broken
# connection would.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! docker info &>/dev/null; then
	echo "SKIP move-dokploy tests: docker is not usable"
	exit 0
fi

tmp=$(mktemp -d)
suffix=$$
postgres=dokploy-postgres.1.test$suffix
failures=0
cleanup() {
	docker rm -f "$postgres" &>/dev/null || true
	rm -rf "$tmp"
}
trap cleanup EXIT

mkdir "$tmp/bin" "$tmp/home"
cat >"$tmp/bin/ssh" <<FAKE_SSH
#!/usr/bin/env bash
while [[ \$1 == -o ]]; do shift 2; done
shift
cmd="\$*"
case \$cmd in
*"ps --filter"*"dokploy-postgres"*) echo $postgres ;;
*"ps --filter"*) echo dokploy.1.test$suffix ;;
*"inspect --format"*) echo dokploy-image ;;
*"scale dokploy=0"*) ;;
*"ps -q --filter"*) echo "ssh: connection lost" >&2; exit 255 ;;
*) cd "$tmp/home" && HOME="$tmp/home" exec bash -c "\$cmd" ;;
esac
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

sql() {
	docker exec -i "$postgres" psql -U dokploy -d dokploy -v ON_ERROR_STOP=1 -X -q -At "$@"
}

docker run -d --name "$postgres" -e POSTGRES_USER=dokploy -e POSTGRES_DB=dokploy \
	-e POSTGRES_PASSWORD=pw postgres:17-alpine >/dev/null
deadline=$((SECONDS + 60))
# Wait for two successful queries because the image restarts after initialization.
until [[ $(sql -c 'select 1' 2>/dev/null) == 1 ]] && sleep 2 && [[ $(sql -c 'select 1' 2>/dev/null) == 1 ]]; do
	((SECONDS < deadline)) || {
		echo "error: $postgres did not start" >&2
		exit 1
	}
	sleep 1
done
sql -c 'create table settings (n int); insert into settings select generate_series(1, 3)'

out=$tmp/out
status=0
bash bin/move-dokploy old new >"$out" 2>&1 || status=$?
assert "a failed listing of the dashboard's containers stops the move (exit $status)" [ "$status" -eq 1 ]
assert "the failure says the listing failed, not that the dashboard is stopped" \
	grep -q "could not list the dashboard's containers on new" "$out"
assert "the way-back dump is in the home directory of the new server" \
	[ -s "$(echo "$tmp"/home/dokploy-before-move-*.dump)" ]

# The recovery hint has to work from any directory on this machine, because the dump
# is on the new server and not here.
sql -c 'delete from settings'
hint=$(grep -m1 pg_restore "$out" | sed 's/^ *//')
assert "the output prints a restore command" [ -n "$hint" ]
restore_status=0
(cd / && bash -c "$hint") || restore_status=$?
assert "the printed restore command succeeds (exit $restore_status)" [ "$restore_status" -eq 0 ]
assert "the restore brings the rows back" [ "$(sql -c 'select count(*) from settings')" = 3 ]
assert "the output prints the command that starts the dashboard again" \
	grep -q 'service scale dokploy=1' "$out"

((failures == 0))
