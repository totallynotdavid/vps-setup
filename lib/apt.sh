# Stdin is closed and conffile prompts are answered, because the script itself
# arrives on the remote bash's stdin and nothing may wait for a person.
apt_get() {
	quiet env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=600 \
		-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -y -qq "$@" </dev/null
}

# A run cut off mid-install leaves dpkg unfinished, and apt refuses to work until
# it is configured. dpkg --configure -a does not wait for the dpkg lock, so it runs
# only when dpkg --audit, which takes no lock, reports something.
apt_repair() {
	[[ -n $(dpkg --audit 2>/dev/null) ]] || return 0
	quiet env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a dpkg --force-confdef --force-confold --configure -a </dev/null
}
