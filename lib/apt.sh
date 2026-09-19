apt_get() {
	quiet env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=120 -y -qq "$@"
}
