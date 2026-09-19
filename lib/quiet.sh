# Runs a command with stdout and stderr captured together. Silent on success;
# on failure prints everything it wrote to stderr and keeps its exit status.
quiet() {
	local output status=0
	output=$("$@" 2>&1) || status=$?
	if ((status != 0)); then
		printf '%s\n' "$output" >&2
	fi
	return "$status"
}
