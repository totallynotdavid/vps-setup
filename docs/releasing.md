# Releasing

A release is a signed tag. The tag is the only thing that publishes.

## Cut a release

Write the release notes first. Replace `.github/release-notes.md` with the notes
for the new version and commit them. Its first line must be
`vps-setup X.Y.Z is out.`, and the notes follow it.

Then, from a clean checkout of `master` that matches `origin/master`:

```sh
mise run release vX.Y.Z
```

`bin/release` refuses unless all of these hold:

- the version looks like `vX.Y.Z`;
- the working tree is clean;
- the branch is `master`, and it matches `origin/master`;
- the tag does not exist locally or on `origin`;
- `mise run check` passes.

Then it creates a signed tag with `git tag -s`, so you need a signing key,
pushes the tag, and prints the URL of the release page.

The tag starts the release workflow (`.github/workflows/release.yml`). It has
three jobs:

- `preflight` fails if a job names an environment that the repository lacks, or
  if the tag already has a release.
- `build` checks the notes, runs `./build`, checks the checksum, builds a second
  time and fails if the two builds differ.
- `publish` waits for both, then creates a GitHub release that attaches
  `dist/install.sh` and `dist/install.sh.sha256`. The release body is
  `.github/release-notes.md` followed by GitHub's generated change list.

The notes check, `bin/check-release-notes`, fails if the tag is not `vX.Y.Z` or
the first line of the notes does not name the tag's version. Nothing generated
is committed, so the release is the only place the script is published. The
download URLs in [Manual setup](./manual-setup.md) point at the latest release.

## Dry run

The workflow also runs on every pull request and on a manual run
(`gh workflow run release.yml`). Those runs do everything a tag does except
`publish`, so a release that would fail fails before the tag. With no tag, the
notes check only requires the first line to name some `vX.Y.Z` version.

The release uses no secret and no environment. `publish` uses the job's own
`GITHUB_TOKEN`, so a maintainer who forks the project needs no account setup to
release.

## Test the build you publish

The release gate is `mise run e2e:aws:releases`: the AWS end-to-end must pass on
every release `supported_os` lists. Then do a run on a real provider server.
`bin/provision` builds `dist/install.sh` from the working tree, so running them
from the commit you are about to tag tests the script the tag will publish. See
[Testing](./testing.md).

## Check the published asset

Two builds of one tree are byte-identical. `build` fixes the sort order of the
fragments with `LC_ALL=C` and writes nothing that depends on the time or the
machine. So after the release, build the tag and compare it with the asset:

```sh
dir=$(mktemp -d)
git archive vX.Y.Z | tar -x -C "$dir"
(cd "$dir" && ./build && cat dist/install.sh.sha256)
curl -fsSL https://github.com/totallynotdavid/vps-setup/releases/download/vX.Y.Z/install.sh.sha256
```

The two digests are the same when the published script is the one built from the
tag.
