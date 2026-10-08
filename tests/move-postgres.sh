#!/usr/bin/env bash
# Runs bin/move-postgres between two real Postgres containers. Only ssh is
# replaced. A stand-in on PATH runs the remote command in a local shell, as ssh
# would on the other server, so both containers use this machine's Docker.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! docker info &>/dev/null; then
	echo "SKIP move-postgres tests: docker is not usable"
	exit 0
fi

tmp=$(mktemp -d)
suffix=$$
old=move-pg-old-$suffix new=move-pg-new-$suffix
image=postgres:17-alpine
failures=0
cleanup() {
	docker rm -f "$old" "$new" &>/dev/null || true
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

start_cluster() {
	docker run -d --name "$1" -e POSTGRES_PASSWORD=pw "$image" >/dev/null
	local deadline=$((SECONDS + 60))
	# Wait for two successful queries because the image restarts after initialization.
	until [[ $(docker exec "$1" psql -U postgres -At -c 'select 1' 2>/dev/null) == 1 ]] &&
		sleep 2 && [[ $(docker exec "$1" psql -U postgres -At -c 'select 1' 2>/dev/null) == 1 ]]; do
		((SECONDS < deadline)) || {
			echo "error: $1 did not start" >&2
			exit 1
		}
		sleep 1
	done
}

sql() {
	docker exec -i "$1" psql -U postgres -v ON_ERROR_STOP=1 -X -q -At -d "${2:-postgres}"
}

move() {
	bash -s -- "$@" <bin/move-postgres
}

# Fails when the command fails, so an error cannot pass for "nothing found".
none_listed() {
	local listed
	listed=$("$@") || return 1
	[[ -z $listed ]]
}

start_cluster "$old" &
start_cluster "$new" &
wait

sql "$old" <<'EOF_SQL'
create role shop_app login password 'app-secret';
create role shop_reader;
create database shop owner shop_app;
EOF_SQL
sql "$old" shop <<'EOF_SQL'
create table orders (id serial primary key, item text not null);
insert into orders (item) select 'item ' || g from generate_series(1, 500) g;
create table notes (body text);
insert into notes values ('one'), ('two');
alter table orders owner to shop_app;
grant select on orders to shop_reader;
grant select, insert on notes to shop_app;
alter default privileges in schema public grant select on tables to shop_reader;
EOF_SQL
sql "$new" <<'EOF_SQL'
create role shop_app login password 'different-secret';
EOF_SQL

out=$tmp/out
status=0
move "$old" shop localhost "$new" >"$out" 2>&1 || status=$?
assert "the move succeeds (exit $status)" [ "$status" -eq 0 ]
((status == 0)) || cat "$out"

assert "all rows came across" \
	[ "$(sql "$new" shop <<<"select (select count(*) from orders) || ' ' || (select count(*) from notes)")" = "500 2" ]
assert "the reader keeps its grant on orders" \
	[ "$(sql "$new" shop <<<"select has_table_privilege('shop_reader', 'orders', 'select')")" = t ]
assert "the app role keeps its grant on notes" \
	[ "$(sql "$new" shop <<<"select has_table_privilege('shop_app', 'notes', 'insert')")" = t ]
assert "the reader has no write privilege it never had" \
	[ "$(sql "$new" shop <<<"select has_table_privilege('shop_reader', 'orders', 'insert')")" = f ]

# The same hash that the old cluster holds, so the application's password still works.
role_hash() {
	sql "$1" <<<"select rolpassword from pg_authid where rolname = 'shop_app'"
}
assert "the role's password matches the old cluster's" [ "$(role_hash "$new")" = "$(role_hash "$old")" ]
assert "the database is owned by the same role" \
	[ "$(sql "$new" <<<"select pg_get_userbyid(datdba) from pg_database where datname = 'shop'")" = shop_app ]
assert "no dump is left in the new container" \
	none_listed docker exec "$new" find /tmp -maxdepth 1 -name 'move-postgres-*.dump'

status=0
move "$old" shop localhost "$new" >"$out" 2>&1 || status=$?
assert "a second move without --replace is refused (exit $status)" [ "$status" -ne 0 ]
assert "the refusal says the database exists" grep -q 'already exists' "$out"

sql "$old" shop <<'EOF_SQL'
insert into notes values ('three');
EOF_SQL
status=0
move --replace "$old" shop localhost "$new" >"$out" 2>&1 || status=$?
assert "--replace moves it again (exit $status)" [ "$status" -eq 0 ]
assert "the replaced database holds the new row" \
	[ "$(sql "$new" shop <<<'select count(*) from notes')" = 3 ]

# With --no-roles, the new cluster keeps its own roles and receives no grants.
sql "$old" <<'EOF_SQL'
create database plain;
EOF_SQL
sql "$old" plain <<'EOF_SQL'
create table t (n int);
insert into t values (1), (2), (3);
grant select on t to shop_reader;
EOF_SQL
status=0
move --no-roles "$old" plain localhost "$new" >"$out" 2>&1 || status=$?
assert "--no-roles moves a database (exit $status)" [ "$status" -eq 0 ]
assert "--no-roles keeps the rows" [ "$(sql "$new" plain <<<'select count(*) from t')" = 3 ]
assert "--no-roles restores no grants" \
	[ "$(sql "$new" plain <<<"select has_table_privilege('shop_reader', 't', 'select')")" = f ]

status=0
move "$old" nosuchdb localhost "$new" >"$out" 2>&1 || status=$?
assert "an unknown source database is refused (exit $status)" [ "$status" -ne 0 ]
assert "the refusal names the database" grep -q "nosuchdb" "$out"

# The owner's name is read from the source cluster and reaches a shell on the other side.
mark=/tmp/move-postgres-injected-$suffix
rm -f "$mark"
sql "$old" <<EOF_SQL
create role "odd owner'; touch $mark; echo '" login;
create database oddown owner "odd owner'; touch $mark; echo '";
EOF_SQL
status=0
move "$old" oddown localhost "$new" >"$out" 2>&1 || status=$?
assert "a database whose owner has quotes and spaces moves (exit $status)" [ "$status" -eq 0 ]
((status == 0)) || cat "$out"
assert "the owner is kept as named" \
	[ "$(sql "$new" <<<"select pg_get_userbyid(datdba) from pg_database where datname = 'oddown'")" = "odd owner'; touch $mark; echo '" ]
assert "the owner's name ran no command" [ ! -e "$mark" ]

# The new cluster cannot hold both memberships. It rejects the GRANT, which psql
# reports while still exiting 0.
sql "$old" <<'EOF_SQL'
create database cycle;
create role cycle_b;
create role cycle_a in role cycle_b;
EOF_SQL
sql "$new" <<'EOF_SQL'
create role cycle_a;
create role cycle_b in role cycle_a;
EOF_SQL
status=0
move "$old" cycle localhost "$new" >"$out" 2>&1 || status=$?
assert "a role the new cluster rejects stops the move (exit $status)" [ "$status" -ne 0 ]
assert "the failure names the role error" grep -q 'member of role' "$out"
assert "no database is restored after the role error" \
	none_listed sql "$new" <<<"select 1 from pg_database where datname = 'cycle'"

((failures == 0))
