# Dokploy behind a Cloudflare Tunnel

vps-setup does not install Docker, Dokploy or cloudflared. This page is a
recipe for a server that you set up with vps-setup and then run Dokploy on,
behind a Cloudflare Tunnel. A server set up another way has neither the guard
nor the results below.

Everything here was run on an AWS Ubuntu server on 2026-09-21, after a full
`install` and `close-ssh`. The versions are Dokploy 0.30.7, cloudflared 2026.9.1
and the packages in Docker's repositories on that day. Dokploy's installer is a
third-party script and will change.

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

## What the guard leaves open

After the install, Docker publishes 80, 443 and 3000. From a
client on a non-tailnet interface, 80, 443 and 3000 all timed out, over IPv4
and IPv6.

On the server, `127.0.0.1:80` answered 404. That is Traefik, which has no router
for that host. `127.0.0.1:3000` answered 307, which is the Dokploy dashboard.
Both answered about 26 seconds after a reboot, with the ports still closed.

A container on the `dokploy-network` overlay reached `dokploy-traefik:80` (404)
and `dokploy:3000` (307).

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

With a tunnel, do not open 80 and 443. If you publish without one,
[Docker on this server](./docker.md#expose-a-port-on-purpose) says how to open
a port on purpose.

## Not covered

- A named tunnel with a token and a public hostname, such as `app.example.com`.
- A Dokploy application routed through the tunnel.
- Certificates behind the tunnel. Traefik's Let's Encrypt HTTP-01 challenge
  cannot be answered through a tunnel. This is from reading, not tried.
- Reaching the dashboard from another tailnet machine. See
  [Docker on this server](./docker.md#reach-a-published-port) for the general
  rule and [Tailnet policy](./tailnet-policy.md) for the policy.
