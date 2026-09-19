install_10_user() {
	user_create
	user_grant_sudo
}

user_create() {
	id "$ADMIN_USER" &>/dev/null || quiet adduser --disabled-password --gecos "" "$ADMIN_USER"
	quiet usermod -aG sudo "$ADMIN_USER"
}

user_grant_sudo() {
	local tmp
	tmp=$(mktemp)
	printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$ADMIN_USER" >"$tmp"
	if ! quiet visudo -cf "$tmp"; then
		rm -f "$tmp"
		die "generated sudoers entry for '$ADMIN_USER' did not validate"
	fi
	install -m 0440 -o root -g root "$tmp" "/etc/sudoers.d/$ADMIN_USER"
	rm -f "$tmp"
}
