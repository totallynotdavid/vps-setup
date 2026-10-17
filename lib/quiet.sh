quiet() {
	local output status=0
	output=$("$@" 2>&1) || status=$?
	if ((status != 0)); then
		printf '%s\n' "$output" >&2
	fi
	return "$status"
}
