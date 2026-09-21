#!/usr/bin/env bash
# bin/resolve-key against a fake curl that records what it is given. Offline, needs no root.
set -euo pipefail

cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

assert() {
	local description=$1
	shift
	if "$@"; then
		printf 'PASS %s\n' "$description"
	else
		printf 'FAIL %s\n' "$description"
		failures=$((failures + 1))
	fi
}

fake=$tmp/fake
mkdir -p "$fake" "$tmp/bin"
# Records argv and stdin of call N in argv.N and stdin.N, then answers by URL.
cat >"$tmp/bin/curl" <<'FAKE'
#!/usr/bin/env bash
n=$(($(cat "$FAKE_DIR/count" 2>/dev/null || echo 0) + 1))
echo "$n" >"$FAKE_DIR/count"
printf '%s\n' "$@" >"$FAKE_DIR/argv.$n"
cat >"$FAKE_DIR/stdin.$n"
case $(sed -n 's/^url = "\(.*\)"$/\1/p' "$FAKE_DIR/stdin.$n") in
*/oauth/token) cat "$FAKE_DIR/token.json" ;;
*/tailnet/-/keys) cat "$FAKE_DIR/key.json" ;;
esac
FAKE
chmod +x "$tmp/bin/curl"

# Joined at run time so the source holds no string shaped like a Tailscale key.
fake_key() {
	printf 'tskey-%s-%s' "$1" "$2"
}

secret=$(fake_key client k7nQpX3CNTRL-s3cr3tS3cr3tS3cr3t)
token=$(fake_key api kTOKEN123-t0kent0kent0ken)
minted=$(fake_key auth kMINTED456CNTRL-m1ntedm1ntedm1nted)
plain=$(fake_key auth kPLAIN789CNTRL-plainplainplain)

reset_fake() {
	rm -f "$fake"/argv.* "$fake"/stdin.* "$fake"/count
	printf '{"access_token":"%s","token_type":"Bearer","expires_in":3600}\n' "$token" >"$fake/token.json"
	printf '{"id":"k123","key":"%s","created":"2026-01-01T00:00:00Z","capabilities":{}}\n' "$minted" >"$fake/key.json"
}

# Sets status, stdout and stderr for bin/resolve-key with the given environment.
resolve() {
	local file=$1
	shift
	status=0
	stdout=$(env -u TS_TAGS -u TS_EPHEMERAL -u TS_HOSTNAME PATH="$tmp/bin:$PATH" FAKE_DIR="$fake" "$@" \
		bin/resolve-key "$file" 2>"$tmp/stderr" </dev/null) || status=$?
	stderr=$(<"$tmp/stderr")
}

calls() {
	cat "$fake/count" 2>/dev/null || echo 0
}

# The JSON body of call N, unescaped from the curl config line.
body() {
	sed -n 's/^data = "\(.*\)"$/\1/p' "$fake/stdin.$1" | sed 's/\\"/"/g'
}

# Succeeds if the command fails.
refute() {
	! "$@"
}

leaks_into_argv() {
	local needle n
	for needle in "$@"; do
		for n in "$fake"/argv.*; do
			grep -qF -- "$needle" "$n" && return 0
		done
	done
	return 1
}

body_for() {
	printf '{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":%s,"preauthorized":true,"tags":[%s]}}},"expirySeconds":3600,"description":"%s"}' "$@"
}

printf '%s\n' "$plain" >"$tmp/plain.key"
printf '%s\n' "$secret" >"$tmp/oauth.key"

reset_fake
resolve "$tmp/plain.key" TS_TAGS=tag:server
assert "a plain key exits 0" [ "$status" -eq 0 ]
assert "a plain key is printed unchanged" [ "$stdout" == "$plain" ]
assert "a plain key does not call curl" [ "$(calls)" -eq 0 ]

reset_fake
resolve "$tmp/oauth.key" TS_TAGS=tag:server,tag:web TS_HOSTNAME=web1
assert "an OAuth secret exits 0" [ "$status" -eq 0 ]
assert "an OAuth secret makes exactly two calls" [ "$(calls)" -eq 2 ]
assert "the first call asks for a token" grep -qF 'url = "https://api.tailscale.com/api/v2/oauth/token"' "$fake/stdin.1"
assert "the token call sends the client credentials" \
	grep -qF "data = \"grant_type=client_credentials&client_id=k7nQpX3CNTRL&client_secret=$secret\"" "$fake/stdin.1"
assert "the second call creates a key" grep -qF 'url = "https://api.tailscale.com/api/v2/tailnet/-/keys"' "$fake/stdin.2"
assert "the key call carries the token from the first response" \
	grep -qF "header = \"Authorization: Bearer $token\"" "$fake/stdin.2"
assert "the key call sends JSON" grep -qF 'header = "Content-Type: application/json"' "$fake/stdin.2"
assert "stdout is exactly the minted key" [ "$stdout" == "$minted" ]
assert "the config goes in on stdin" [ "$(<"$fake/argv.1")" == $'-q\n--config\n-' ]
assert "the secret, token and minted key stay out of every argv" \
	refute leaks_into_argv "$secret" "k7nQpX3CNTRL-s3cr3t" "$token" "$minted"
assert "the key request is one-use, pre-approved, tagged, not ephemeral, named for the host" \
	[ "$(body 2)" == "$(body_for false '"tag:server","tag:web"' 'vps-setup web1')" ]

reset_fake
resolve "$tmp/oauth.key" TS_TAGS=tag:server TS_EPHEMERAL=1
assert "TS_EPHEMERAL=1 makes the key ephemeral" [ "$(body 2)" == "$(body_for true '"tag:server"' 'vps-setup')" ]

reset_fake
resolve "$tmp/oauth.key" TS_TAGS=tag:server TS_HOSTNAME='a.b_c/d'"$(printf 'x%.0s' {1..60})"
description=$(body 2 | sed 's/.*"description":"\([^"]*\)".*/\1/')
assert "the description keeps to 50 alphanumerics, hyphens and spaces" \
	grep -Eq '^[A-Za-z0-9 -]{1,50}$' <<<"$description"

reset_fake
resolve "$tmp/oauth.key"
assert "a missing TS_TAGS exits non-zero" [ "$status" -ne 0 ]
assert "a missing TS_TAGS says the secret needs tags matching the client's" \
	grep -q "OAuth client secret needs TS_TAGS matching the client's tags" <<<"$stderr"
assert "a missing TS_TAGS makes no curl call" [ "$(calls)" -eq 0 ]

reset_fake
resolve "$tmp/oauth.key" 'TS_TAGS=server'
assert "a malformed tag exits non-zero" [ "$status" -ne 0 ]
assert "a malformed tag makes no curl call" [ "$(calls)" -eq 0 ]

reset_fake
printf '{"message":"invalid client credentials for %s"}\n' "$secret" >"$fake/token.json"
resolve "$tmp/oauth.key" TS_TAGS=tag:server
assert "a token error exits non-zero" [ "$status" -ne 0 ]
assert "a token error prints the API's message" grep -q 'invalid client credentials' <<<"$stderr"
assert "a token error does not print the secret" refute grep -qF -- "k7nQpX3CNTRL-s3cr3t" <<<"$stderr$stdout"
assert "a token error stops after the token call" [ "$(calls)" -eq 1 ]

reset_fake
printf '{"message":"requested tags [tag:server] are invalid or not permitted"}\n' >"$fake/key.json"
resolve "$tmp/oauth.key" TS_TAGS=tag:server
assert "a key error exits non-zero" [ "$status" -ne 0 ]
assert "a key error prints the API's message" grep -q 'requested tags \[tag:server\] are invalid' <<<"$stderr"
assert "a key error prints neither the secret nor the token" \
	refute grep -qE "k7nQpX3CNTRL-s3cr3t|t0kent0ken" <<<"$stderr$stdout"
assert "a key error prints no key on stdout" [ -z "$stdout" ]

reset_fake
printf '%s?ephemeral=false&preauthorized=false\n' "$secret" >"$tmp/suffix.key"
resolve "$tmp/suffix.key" TS_TAGS=tag:server TS_EPHEMERAL=1
assert "a ?suffix on the secret is not sent" refute grep -qF '?' "$fake/stdin.1"
assert "a ?suffix on the secret does not decide ephemeral" [ "$(body 2)" == "$(body_for true '"tag:server"' 'vps-setup')" ]

reset_fake
printf '\n' >"$tmp/empty.key"
resolve "$tmp/empty.key"
assert "an empty key file exits non-zero" [ "$status" -ne 0 ]

resolve "$tmp/missing.key"
assert "a missing file exits non-zero" [ "$status" -ne 0 ]

((failures == 0))
