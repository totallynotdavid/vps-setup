install_20_tailscale() {
	tailscale_ensure_installed
	systemctl enable --now tailscaled
	tailscale_join
}

tailscale_ensure_installed() {
	command -v tailscale >/dev/null && return 0
	tailscale_add_repo
	apt_get update
	apt_get install tailscale
}

tailscale_add_repo() {
	local base codename
	codename=$(os_field VERSION_CODENAME)
	base=https://pkgs.tailscale.com/stable/ubuntu/$codename
	tailscale_fetch "$base.noarmor.gpg" /usr/share/keyrings/tailscale-archive-keyring.gpg
	tailscale_fetch "$base.tailscale-keyring.list" /etc/apt/sources.list.d/tailscale.list
}

tailscale_fetch() {
	local url=$1 dest=$2 tmp
	tmp=$(mktemp)
	curl -fsSL "$url" -o "$tmp" || die "download failed: $url"
	install -m 0644 "$tmp" "$dest"
	rm -f "$tmp"
}

# Pass all flags; tailscale up refuses to change running nodes without repeating every non-default flag.
tailscale_join() {
	local args=(--ssh "--hostname=$TS_HOSTNAME" --timeout=10m)
	if [[ -n $TS_TAGS ]]; then
		args+=("--advertise-tags=$TS_TAGS")
	fi
	if [[ -n $TS_AUTHKEY_FILE ]]; then
		args+=("--auth-key=file:$TS_AUTHKEY_FILE")
	fi
	tailscale up "${args[@]}"
}
