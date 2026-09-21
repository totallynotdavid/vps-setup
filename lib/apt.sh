# Stdin is closed and conffile prompts are answered, because the script itself
# arrives on the remote bash's stdin and nothing may wait for a person.
apt_get() {
	quiet env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=600 \
		-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -y -qq "$@" </dev/null
}

# A run cut off mid-install leaves dpkg unfinished, and apt refuses to work
# until it is configured. A no-op on a healthy system.
apt_repair() {
	quiet env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a dpkg --force-confdef --force-confold --configure -a </dev/null
}
