#!/usr/bin/env bash
# The step lists build writes, and the dispatcher that runs them, against the
# generated dist/install.sh without its final `main "$@"`.
set -euo pipefail

cd "$(dirname "$0")/.."
export LC_ALL=C
script=dist/install.sh
[[ -f $script ]] || {
	echo "error: $script is missing; run ./build first" >&2
	exit 1
}

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

head -n -1 "$script" >"$tmp/definitions.sh"
# shellcheck source=/dev/null
source "$tmp/definitions.sh"

is_function() {
	declare -F "$1" >/dev/null
}

all_are_functions() {
	local step
	for step in "$@"; do
		is_function "$step" || return 1
	done
}

# The list holds one step per file of the phase, in file name order.
lists_each_file() {
	local phase=$1 directory=$2 list=$3 file name expected=()
	local -n steps=$list
	for file in "$directory"/*.sh; do
		name=${file##*/}
		name=${name%.sh}
		expected+=("${phase}_${name//-/_}")
	done
	[[ ${steps[*]} == "${expected[*]}" ]]
}

assert "install_steps has a step for each file in steps/install, in order" \
	lists_each_file install steps/install install_steps
assert "close_ssh_steps has a step for each file in steps/close-ssh, in order" \
	lists_each_file close_ssh steps/close-ssh close_ssh_steps
assert "every install step is a defined function" all_are_functions "${install_steps[@]}"
assert "every close-ssh step is a defined function" all_are_functions "${close_ssh_steps[@]}"

# A function whose name starts with a phase name is a step only when it is listed.
# The fake steps and helpers record their names. The gates are stubbed out.
calls=$tmp/calls
require_supported_os() { :; }
require_root() { :; }
log() { :; }
install_steps=(install_first install_second)
install_first() { echo install_first >>"$calls"; }
install_second() { echo install_second >>"$calls"; }
install_helper() { echo install_helper >>"$calls"; }
close_ssh_steps=(close_ssh_only)
close_ssh_only() { echo close_ssh_only >>"$calls"; }

ran() {
	[[ $(tr '\n' ' ' <"$calls") == "$1 " ]]
}

: >"$calls"
main install
assert "install runs its listed steps in list order" ran "install_first install_second"

: >"$calls"
main close-ssh
assert "close-ssh runs only its own steps" ran "close_ssh_only"

failing_step() { return 3; }
install_steps=(install_first failing_step install_second)
: >"$calls"
set +e
(
	set -e
	main install
)
status=$?
set -e
assert "a failing step stops the phase with its status" [ "$status" -eq 3 ]
assert "a failing step keeps later steps from running" ran "install_first"

((failures == 0))
