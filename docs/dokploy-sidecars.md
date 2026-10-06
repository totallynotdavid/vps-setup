# Move a Tailscale Service sidecar

Move a Tailscale Service host to a new server without changing its name or
address. This ran on 2026-09-21.

A database was served to other servers through a Tailscale Service. A sidecar
container that shares the Postgres container's network namespace advertised it.
Its node identity is in its state volume. Stop the old sidecar, copy the volume,
and start the new sidecar with it. It came up under the same tailnet name and
address. `tailscale serve status` showed the Service, and a TCP connect to the
Service worked from the new server, the old one and a third server. The auth key
in the environment was not used.

Never let two hosts advertise the Service at once.

A host that connects to a Service hosted by a sidecar on the same machine goes
round through the tailnet. The connect took 157 ms. Point applications on that
machine at the local container's name instead.

## After a reboot

The sidecars did not come back after `systemctl reboot`. Docker had tried to
start each one before the container whose network it joins was running, and it
did not retry: `cannot join network namespace of a non running container`. The
restart count was 0.

A script that runs `docker start` on each sidecar that is not running, from cron
at `@reboot` and every five minutes, brought them back. Everything else came
back by itself: SSH after 65 seconds, and every Swarm service and every compose
container with a restart policy.
