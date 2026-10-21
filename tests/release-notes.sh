#!/usr/bin/env bash
# Tests bin/check-release-notes with and without a tag. It runs offline and needs no root.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source-path=SCRIPTDIR/..
source tests/lib/helpers.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

notes() {
	printf '%s\n\nBody.\n' "$1" >"$tmp/notes.md"
}

# Succeeds if bin/check-release-notes accepts the notes file and optional tag.
accepts() {
	bin/check-release-notes "$tmp/notes.md" "$@" 2>"$tmp/stderr"
}

refuses() {
	! accepts "$@"
}

notes 'vps-setup 0.4.0 is out.'
assert "notes naming the tag's version pass" accepts v0.4.0
assert "a dry run takes notes that name any version" accepts
assert "notes naming another version fail for a tag" refuses v0.5.0
assert "a tag that is not vX.Y.Z fails" refuses 0.4.0
assert "a tag with a suffix fails" refuses v0.4.0-rc1
assert "a version prefix is not a substring match" refuses v0.4.00

notes 'vps-setup 0.4 is out.'
assert "notes without a full version fail a dry run" refuses

notes 'Release 0.4.0.'
assert "notes without the standard first line fail a dry run" refuses
assert "the error shows the first line it found" grep -q "Release 0.4.0." "$tmp/stderr"

printf '\nvps-setup 0.4.0 is out.\n' >"$tmp/notes.md"
assert "a blank first line fails" refuses

rm "$tmp/notes.md"
assert "a missing notes file fails" refuses

((failures == 0))
