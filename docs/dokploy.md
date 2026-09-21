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

5. Deploy each application on the new server with its domain as it moves. When
   the last one has moved, delete the file.

## Not covered

- A Dokploy application routed through the tunnel.
- cloudflared as a systemd service on the host after a reboot.
- An application built from source and deployed through the dashboard, after a
  reboot. Only the connector, made through the API from an image, was tried.
- A database that needs more than Docker's stop timeout to shut down cleanly.
- How long a provider's server takes to boot.
- Certificates behind the tunnel. Traefik's Let's Encrypt HTTP-01 challenge
  cannot be answered through a tunnel. This is from reading, not tried.
