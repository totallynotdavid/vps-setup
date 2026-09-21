# Releasing

A release is a signed tag. The tag is the only thing that publishes.

## Cut a release

From a clean checkout of `master` that matches `origin/master`:

```sh
mise run release vX.Y.Z
```

`bin/release` refuses unless all of these hold:

- the version looks like `vX.Y.Z`;
- the working tree is clean;
- the branch is `master`, and it matches `origin/master`;
- the tag does not exist locally or on `origin`;
- `mise run check` passes.

Then it creates a signed tag with `git tag -s`, so you need a signing key, pushes
the tag, and prints the URL of the release page.

The tag starts the release workflow (`.github/workflows/release.yml`). It runs
`./build` on the tagged commit and creates a GitHub release that attaches
`dist/install.sh` and `dist/install.sh.sha256`, with generated notes. Nothing
generated is committed, so the release is the only place the script is published.
The download URLs in [Manual setup](./manual-setup.md) point at the latest
release.

## Tested build, published asset

The release gate is `mise run e2e:aws:releases`: the AWS end-to-end must pass on
every release `supported_os` lists. Then do a run on a real provider server.
`bin/provision` builds `dist/install.sh` from the working tree, so running them
from the commit you are about to tag tests the script the tag will publish. See
[Testing](./testing.md).

Two builds of one tree are byte-identical. `build` fixes the sort order of the
fragments with `LC_ALL=C` and writes nothing that depends on the time or the
machine. So after the release, build the tag and compare it with the asset:

```sh
dir=$(mktemp -d)
git archive vX.Y.Z | tar -x -C "$dir"
(cd "$dir" && ./build && cat dist/install.sh.sha256)
curl -fsSL https://github.com/totallynotdavid/vps-setup/releases/download/vX.Y.Z/install.sh.sha256
```

The two digests are the same when the published script is the one built from
the tag.
