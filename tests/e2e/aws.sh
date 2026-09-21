#!/usr/bin/env bash
# End-to-end harness on AWS EC2: creates a fresh Ubuntu server that starts the
# way a Contabo one does (root login with a password over SSH), runs a scenario
# against it and destroys it.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source-path=SCRIPTDIR/../..
source "$repo/lib/os.sh"
self=$repo/tests/e2e/aws.sh
tf_dir=$repo/tests/e2e/aws
region=${AWS_REGION:-us-east-1}
ubuntu_version=${UBUNTU_VERSION:-26.04}
TS_TAGS=${TS_TAGS:-tag:vps-test}
max_age=$((2 * 3600))
export TS_TAGS
export TS_EPHEMERAL=1
export TF_VAR_region=$region

print_usage() {
	cat <<'EOF_USAGE'
usage: aws.sh up | run | refuse | down | sweep | all | releases

  up        create the server and wait until root and its password work; prints its public IP
  run       tests/e2e/run.sh against that server
  refuse    tests/e2e/refuse-close.sh against that server
  down      destroy the server; safe to repeat
  sweep     terminate leftovers older than two hours, in case a run crashed
  all       for run and refuse: up, scenario, down; always destroys
  releases  all once per supported Ubuntu release; one result line each, exits 1 if any failed

environment:
  AWS_PROFILE        or AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY; for every command
  TS_TEST_KEY_FILE   file holding an OAuth client secret or an auth key; for run, refuse and all
  ADMIN_USER         admin account to create (default: admin)
  TS_TAGS            tags of the key or client (default: tag:vps-test)
  AWS_REGION         region (default: us-east-1)
  UBUNTU_VERSION     Ubuntu release of the server, for example 24.04 (default: 26.04)
EOF_USAGE
}

usage() {
	print_usage >&2
	exit 2
}

log() {
	printf '==> %s\n' "$*" >&2
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

tf() {
	terraform -chdir="$tf_dir" "$@"
}

# Every input is checked before the first AWS call, and all the missing ones are named together.
require_inputs() {
	local needs_key=$1 problems=() credentials_error
	local tool
	for tool in terraform aws curl; do
		command -v "$tool" >/dev/null || problems+=("$tool is not on PATH; mise install provides terraform and aws")
	done
	if ((needs_key)); then
		if [[ -z ${TS_TEST_KEY_FILE:-} ]]; then
			problems+=("TS_TEST_KEY_FILE is not set; set it to a file holding an OAuth client secret, or a reusable, ephemeral auth key, for $TS_TAGS")
		elif [[ ! -f $TS_TEST_KEY_FILE || ! -r $TS_TEST_KEY_FILE ]]; then
			problems+=("TS_TEST_KEY_FILE='$TS_TEST_KEY_FILE' is not a readable file")
		fi
	fi
	if ((${#problems[@]})); then
		printf 'error: %s\n' "${problems[@]}" >&2
		exit 2
	fi
	if ! credentials_error=$(aws sts get-caller-identity --region "$region" --output text 2>&1 >/dev/null); then
		printf 'error: no usable AWS credentials: set AWS_PROFILE, or AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, so that aws sts get-caller-identity succeeds\n%s\n' "$credentials_error" >&2
		exit 2
	fi
}

operator_cidr() {
	local ip
	ip=$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]') ||
		die "could not learn this machine's public IP from checkip.amazonaws.com"
	[[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "checkip.amazonaws.com returned '$ip', not an IPv4 address"
	printf '%s/32\n' "$ip"
}

new_run_id() {
	od -An -N4 -tx1 /dev/urandom | tr -d ' \n'
}

server_output() {
	tf output -raw "$1" 2>/dev/null || die "there is no server; run '$0 up' first"
}

# The password reaches OpenSSH only through the environment of the command it starts.
# Callers may run this under || or if, where errexit is off, so failures exit explicitly.
with_root_password() (
	dir=$(mktemp -d) || exit 1
	trap 'rm -rf "$dir"' EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	cat >"$dir/askpass" <<'EOF_ASKPASS'
#!/bin/sh
printf '%s\n' "$E2E_ROOT_PASSWORD"
EOF_ASKPASS
	chmod 700 "$dir/askpass"
	E2E_ROOT_PASSWORD=$(server_output root_password) || exit 1
	export E2E_ROOT_PASSWORD SSH_ASKPASS=$dir/askpass SSH_ASKPASS_REQUIRE=force
	"$@"
)

wait_until_ready() {
	local ip=$1 deadline=$((SECONDS + 300)) output status
	log "wait for root and its password over SSH, and for cloud-init"
	while ((SECONDS < deadline)); do
		status=0
		output=$(with_root_password timeout "$((deadline - SECONDS))" ssh -n \
			-o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -o ConnectTimeout=5 \
			-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
			"root@$ip" 'cloud-init status --wait' 2>&1) || status=$?
		case $status in
		# 2 is cloud-init finished with recoverable errors; the login already worked.
		0 | 2)
			log "cloud-init: ${output//$'\n'/ }"
			return 0
			;;
		255) sleep 5 ;;
		124) break ;;
		*) die "cloud-init failed on $ip (exit $status): $output" ;;
		esac
	done
	die "root and its password did not work on $ip within five minutes${output:+; last output: $output}"
}

cmd_up() {
	local run_id cidr ip
	cidr=$(operator_cidr)
	tf init -input=false >&2
	if [[ -n $(tf state list 2>/dev/null) ]]; then
		die "a server from an earlier run still exists; run '$0 down' first"
	fi
	run_id=$(new_run_id)
	log "create run $run_id, SSH open to $cidr only"
	tf apply -input=false -auto-approve -var "run_id=$run_id" -var "ssh_source_cidr=$cidr" \
		-var "ubuntu_version=$ubuntu_version" >&2
	ip=$(server_output public_ip)
	wait_until_ready "$ip"
	printf '%s\n' "$ip"
}

cmd_run() {
	local ip run_id
	ip=$(server_output public_ip)
	run_id=$(server_output run_id)
	with_root_password "$repo/tests/e2e/run.sh" "root@$ip" "e2e-$run_id" --key "$TS_TEST_KEY_FILE"
}

cmd_refuse() {
	local ip run_id
	ip=$(server_output public_ip)
	run_id=$(server_output run_id)
	with_root_password "$repo/tests/e2e/refuse-close.sh" "root@$ip" "e2e-$run_id" --key "$TS_TEST_KEY_FILE"
}

# Destroying only reads the state, so the two required variables take placeholders.
# The release is passed too, because Terraform validates it and reads its image on destroy.
cmd_down() {
	log "destroy"
	tf init -input=false >&2
	tf destroy -input=false -auto-approve -var run_id=destroy -var ssh_source_cidr=192.0.2.1/32 \
		-var "ubuntu_version=$ubuntu_version" >&2
}

older_than_max_age() {
	local stamp=$1 seconds
	# No readable time means the resource is not ours to trust, so it counts as old.
	seconds=$(date -u -d "$stamp" +%s 2>/dev/null) || return 0
	((seconds < $(date -u +%s) - max_age))
}

sweep_instances() {
	local id launched rows stale=()
	rows=$(aws ec2 describe-instances --region "$region" \
		--filters Name=tag:purpose,Values=vps-setup-e2e Name=instance-state-name,Values=pending,running,stopping,stopped \
		--query 'Reservations[].Instances[].[InstanceId,LaunchTime]' --output text)
	while read -r id launched; do
		[[ -n $id ]] || continue
		if older_than_max_age "$launched"; then
			stale+=("$id")
		fi
	done <<<"$rows"
	((${#stale[@]})) || return 0
	log "terminate ${stale[*]}"
	aws ec2 terminate-instances --region "$region" --instance-ids "${stale[@]}" >/dev/null
	aws ec2 wait instance-terminated --region "$region" --instance-ids "${stale[@]}"
}

sweep_security_groups() {
	local id created rows failed=0
	rows=$(aws ec2 describe-security-groups --region "$region" \
		--filters Name=tag:purpose,Values=vps-setup-e2e \
		--query "SecurityGroups[].[GroupId,Tags[?Key=='created_at'].Value|[0]]" --output text)
	while read -r id created; do
		[[ -n $id ]] || continue
		older_than_max_age "$created" || continue
		log "delete security group $id"
		for _ in 1 2 3 4 5 6; do
			if aws ec2 delete-security-group --region "$region" --group-id "$id" 2>/dev/null; then
				continue 2
			fi
			sleep 5
		done
		printf 'error: could not delete security group %s; something still uses it\n' "$id" >&2
		failed=1
	done <<<"$rows"
	((failed == 0))
}

cmd_sweep() {
	log "sweep $region: instances and security groups tagged purpose=vps-setup-e2e older than two hours"
	sweep_instances
	sweep_security_groups
}

server_may_exist=0

teardown_on_exit() {
	local status=$?
	if ((server_may_exist)); then
		log "tear down"
		"$self" down || status=1
	fi
	exit "$status"
}

cmd_all() {
	local scenario ip failed=()
	trap teardown_on_exit EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	for scenario in run refuse; do
		log "scenario $scenario"
		server_may_exist=1
		if ip=$("$self" up) && log "server at $ip" && "$self" "$scenario"; then
			log "scenario $scenario passed"
		else
			log "scenario $scenario FAILED"
			failed+=("$scenario")
		fi
		if "$self" down; then
			server_may_exist=0
		fi
	done
	((${#failed[@]} == 0)) || die "failed: ${failed[*]}"
}

cmd_releases() {
	local supported release failed=()
	local -a releases
	trap 'exit 130' INT
	trap 'exit 143' TERM
	mapfile -t releases < <(supported_os)
	for supported in "${releases[@]}"; do
		release=${supported#* }
		log "release $release"
		if UBUNTU_VERSION=$release "$self" all; then
			printf 'release %s: passed\n' "$release"
		else
			printf 'release %s: FAILED\n' "$release"
			failed+=("$release")
		fi
	done
	((${#failed[@]} == 0)) || die "failed: ${failed[*]}"
}

(($# == 1)) || usage
case $1 in
-h | --help)
	print_usage
	exit 0
	;;
up | down | sweep)
	require_inputs 0
	;;
run | refuse | all | releases)
	require_inputs 1
	;;
*) usage ;;
esac
"cmd_$1"
