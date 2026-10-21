vps-setup 0.4.0 is out.

It comes about a month after 0.3.0. It adds tools for moving a server's data and
services to a new server, and it breaks nothing: `install.sh` and
`bin/provision` take the same arguments and do the same work as in 0.3.0, so
there is no reason to hold back.

The biggest change is four scripts for moving to a new server. `bin/copy-volume`
copies a Docker volume or a directory and checks that both sides list the same
files. `bin/copy-image` copies Docker images and compares their layers. With
`--registry` it also publishes them from the new server's loopback address,
which is how Dokploy deploys an image that exists nowhere else.
`bin/move-postgres` moves one database with its roles and grants, then compares
row counts and table grants. `bin/move-dokploy` moves the Dokploy database along
with the encryption keys it needs, and leaves a dump on the new server as the
way back. Each script checks its own copy and stops when the two sides differ.
The new documents "Copy data between servers" and "Move a Dokploy server", and
the pages split out of it, walk through each move.

The second change is `systemd/compose@.service`. It starts the compose stack in
`/srv/compose/<name>` after Docker is up and waits until it is healthy. Docker
can fail to start a sidecar at boot when it joins another container's network.
This unit starts it again. Install it by copying it to `/etc/systemd/system/`
and running `systemctl enable --now compose@<name>`.

Smaller changes: `bin/verify` and the known-hosts helper moved out of `tests/`,
because `bin/provision` runs them. The generated `install.sh` now lists its
steps in order instead of discovering them at run time. The docs were rewritten
and the reboot guidance in "Docker on this server" now says first that every
container needs a restart policy. The rest is tests, including end-to-end
scenarios for the sidecar and the login URL, and comment cleanup.

Known problems: none known.

To upgrade, clone the new tag or download `install.sh` from this release and run
it again. Running it again is safe. Report problems at
https://github.com/totallynotdavid/vps-setup/issues.
