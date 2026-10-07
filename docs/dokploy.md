# Dokploy behind a Cloudflare Tunnel

A recipe for a server that you set up with vps-setup and then run Dokploy on,
behind a Cloudflare Tunnel. vps-setup does not install Docker, Dokploy or
cloudflared. A server set up another way has neither the guard nor the results
below.

Everything here was checked on an AWS Ubuntu server after a full `install` and
`close-ssh`. The install steps, the dashboard check and a named tunnel were also
checked on a Contabo server with Ubuntu 26.04. The versions are Dokploy 0.30.7,
cloudflared 2026.9.1. The Docker versions are named where they matter, in the
next section. Dokploy's installer is a third-party script and changes.

Run vps-setup first, then install Docker and Dokploy. The Docker guard of step
35 was in place before Docker in every run. See
[Docker on this server](./docker.md).

## Pick the Ubuntu release

Dokploy 0.30.7's installer installs Docker 28.5.0 through
`get.docker.com --version`. It holds `docker-ce`, `docker-ce-cli` and
`docker-ce-rootless-extras` with `apt-mark hold`. It skips its Docker step when
`docker` is already there.

With Dokploy 0.30.7, Docker's apt repository for 26.04 offered only 29.3.1 to
29.8.1, and the one for 24.04 offered 28.5.0. So the installer's pinned Docker
cannot install on a bare 26.04. `apt-cache madison docker-ce`, run after
Docker's repository is added, lists what the repository offers now.

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
the guard, that address does not answer from the internet.

## What the guard leaves open

After the install, Docker publishes 80, 443 and 3000. From a client on a
non-tailnet interface, all three timed out, over IPv4 and IPv6.

On the server, `127.0.0.1:80` answered 404. That is Traefik, which has no router
for that host. `127.0.0.1:3000` answered 307, which is the Dokploy dashboard.
Both answered about 26 seconds after a reboot, with the ports still closed.

A container on the `dokploy-network` overlay reached `dokploy-traefik:80` (404)
and `dokploy:3000` (307).

## Open the dashboard

From another machine on the tailnet, open
`http://<the server's tailnet name>:3000`. The
[tailnet policy](./tailnet-policy.md) must allow port 3000. On the Contabo
server, a tailnet device got `307` on port 3000 and `404` on port 80.

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
interface. A tunnel opens no inbound port, so it needs no `ufw route allow`. ufw
allows outbound connections by default, so cloudflared's connection out to
Cloudflare needs no rule.

Start a cloudflared container with `--restart unless-stopped`. One started with
no restart flag stayed `exited` after a reboot, and the tunnel with it. See
[After a reboot](./docker.md#after-a-reboot).

With a tunnel, do not open 80 and 443. If you publish without one,
[Docker on this server](./docker.md#expose-a-port-on-purpose) says how to open a
port on purpose.

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

## Not covered

- cloudflared as a systemd service on the host after a reboot.
- An application built from source and deployed through the dashboard, after a
  reboot. Only the connector, made through the API from an image, was tried.
- Certificates behind the tunnel. Traefik's Let's Encrypt HTTP-01 challenge
  cannot be answered through a tunnel. This is from reading, not tried.

To move to a new server, see [Move a Dokploy server](./dokploy-move.md).
