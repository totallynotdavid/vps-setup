# Move a Postgres database

Move an application's Postgres database to a new server with its roles and
grants. This ran on 2026-09-21.

`pg_dump` dumps one database. The roles of the cluster and the grants on its
tables are not part of it, and restoring with `--no-privileges` drops the
grants. A client that logged in as its own role got `role "..." does not exist`.

1. On the old server, dump the database as an archive, and dump the roles:

   ```sh
   pg_dump -Fc <database> > dump
   pg_dumpall --globals-only > globals.sql
   ```

2. Copy `dump` and `globals.sql` to the new server. See
   [Copy data between servers](./copy-data.md).

3. On the new server, apply the roles. An "already exists" for the superuser is
   expected. `-d postgres` is needed because `psql` otherwise connects to a
   database named after the user, which the new cluster may not have:

   ```sh
   psql -d postgres -f globals.sql
   ```

4. Create the database and restore the data without grants:

   ```sh
   createdb <database>
   pg_restore --no-owner --no-privileges -d <database> dump
   ```

5. Restore only the ACL entries of the dump:

   ```sh
   pg_restore -l dump | grep -E ' (DEFAULT )?ACL ' > acl.list
   pg_restore -L acl.list --no-owner -d <database> dump
   ```

The image reads `POSTGRES_PASSWORD` only when it initializes a cluster. The
application's password differed from the compose environment, so the new cluster
refused it with `password authentication failed`. `ALTER ROLE ... PASSWORD`
fixed it.

The grants matched the old server after this: the ACL of every table and
function hashed to the same value, and `information_schema.role_table_grants`
had the same 18 rows.

Run `vacuumdb --analyze-only` after a restore, because a restore leaves no
statistics. A 731 MB dump of a 4.3 GB database restored with `pg_restore -j 4`
in 289 seconds with no errors.

To serve the database to other servers through a Tailscale Service, see
[Move a Tailscale Service sidecar](./dokploy-sidecars.md).
