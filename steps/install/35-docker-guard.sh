install_35_docker_guard() {
	docker_guard_apply /etc/ufw/after.rules ufw-user-forward /etc/ufw/after6.rules ufw6-user-forward
}

# Published container ports are filtered in FORWARD, ahead of ufw's INPUT rules.
# DOCKER-USER is the chain Docker runs first and never flushes. iptables takes
# one -i per rule, so each interface has a line of its own. ufw restores
# after.rules before it creates its user chains, so the block declares its own.
docker_guard_block() {
	local user_forward=$1
	cat <<EOF_BLOCK
# BEGIN vps-setup docker guard
*filter
:$user_forward - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -i lo -j RETURN
-A DOCKER-USER -i tailscale0 -j RETURN
-A DOCKER-USER -i docker0 -j RETURN
-A DOCKER-USER -i br-+ -j RETURN
-A DOCKER-USER -i docker_gwbridge -j RETURN
-A DOCKER-USER -j $user_forward
-A DOCKER-USER -m conntrack --ctstate NEW -j DROP
COMMIT
# END vps-setup docker guard
EOF_BLOCK
}

# Takes file and user-forward chain pairs. Writes the ones that changed, and
# reloads ufw once if one did or the guard is not loaded, which is what a run that
# wrote the files but could not restore them leaves. Dies unless it is loaded then.
docker_guard_apply() {
	local file chain changed=0
	while (($#)); do
		file=$1 chain=$2
		shift 2
		docker_guard_check "$file"
		docker_guard_render "$file" "$chain" | cmp -s - "$file" && continue
		docker_guard_write "$file" "$chain"
		changed=1
	done
	if ((changed)) || ! docker_guard_loaded; then
		quiet ufw reload || die "ufw could not reload with the docker guard; check /etc/ufw/after.rules and after6.rules, then run 'ufw reload'"
		docker_guard_loaded ||
			die "the firewall rules did not restore: ufw kept its old rules and the docker guard is not loaded. Root SSH is still open; check /etc/ufw/after.rules and after6.rules, then run 'ufw reload'"
	fi
}

# ufw reports itself active even when it kept its old rules, so ask the chains.
docker_guard_loaded() {
	docker_guard_family_loaded iptables && docker_guard_family_loaded ip6tables
}

docker_guard_family_loaded() {
	"$1" -S DOCKER-USER 2>/dev/null | grep -q -- '--ctstate NEW -j DROP'
}

# Deleting from a lone marker to the end of the file would drop rules that are not ours.
docker_guard_check() {
	local file=$1 begin end
	[[ -f $file ]] || die "$file is missing; the ufw package installs it"
	begin=$(grep -c '^# BEGIN vps-setup docker guard$' "$file" || true)
	end=$(grep -c '^# END vps-setup docker guard$' "$file" || true)
	((begin == end && begin <= 1)) || die "$file has unmatched vps-setup docker guard markers; fix them by hand"
}

# The file without any earlier block, then the block, so a rerun gives the same bytes.
docker_guard_render() {
	sed -e '/^# BEGIN vps-setup docker guard$/,/^# END vps-setup docker guard$/d' -e "\$a\\" "$1"
	docker_guard_block "$2"
}

# Replaces the file whole, so a cut-off run never leaves ufw a half-written one.
docker_guard_write() {
	local file=$1 tmp
	tmp=$(mktemp "$file.XXXXXX")
	docker_guard_render "$file" "$2" >"$tmp"
	chmod --reference="$file" "$tmp"
	chown --reference="$file" "$tmp"
	mv "$tmp" "$file"
}
