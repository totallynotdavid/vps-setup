require_root() {
	((EUID == 0)) || die "must run as root"
}
