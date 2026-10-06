# vps-setup manual

- [Get started](./get-started.md): requirements, the first run and what it
  prints.
- [Manual setup](./manual-setup.md): the same flow by hand, without cloning the
  repository.
- [Inputs](./inputs.md): every variable and argument of `install.sh`,
  `bin/provision` and `bin/resolve-key`.
- [Auth key](./auth-key.md): skip the login URL with an OAuth client or an auth
  key.
- [Tailnet policy](./tailnet-policy.md): the rules that let your machine SSH to
  the server.
- [Docker on this server](./docker.md): the firewall guard, opening a port, and
  restarts after a reboot.
- [Dokploy behind a Cloudflare Tunnel](./dokploy.md): install Dokploy and
  publish it through a tunnel.
- [Move a Dokploy server](./dokploy-move.md): hand a tunnel and the Dokploy
  database to a new server.
- [Move Dokploy applications](./dokploy-apps.md): images, compose applications,
  file mounts and names on a shared network.
- [Move a Postgres database](./dokploy-databases.md): roles, grants and
  passwords.
- [Move a Tailscale Service sidecar](./dokploy-sidecars.md): keep a Service's
  name and address on the new server.
- [Copy data between servers](./copy-data.md): images, volumes, and copy speed
  with `rsync` and parallel `tar`.
- [How it works](./how-it-works.md): what each step does on the server, and why
  in that order.
- [Design boundaries](./design-boundaries.md): what the tool will not do.
- [Testing](./testing.md): the unit tests and the end-to-end harness.
- [Releasing](./releasing.md): cut and check a release.
