#!/usr/bin/env bash
# The first-boot wait, run against the source fragments with a fake cloud-init.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source-path=SCRIPTDIR/..
source lib/log.sh
source steps/install/05-first-boot.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
system_path=$PATH

# The fake logs its arguments and exits with $FAKE_STATUS. The fake timeout stands
# in for one that expired.
mkdir "$tmp/empty" "$tmp/bin" "$tmp/expired"
cat >"$tmp/bin/cloud-init" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_CALLS"
echo '.....'
exit "$FAKE_STATUS"
FAKE
printf '#!/usr/bin/env bash\nexit 124\n' >"$tmp/expired/timeout"
chmod +x "$tmp/bin/cloud-init" "$tmp/expired/timeout"
export FAKE_CALLS=$tmp/calls

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

# Sets status, stdout and stderr for the step on the given PATH, with cloud-init exiting as given.
run_step() {
	local path=$1
	FAKE_STATUS=${2-0}
	export FAKE_STATUS
	rm -f "$FAKE_CALLS"
	status=0
	stdout=$(PATH=$path install_05_first_boot 2>"$tmp/stderr") || status=$?
	stderr=$(<"$tmp/stderr")
}

run_step "$tmp/empty"
assert "no cloud-init: returns 0" [ "$status" -eq 0 ]
assert "no cloud-init: calls nothing" [ ! -e "$FAKE_CALLS" ]
assert "no cloud-init: prints nothing" [ -z "$stdout$stderr" ]

run_step "$tmp/bin:$system_path" 1
assert "cloud-init exits 1: returns 0" [ "$status" -eq 0 ]
assert "cloud-init exits 1: calls it once, with status --wait" [ "$(<"$FAKE_CALLS")" == 'status --wait' ]
assert "cloud-init exits 1: says it is waiting" [ "$stderr" == '==> waiting for the provider'\''s first-boot setup to finish' ]
assert "cloud-init exits 1: keeps its output off stdout" [ -z "$stdout" ]

run_step "$tmp/expired:$tmp/bin:$system_path"
assert "the wait times out: returns 0" [ "$status" -eq 0 ]
assert "the wait times out: does not run cloud-init" [ ! -e "$FAKE_CALLS" ]

((failures == 0))
