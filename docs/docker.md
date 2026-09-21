# Docker on this server

vps-setup does not install Docker. It makes sure that ufw's promise still
holds if you install it later: nothing reaches a container from outside the
tailnet unless you say so.

## Why a guard is needed

Docker publishes a container's port with iptables rules that run in `FORWARD`,
before ufw's `INPUT` rules. So "ufw: deny incoming" does not cover containers.
On Ubuntu 26.04 with ufw active and Docker 29.8.1, a plain `docker run -p`, a
Swarm ingress service and a Swarm `mode=host` service all answered a client that
arrived on a non-tailnet interface. Step 35 closes that.
[How it works](./how-it-works.md#install) says how.

## What the guard does

Docker runs the `DOCKER-USER` chain first and never flushes it. Step 35 fills
it, for IPv4 and IPv6:

- Traffic that arrives on `lo`, `tailscale0`, `docker0`, `docker_gwbridge` or an
  interface named `br-...` is not filtered by the guard. Docker's own rules
  decide.
- Any other new connection into a container is dropped, unless a
  `ufw route allow` rule accepted it.
- An interface name the guard does not know is treated as public.

With the guard, the three kinds of published port above timed out from a
non-tailnet interface, and `127.0.0.1` still answered. A container could still
reach the internet. The guard survived `ufw reload`, `systemctl restart docker`
and a reboot. Without Docker installed, the chain is empty and nothing changes.

## Reach a published port

- On the server, use `127.0.0.1`: `curl http://127.0.0.1:8080/`.
- From another machine on the tailnet, use the server's tailnet name or address:
  `curl http://web1:8080/`. Your [tailnet policy](./tailnet-policy.md) must
  also allow the port, because a grant lists the ports it opens.

## Expose a port on purpose

Add a route rule:

```sh
sudo ufw route allow proto tcp from any to any port 80
```

The port is the container's port, the one after the colon in `-p 8080:80`,
because Docker has already rewritten the destination when the guard sees the
packet. The rule opens that port on every container that listens on it. For a
Swarm service in ingress mode, allow the published port. Close a port again with
the same rule after `delete`:

```sh
sudo ufw route delete allow proto tcp from any to any port 80
```

A Cloudflare Tunnel opens no inbound port. See
[Dokploy behind a Cloudflare Tunnel](./dokploy.md).

## A bridge with its own name

The guard trusts Docker's bridge names. A bridge with any other name is
blocked. Allow it with:

```sh
sudo ufw route allow in on <bridge>
```

## After a reboot

The server reboots itself after an update that needs it. See
[Inputs](./inputs.md). `AUTO_REBOOT=off` turns it off.

This was run on 2026-09-21 on an AWS Ubuntu 26.04 server, after a full `install`
and `close-ssh`, with Docker 29.8.1 and Dokploy 0.30.7. The reboot was scheduled
with `shutdown -r +1`, which is how `unattended-upgrades` issues it.

- Containers started with `--restart unless-stopped` were running after the
  boot: a plain `docker run`, a compose service with
  `restart: unless-stopped`, and a cloudflared container, which registered a new
  tunnel connection.
- Containers started with no restart flag stayed `exited`: a plain `docker run`,
  a compose service without `restart:`, and a cloudflared container.
  `docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' NAME` printed `no` for
  them, so Docker's default is `no`.
- Traefik, whose restart policy is `always`, answered 404 on `127.0.0.1:80`
  15 seconds after boot.
- Dokploy's own services, which run on Swarm, came back about 26 seconds after a
  reboot, on 24.04 and on 26.04. A snapshot taken 15 seconds after boot still
  showed Swarm services at `0/1`, so give them a minute.
- The guard was loaded for IPv4 and IPv6 after the boot, and ports 80, 443 and
  3000 timed out from a non-tailnet interface.
- SSH answered again about 20 seconds after the reboot began. A provider's
  server may take longer.

Every container that has to come back needs a restart policy:
`--restart unless-stopped` for `docker run`, `restart: unless-stopped` in a
compose file. A cloudflared container without one stays down, and the tunnel
with it, so the site is unreachable until someone starts it again. Nothing on a
Tailscale-only server shows that. Start it with `--restart unless-stopped`.

Not covered:

- cloudflared as a systemd service on the host after a reboot.
- An application deployed through the Dokploy dashboard after a reboot.
- A database that needs more than Docker's stop timeout to shut down cleanly.
- How long a provider's server takes to boot.

## What it does not cover

- **Swarm's own ports.** 2377, 7946 and 4789 are host ports, and ufw's input
  rules already block them.
- **`--network host`.** Such a container listens on the host itself, so ufw's
  input rules cover it.
- **Docker's nftables backend.** The guard is made of iptables rules, and only
  Docker's iptables backend uses `DOCKER-USER`.

## Update Docker yourself

`unattended-upgrades` does not update Docker. Docker's repository is not an
allowed origin, on purpose. Some tools pin a Docker version, and Docker 29
raised the minimum API version and broke older Traefik. Update Docker when you
have checked what runs on it.
