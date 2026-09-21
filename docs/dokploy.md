# Dokploy behind a Cloudflare Tunnel

vps-setup does not install Docker, Dokploy or cloudflared. This page is a
recipe for a server that you set up with vps-setup and then run Dokploy on,
behind a Cloudflare Tunnel. A server set up another way has neither the guard
nor the results below.

Everything here was run on an AWS Ubuntu server on 2026-09-21, after a full
`install` and `close-ssh`. The install steps, the dashboard check and a named
tunnel also ran on a Contabo server with Ubuntu 26.04 on the same day. The
versions are Dokploy 0.30.7, cloudflared 2026.9.1 and the packages in Docker's
repositories on that day. Dokploy's installer is a third-party script and will
change.

## Order

Run vps-setup first. Then install Docker and Dokploy. The Docker guard of
step 35 was in place before Docker in every run. See
[Docker on this server](./docker.md) for what the guard does.

## Pick the Ubuntu release

Dokploy 0.30.7's installer installs Docker 28.5.0 through
`get.docker.com --version`. It holds `docker-ce`, `docker-ce-cli` and
`docker-ce-rootless-extras` with `apt-mark hold`. It skips its Docker step when
`docker` is already there.

Docker's apt repository for 26.04 carries only 29.3.1 to 29.8.1 (listed
2026-09-21). The repository for 24.04 carries 28.5.0. So the installer's pinned
Docker cannot install on a bare 26.04.

- **24.04.** The installer alone worked, with its own Docker 28.5.0.
- **26.04.** Install Docker first:

  ```sh
  curl -fsSL https://get.docker.com | sh
  ```

  That gave Docker 29.8.1. Dokploy's installer then found Docker and skipped its
  step.

## Install Dokploy

The installer needs at least 2 GB of RAM and 30 GB of disk. This comes from
reading its script. It was not tried with less.

Download the installer and run it as root, with the server's own address in
`ADVERTISE_ADDR`:

```sh
curl -sSL https://dokploy.com/install.sh -o install.sh
sudo ADVERTISE_ADDR=<the server's own address> sh install.sh
```

Dokploy, its Postgres and Traefik came up and survived a reboot.

The installer's last line points at `http://<the server's address>:3000`. Behind
the guard, that address does not answer from the internet. See
[Open the dashboard](#open-the-dashboard).

## What the guard leaves open

After the install, Docker publishes 80, 443 and 3000. From a
client on a non-tailnet interface, 80, 443 and 3000 all timed out, over IPv4
and IPv6.

On the server, `127.0.0.1:80` answered 404. That is Traefik, which has no router
for that host. `127.0.0.1:3000` answered 307, which is the Dokploy dashboard.
Both answered about 26 seconds after a reboot, with the ports still closed.

A container on the `dokploy-network` overlay reached `dokploy-traefik:80` (404)
and `dokploy:3000` (307).

## Open the dashboard

From another machine on the tailnet, open
`http://<the server's tailnet name>:3000`. The tailnet policy must allow port
3000. See [Tailnet policy](./tailnet-policy.md). On the Contabo server, a tailnet
device got `307` on port 3000 and `404` on port 80.

A new Dokploy redirects `/` to `/register`, and `/register` answered `200`.
Register the first account before anyone else can reach the port. This page did
not create an account, so what that account can do was not tried.

Without a grant for port 3000, forward the port through Tailscale SSH:

```sh
ssh -L 3000:127.0.0.1:3000 ops@web1
```

Then open `http://127.0.0.1:3000`. On the Contabo server, that answered `307` to
`/register`.

## Add a Cloudflare Tunnel

cloudflared 2026.9.1 came from Cloudflare's apt repository. A quick tunnel
(`cloudflared tunnel --url ...`, no account) stood in for a named tunnel. Both
ways below reached Traefik, whose answer to a host it has no router for is
`404 page not found`:

1. **cloudflared on the host.** The origin is `http://127.0.0.1:80`. cloudflared
   listened only on `127.0.0.1`, for its metrics port.
2. **cloudflared in a container.** Start the container with
   `--network dokploy-network`. The origin is `http://dokploy-traefik:80`.

With either one running, 80, 443 and 3000 still timed out from a non-tailnet
interface. A tunnel opens no inbound port, so it needs no `ufw route allow`.
ufw allows outbound connections by default, so cloudflared's connection out to
Cloudflare needs no rule.

A cloudflared container needs a restart policy. After a reboot, run on
2026-09-21, one started with `--restart unless-stopped` was running and
registered a new tunnel connection. One started with no restart flag stayed
`exited`, and the tunnel with it, so the site was unreachable until someone
started it again. Docker's default is no restart. Start it with
`--restart unless-stopped`. [After a reboot](./docker.md#after-a-reboot) has the
rest.

With a tunnel, do not open 80 and 443. If you publish without one,
[Docker on this server](./docker.md#expose-a-port-on-purpose) says how to open
a port on purpose.

## Run the tunnel as a Dokploy application

A tunnel that Cloudflare manages keeps its routes in the Cloudflare dashboard.
The server runs only a connector with the tunnel's token. On the Contabo server
the connector ran as a Dokploy application, made through Dokploy's API:

- Source: the Docker image `cloudflare/cloudflared:2026.9.1`.
- Arguments: `tunnel run`.
- Environment: `TUNNEL_TOKEN=<the tunnel's token>`.
- One replica.

Dokploy puts its applications on `dokploy-network`, so a route to
`http://dokploy-traefik:80` resolved. The connector registered four QUIC
connections and took the tunnel's routes within a few seconds.

Dokploy keeps the token in the application's environment, and its API returns it
to anyone with an API key.

After `systemctl reboot`, SSH answered at 38 seconds. The connector's service
was at 1/1 after about 47 seconds, with its four connections registered again.
Dokploy's own service was at 1/1 after about 84 seconds. The application had no
restart setting of its own. Swarm restarted it.

## Move a tunnel from another server

To move a running tunnel's connector to a new Dokploy server without downtime,
make the new server forward every host it has no application for to the old
server, then start the connector on the new one. This ran between two Dokploy
servers on one tailnet on 2026-09-21.

1. On the new server, add a file to `/etc/dokploy/traefik/dynamic/`:

   ```yaml
   http:
     routers:
       old-server:
         rule: HostRegexp(`^.+$`)
         priority: 1
         entryPoints:
           - web
         service: old-server
     services:
       old-server:
         loadBalancer:
           passHostHeader: true
           servers:
             - url: http://<the old server's tailnet address>:80
   ```

   Traefik watches the directory and picked the file up within seconds. A router
   for a real host has a longer rule, so it wins over this one.

2. On the new server, send the same request to its own Traefik and to the old
   server, for each host:

   ```sh
   curl -H 'Host: app.example.com' http://127.0.0.1:80/
   curl -H 'Host: app.example.com' http://<the old server's tailnet address>:80/
   ```

   Five hosts gave the same status and the same body on both, and an unknown
   host gave 404 on both.

3. Deploy the connector on the new server with the same token. The tunnel then
   has two connectors and both answer the same, so it does not matter which one
   takes a request.

4. Stop the connector on the old server. Requests then reach the old server's
   applications through the new one. Five hosts gave the same status codes
   through Cloudflare before and after. The new connector's
   `cloudflared_tunnel_total_requests` counter, on its metrics port, rose with
   the requests sent.

5. Move each application to the new server, as described in
   [Move the applications](#move-the-applications). When the last one has
   moved, delete the file.

## Move the applications

Restoring the old server's Dokploy database moves projects, applications,
composes, remote servers and users in one step. Both servers ran Dokploy 0.30.7.
This ran on 2026-09-21.

1. On the old server, dump the database and copy the file to the new server:

   ```sh
   docker exec <the Postgres container> pg_dump -U dokploy -Fc dokploy > dokploy.dump
   ```

2. On the new server, dump its own database the same way first. That is the way
   back.
3. Scale the dashboard to zero with `docker service scale dokploy=0`. Traefik
   and the tunnel connector keep running.
4. In the Postgres container, drop and create the `dokploy` database, then run
   `pg_restore -U dokploy -d dokploy --no-owner --no-privileges` on the dump.
5. Scale the dashboard back to one with `docker service scale dokploy=1`.

The counts of projects, applications, composes and servers matched the old
server, and the log showed no errors. The accounts and the API keys are the old
server's from then on.

Four things did not come across.

**Environment variables.** Dokploy stores them as `enc:v1:` values (AES-256-GCM)
with a key derived from the server's `BETTER_AUTH_SECRET`. The new server logged
`Failed to decrypt an encrypted column; returning the raw value`, so a deploy
would have passed the ciphertext as the environment. Dokploy reads extra keys
from `/etc/dokploy/encryption.key`, one 64-hex key per line. The function
`exportEncryptionKeys()` in the old server's
`@dokploy/server/dist/lib/encryption.js` prints the derived keys, not the raw
secret. Run it in the old server's `dokploy` container and pipe the output to
the new server. All 19 variables of a test application then decrypted.
Importing the module also prints a line of text, so keep only the lines that are
64 hex characters. Keep the file mode at 0600, owned by root. Dokploy
re-encrypts a value only when it next writes it, so the file stays needed. A
copy kept off the server makes a dump restorable after the server is lost.

**Traefik router files.** They are files in `/etc/dokploy/traefik/dynamic/`, not
database rows. A restored domain has no router until it is saved again. Calling
`domain.update` in the API with the same values writes `<app name>.yml`. Before
that, the new server answered the host through the forwarding file above and
gave the same answer, so only Traefik's router list showed the difference:

```sh
docker exec dokploy-traefik wget -qO- http://localhost:8080/api/http/routers
```

**The daily Docker cleanup.** `enableDockerCleanup` in the web server settings
came across as true. Images copied by hand are not in use yet, and the cleanup
can remove them, so turn it off until they are.

**The old dashboard's domain.** The web server setting `host` came across too.
Clear it, so the new server never routes that name. Both settings were changed
in the database while the dashboard was stopped.

### Copy the images

Images built on the old server have to reach the new one. This copied 8 images,
5.7 GB, in 9 minutes 50 seconds, about 15 MB/s over a tailnet:

```sh
docker save <images> | gzip -1 | ssh web2 'gunzip | docker load'
```

The image IDs differ on the two servers, because a classic image store and a
containerd store name the same image differently. The layer lists matched for
all 8:

```sh
docker image inspect --format '{{json .RootFS.Layers}}' <image>
```

### Deploy an image that exists only locally

A Docker-image application runs `docker pull` on every deploy. An image that
exists only in the local store fails with
`pull access denied ... repository does not exist`, and nothing is created. A
registry on the loopback address fixes it:

```sh
docker run -d --name registry --restart unless-stopped \
  -p 127.0.0.1:5000:5000 -v registry-data:/var/lib/registry registry:3
docker tag app:latest 127.0.0.1:5000/app:1
docker push 127.0.0.1:5000/app:1
```

Set `127.0.0.1:5000/app:1` as the application's image. Docker allows a loopback
registry over HTTP, and the pull reported the image as up to date straight away.
Turn the application's automatic deploy off, because it has no repository to
watch.

### Check that the new server answers

One application moved this way answered through the tunnel from the new server.
Twelve requests from outside all got the same answer as before, and the old
server's access log saw none of them. The status and the body matched what the
old server gave.

### Move a compose application

A compose application that builds from a repository has nothing to build from
once the repository is gone. Set its source to `raw`, paste the compose file as
it was at the deployed commit, and replace each `build:` with an `image:` from
the loopback registry. Volumes and host paths do not come across, so copy them
after a clean stop:

```sh
docker run --rm -v vol:/v:ro alpine tar cf - -C /v . \
  | ssh web2 'docker run --rm -i -v vol:/v alpine tar xf - --numeric-owner -C /v'
```

For a host path, mount the path in the first container and extract with
`sudo tar xf - --numeric-owner -p -C <path>` on the new server. Compose used
volumes that were created ahead of it and printed only a warning that it had not
created them. Row counts matched on three databases.

### Deploy a file mount

A Dokploy file mount is a database row that holds the content. Its file,
`/etc/dokploy/applications/<app name>/files`, was not on the new server after
the restore, and the service was rejected with
`bind source path does not exist`. Calling `mounts.update` with the same content
wrote nothing, because the row has no `filePath`. Copying the file from the old
server fixed it, and the two files had the same sha256.

### Move a database with its roles

`pg_dump` dumps one database. The roles of the cluster and the grants on its
tables are not part of it, and restoring with `--no-privileges` drops the
grants. A client that logged in as its own role got `role "..." does not exist`.
Dump the roles on the old server and apply them on the new one. An "already
exists" for the superuser is expected. Then restore only the ACL entries of the
dump:

```sh
pg_dumpall --globals-only > globals.sql
pg_restore -l dump | grep -E ' (DEFAULT )?ACL ' > acl.list
pg_restore -L acl.list --no-owner -d <database> dump
```

The image reads `POSTGRES_PASSWORD` only when it initializes a cluster. The
application's password differed from the compose environment, so the new cluster
refused it with `password authentication failed`. `ALTER ROLE ... PASSWORD`
fixed it. The grants matched the old server after this: the ACL of every table
and function hashed to the same value, and
`information_schema.role_table_grants` had the same 18 rows. Run
`vacuumdb --analyze-only` after a restore, because a restore leaves no
statistics. A 731 MB dump of a 4.3 GB database restored with `pg_restore -j 4`
in 289 seconds with no errors.

### Move a Tailscale Service host

The database was served to other servers through a Tailscale Service. A sidecar
container that shares the Postgres container's network namespace advertised it.
Its node identity is in its state volume. Stop the old sidecar, copy the volume,
and start the new sidecar with it. It came up under the same tailnet name and
address. `tailscale serve status` showed the Service, and a TCP connect to the
Service worked from the new server, the old one and a third server. The auth key
in the environment was not used. Never let two hosts advertise the Service at
once.

A host that connects to a Service hosted by a sidecar on the same machine goes
round through the tailnet. The connect took 157 ms. Point applications on that
machine at the local container's name instead.

### Names on a shared network

A container on a private network and on `dokploy-network` resolves a name in
either. On the new server the name `postgres` resolved to the database of
another application on `dokploy-network`, not to the application's own. That
database logged about 1,000 `sorry, too many clients already` and 283
`canceling authentication due to timeout` in five minutes. The application's own
database logged nothing. Use the container's full name, such as
`<project>-postgres-1`, in the connection string.

A container on the default bridge could not resolve tailnet names. A container
on `dokploy-network` could, and it also resolved another container by its name.

### After a reboot

The sidecars did not come back after `systemctl reboot`. Docker had tried to
start each one before the container whose network it joins was running, and it
did not retry: `cannot join network namespace of a non running container`. The
restart count was 0. A script that runs `docker start` on each sidecar that is
not running, from cron at `@reboot` and every five minutes, brought them back.
Everything else came back by itself: SSH after 65 seconds, and every Swarm
service and every compose container with a restart policy.

### Copy speed

The tailnet copy was limited by `tailscaled`, which used 100% of one core on the
receiving server. `ssh` reached about 15 MB/s. Four parallel streams and plain
TCP both totalled 10 to 14 MB/s. A 40 GB SQLite file that had not changed for
five weeks went over in 1 GiB chunks, four at a time, with
`dd skip=N | zstd -1 | ssh | zstd -d | dd seek=N conv=notrunc` into a file
created with `truncate` at its final size. `zstd -1` compressed a slice of it
2.55 to 1. The sha256 of the copy equalled the source's. 683,417 small files
took 47 minutes. A `docker run` client that was killed left its container
running. Its `tar` wrote the whole stream into the container's log and filled
the disk. Check with `docker ps` after you stop a copy.

## Not covered

- cloudflared as a systemd service on the host after a reboot.
- An application built from source and deployed through the dashboard, after a
  reboot. Only the connector, made through the API from an image, was tried.
- A database that needs more than Docker's stop timeout to shut down cleanly.
- How long a provider's server takes to boot.
- Certificates behind the tunnel. Traefik's Let's Encrypt HTTP-01 challenge
  cannot be answered through a tunnel. This is from reading, not tried.
