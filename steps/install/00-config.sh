install_00_config() {
	ADMIN_USER=${ADMIN_USER:-admin}
	TS_HOSTNAME=${TS_HOSTNAME:-$(hostname -s)}
	TS_TAGS=${TS_TAGS:-}
	TS_AUTHKEY_FILE=${TS_AUTHKEY_FILE:-}

	config_check_admin_user
	config_check_hostname
	config_check_tags
	config_check_authkey_file
}

config_check_admin_user() {
	local re='^[a-z_][a-z0-9_-]*$'
	[[ $ADMIN_USER =~ $re ]] ||
		die "ADMIN_USER '$ADMIN_USER' is invalid; use lowercase letters, digits, '_' and '-', starting with a letter or '_'"
}

config_check_hostname() {
	local re='^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'
	[[ $TS_HOSTNAME =~ $re ]] ||
		die "TS_HOSTNAME '$TS_HOSTNAME' is invalid; use one DNS label: lowercase letters, digits and '-', 1-63 characters, not starting or ending with '-'"
}

config_check_tags() {
	local re='^tag:[a-z0-9-]+(,tag:[a-z0-9-]+)*$'
	[[ -z $TS_TAGS || $TS_TAGS =~ $re ]] ||
		die "TS_TAGS '$TS_TAGS' is invalid; use comma-separated tags like tag:server,tag:web (lowercase letters, digits and '-')"
}

config_check_authkey_file() {
	[[ -z $TS_AUTHKEY_FILE || (-f $TS_AUTHKEY_FILE && -r $TS_AUTHKEY_FILE) ]] ||
		die "TS_AUTHKEY_FILE '$TS_AUTHKEY_FILE' is not a readable regular file"
}
