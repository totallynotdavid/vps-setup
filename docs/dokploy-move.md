# Move a Dokploy server

Move a running tunnel's connector and the Dokploy database to a new server
without downtime. This was checked between two Dokploy 0.30.7 servers on one
tailnet. [Dokploy behind a Cloudflare Tunnel](./dokploy.md) sets one up.

The order is:

1. [Forward unknown hosts to the old server](#forward-unknown-hosts-to-the-old-server).
2. [Move the connector](#move-the-connector).
3. [Restore the Dokploy database](#restore-the-dokploy-database).
4. [Fix what did not come across](#fix-what-did-not-come-across).
5. Move each application and its data:
   [Move Dokploy applications](./dokploy-apps.md),
   [Move a Postgres database](./dokploy-databases.md),
   [Move a Tailscale Service sidecar](./dokploy-sidecars.md) and
   [Copy data between servers](./copy-data.md).
6. [Check that the new server answers](#check-that-the-new-server-answers).
7. Delete the forwarding file once the last application has moved.

## Forward unknown hosts to the old server

On the new server, make Traefik forward every host it has no application for to
the old server. Add a file to `/etc/dokploy/traefik/dynamic/`:

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

Send the same request to the new server's Traefik and to the old server, for
each host:

```sh
curl -H 'Host: app.example.com' http://127.0.0.1:80/
curl -H 'Host: app.example.com' http://<the old server's tailnet address>:80/
```

Five hosts gave the same status and the same body on both, and an unknown host
gave 404 on both.

## Move the connector

Deploy the connector on the new server with the same token. See
[Run the tunnel as a Dokploy application](./dokploy.md#run-the-tunnel-as-a-dokploy-application).
The tunnel then has two connectors and both answer the same, so it does not
matter which one takes a request.

Stop the connector on the old server. Requests then reach the old server's
applications through the new one. Five hosts gave the same status codes through
Cloudflare before and after. The new connector's
`cloudflared_tunnel_total_requests` counter, on its metrics port, rose with the
requests sent.

## Restore the Dokploy database

Restoring the old server's Dokploy database moves projects, applications,
composes, remote servers and users in one step. Both servers ran Dokploy 0.30.7.

1. On the old server, dump the database:

   ```sh
   docker exec <the Postgres container> pg_dump -U dokploy -Fc dokploy > dokploy.dump
   ```

   Copy `dokploy.dump` to the new server. See
   [Copy data between servers](./copy-data.md).

2. On the new server, dump its own database the same way first. That is the way
   back.
3. Scale the dashboard to zero with `docker service scale dokploy=0`. Traefik
   and the tunnel connector keep running.
4. Drop and create the `dokploy` database in the Postgres container, then
   restore the dump:

   ```sh
   docker exec <the Postgres container> dropdb -U dokploy dokploy
   docker exec <the Postgres container> createdb -U dokploy dokploy
   docker exec -i <the Postgres container> pg_restore -U dokploy -d dokploy --no-owner --no-privileges < dokploy.dump
   ```

5. Scale the dashboard back to one with `docker service scale dokploy=1`.

The counts of projects, applications, composes and servers matched the old
server, and the log showed no errors. The accounts and the API keys are the old
server's from then on.

## Fix what did not come across

**Environment variables.** Dokploy stores them as `enc:v1:` values (AES-256-GCM)
with a key derived from the server's `BETTER_AUTH_SECRET`. The new server logged
`Failed to decrypt an encrypted column; returning the raw value`, so a deploy
would have passed the ciphertext as the environment. Dokploy reads extra keys
from `/etc/dokploy/encryption.key`, one 64-hex key per line. The function
`exportEncryptionKeys()` in the old server's
`@dokploy/server/dist/lib/encryption.js` prints the derived keys, not the raw
secret. Run it in the old server's `dokploy` container and pipe the output to
the new server. All 19 variables of a test application then decrypted. Importing
the module also prints a line of text, so keep only the lines that are 64 hex
characters. Keep the file mode at 0600, owned by root. Dokploy re-encrypts a
value only when it next writes it, so the file stays needed. A copy kept off the
server makes a dump restorable after the server is lost.

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

## Check that the new server answers

One application moved this way answered through the tunnel from the new server.
Twelve requests from outside all got the same answer as before, and the old
server's access log saw none of them. The status and the body matched what the
old server gave.
