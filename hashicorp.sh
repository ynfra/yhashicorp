#!/bin/bash
SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)

CONSUL_VERSION="1.22.6"
NOMAD_VERSION="1.11.3"
CNI_VERSION="v1.9.1"

HASHICORP_RELEASES="https://releases.hashicorp.com"
CNI_RELEASES="https://github.com/containernetworking/plugins/releases/download"

TERRAFORM_VERSION="1.14.8"

CONSUL_BIN="$SCRIPT_DIR/files/consul"
NOMAD_BIN="$SCRIPT_DIR/files/nomad"
TERRAFORM_BIN="$SCRIPT_DIR/files/terraform"

usage() {
	echo "Usage: $0 <tool> <command> [flags]"
	echo ""
	echo "  Tools:    consul | nomad"
	echo "  Commands: install | bootstrap"
	echo ""
	echo "  $0 install"
	echo "  $0 consul install [--global]"
	echo "  $0 consul bootstrap"
	echo "  $0 nomad install [--global]"
	echo "  $0 nomad bootstrap [--consul]"
	echo "  $0 terraform install [--global]"
	echo "  $0 docker install"
	echo "  $0 start"
	echo "  $0 stop"
	echo "  $0 validate"
	exit 1
}

require_root() {
	if [[ "$EUID" -ne 0 ]]; then
		echo "error: this command must be run as root" >&2
		exit 1
	fi
}

detect_arch() {
	local machine
	machine=$(uname -m)
	case "$machine" in
		x86_64)  echo "amd64" ;;
		aarch64) echo "arm64" ;;
		arm64)   echo "arm64" ;;
		*)
			echo "error: unsupported architecture: $machine" >&2
			exit 1
			;;
	esac
}

detect_ip() {
	ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}'
}

detect_iface() {
	ip route 2>/dev/null | awk '/^default/{print $5; exit}'
}

# ── install (system deps) ─────────────────────────────────────────────────────

cmd_install() {
	set -exo pipefail
	require_root
	apt-get install -y tmux curl unzip jq make
	echo "system dependencies installed"
}

# ── consul install ────────────────────────────────────────────────────────────

cmd_consul_install() {
	local global=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--global) global=true; shift ;;
			*) echo "error: unknown flag: $1" >&2; exit 1 ;;
		esac
	done

	set -exo pipefail
	require_root

	local arch
	arch=$(detect_arch)

	apt-get install -y unzip curl

	local files_dir="$SCRIPT_DIR/files"
	mkdir -p "$files_dir"

	local zip_file="consul_${CONSUL_VERSION}_linux_${arch}.zip"
	local sums_file="consul_${CONSUL_VERSION}_SHA256SUMS"
	local base_url="$HASHICORP_RELEASES/consul/${CONSUL_VERSION}"

	if [[ ! -f "$files_dir/$zip_file" ]]; then
		curl -fSL -o "$files_dir/$zip_file" "$base_url/$zip_file"
	fi
	if [[ ! -f "$files_dir/$sums_file" ]]; then
		curl -fSL -o "$files_dir/$sums_file" "$base_url/$sums_file"
	fi

	(cd "$files_dir" && grep "$zip_file" "$sums_file" | sha256sum --check)

	unzip -o "$files_dir/$zip_file" -d "$files_dir/"
	chmod +x "$files_dir/consul"

	if [[ "$global" == true ]]; then
		install -m 0755 "$files_dir/consul" /usr/local/bin/consul
		echo "consul $($CONSUL_BIN version | head -1) installed to $CONSUL_BIN and /usr/local/bin/consul"
	else
		echo "consul $($CONSUL_BIN version | head -1) installed to $CONSUL_BIN"
	fi
}

# ── consul bootstrap ──────────────────────────────────────────────────────────

cmd_consul_bootstrap() {
	set -exo pipefail

	local bind_ip
	bind_ip=$(detect_ip)
	if [[ -z "$bind_ip" ]]; then
		echo "error: could not detect local IP address" >&2
		exit 1
	fi

	mkdir -p "$SCRIPT_DIR/conf" "$SCRIPT_DIR/data/consul" "$SCRIPT_DIR/logs"

	cat > "$SCRIPT_DIR/conf/consul.hcl" <<EOF
datacenter = "dc1"
domain     = "consul"

performance {
	raft_multiplier  = 1
	leave_drain_time = "5s"
	rpc_hold_timeout = "7s"
}

bind_addr            = "$bind_ip"
advertise_addr       = "$bind_ip"
advertise_addr_wan   = "$bind_ip"
client_addr          = "0.0.0.0"

addresses {
	dns   = "0.0.0.0"
	http  = "0.0.0.0"
	https = "0.0.0.0"
	grpc  = "0.0.0.0"
}

ports {
	dns      = 8600
	http     = 8500
	https    = -1
	serf_lan = 8301
	serf_wan = 8302
	server   = 8300
	grpc     = 8502
}

recursors = ["1.1.1.1", "8.8.8.8", "8.8.4.4"]

raft_protocol = 3

data_dir  = "$SCRIPT_DIR/data/consul"
log_level = "INFO"
log_file  = "$SCRIPT_DIR/logs/consul.log"

log_rotate_bytes     = 10000000
log_rotate_duration  = "24h"
log_rotate_max_files = 100

disable_update_check        = false
enable_script_checks        = false
disable_remote_exec         = true
enable_local_script_checks  = false

limits {
	http_max_conns_per_client = 200
	https_handshake_timeout   = "5s"
	rpc_handshake_timeout     = "5s"
	rpc_max_conns_per_client  = 100
	rpc_rate                  = -1
	rpc_max_burst             = 1000
}

ui_config {
	enabled = true
}

retry_interval = "30s"
retry_max      = 0

connect {
	enabled = true
}

telemetry {
	prometheus_retention_time = "24h"
}

server            = true
bootstrap         = true
bootstrap_expect  = 1
EOF

	echo "consul config written to $SCRIPT_DIR/conf/consul.hcl"
}

# ── nomad install ─────────────────────────────────────────────────────────────

cmd_nomad_install() {
	local global=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--global) global=true; shift ;;
			*) echo "error: unknown flag: $1" >&2; exit 1 ;;
		esac
	done

	set -exo pipefail
	require_root

	local arch
	arch=$(detect_arch)

	apt-get install -y unzip curl

	local files_dir="$SCRIPT_DIR/files"
	mkdir -p "$files_dir"

	# Nomad binary
	local zip_file="nomad_${NOMAD_VERSION}_linux_${arch}.zip"
	local sums_file="nomad_${NOMAD_VERSION}_SHA256SUMS"
	local base_url="$HASHICORP_RELEASES/nomad/${NOMAD_VERSION}"

	if [[ ! -f "$files_dir/$zip_file" ]]; then
		curl -fSL -o "$files_dir/$zip_file" "$base_url/$zip_file"
	fi
	if [[ ! -f "$files_dir/$sums_file" ]]; then
		curl -fSL -o "$files_dir/$sums_file" "$base_url/$sums_file"
	fi

	(cd "$files_dir" && grep "$zip_file" "$sums_file" | sha256sum --check)

	unzip -o "$files_dir/$zip_file" -d "$files_dir/"
	chmod +x "$files_dir/nomad"

	if [[ "$global" == true ]]; then
		install -m 0755 "$files_dir/nomad" /usr/local/bin/nomad
		echo "nomad $($NOMAD_BIN version | head -1) installed to $NOMAD_BIN and /usr/local/bin/nomad"
	else
		echo "nomad $($NOMAD_BIN version | head -1) installed to $NOMAD_BIN"
	fi

	# CNI plugins
	local cni_tarball="cni-plugins-linux-${arch}-${CNI_VERSION}.tgz"
	local cni_url="$CNI_RELEASES/${CNI_VERSION}/$cni_tarball"

	if [[ ! -f "$files_dir/$cni_tarball" ]]; then
		curl -fSL -o "$files_dir/$cni_tarball" "$cni_url"
	fi

	mkdir -p /opt/cni/bin /opt/cni/config
	tar -xzf "$files_dir/$cni_tarball" -C /opt/cni/bin/

	echo "CNI plugins ${CNI_VERSION} installed to /opt/cni/bin/"
}

# ── terraform install ─────────────────────────────────────────────────────────

cmd_terraform_install() {
	local global=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--global) global=true; shift ;;
			*) echo "error: unknown flag: $1" >&2; exit 1 ;;
		esac
	done

	set -exo pipefail
	require_root

	local arch
	arch=$(detect_arch)

	apt-get install -y unzip curl

	local files_dir="$SCRIPT_DIR/files"
	mkdir -p "$files_dir"

	local zip_file="terraform_${TERRAFORM_VERSION}_linux_${arch}.zip"
	local sums_file="terraform_${TERRAFORM_VERSION}_SHA256SUMS"
	local base_url="$HASHICORP_RELEASES/terraform/${TERRAFORM_VERSION}"

	if [[ ! -f "$files_dir/$zip_file" ]]; then
		curl -fSL -o "$files_dir/$zip_file" "$base_url/$zip_file"
	fi
	if [[ ! -f "$files_dir/$sums_file" ]]; then
		curl -fSL -o "$files_dir/$sums_file" "$base_url/$sums_file"
	fi

	(cd "$files_dir" && grep "$zip_file" "$sums_file" | sha256sum --check)

	unzip -o "$files_dir/$zip_file" -d "$files_dir/"
	chmod +x "$files_dir/terraform"

	if [[ "$global" == true ]]; then
		install -m 0755 "$files_dir/terraform" /usr/local/bin/terraform
		echo "terraform $($TERRAFORM_BIN version | head -1) installed to $TERRAFORM_BIN and /usr/local/bin/terraform"
	else
		echo "terraform $($TERRAFORM_BIN version | head -1) installed to $TERRAFORM_BIN"
	fi
}

# ── docker install ───────────────────────────────────────────────────────────

cmd_docker_install() {
	set -exo pipefail
	require_root

	local files_dir="$SCRIPT_DIR/files"
	mkdir -p "$files_dir"

	local installer="$files_dir/install-docker.sh"
	if [[ ! -f "$installer" ]]; then
		curl -fsSL https://get.docker.com -o "$installer"
	fi

	sh "$installer"
	echo "docker $(docker --version) installed"
}

# ── nomad bootstrap ───────────────────────────────────────────────────────────

cmd_nomad_bootstrap() {
	set -exo pipefail

	local use_consul=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--consul) use_consul=true; shift ;;
			*) echo "error: unknown flag: $1" >&2; exit 1 ;;
		esac
	done

	local iface
	iface=$(detect_iface)
	local advertise_ip
	advertise_ip=$(detect_ip)

	if [[ -z "$advertise_ip" ]]; then
		echo "error: could not detect local IP address" >&2
		exit 1
	fi

	mkdir -p "$SCRIPT_DIR/conf" "$SCRIPT_DIR/data/nomad" "$SCRIPT_DIR/logs"

	# Build optional consul stanza
	local consul_block=""
	if [[ "$use_consul" == true ]]; then
		consul_block=$(cat <<'CONSUL'

consul {
	address              = "localhost:8500"
	ssl                  = false
	ca_file              = ""
	cert_file            = ""
	key_file             = ""
	token                = ""
	server_service_name  = "nomad-servers"
	client_service_name  = "nomad-clients"
	tags                 = []
	auto_advertise       = true
	server_auto_join     = true
	client_auto_join     = true
}
CONSUL
)
	fi

	# Build optional server_join stanza (only when not using consul)
	local server_join_block=""
	if [[ "$use_consul" == false ]]; then
		server_join_block=$(cat <<EOF

server_join {
	retry_join     = ["127.0.0.1"]
	retry_max      = 3
	retry_interval = "15s"
}
EOF
)
	fi

	cat > "$SCRIPT_DIR/conf/nomad.hcl" <<EOF
name       = "$(hostname -s)"
region     = "global"
datacenter = "dc1"

enable_debug        = false
disable_update_check = false

bind_addr = "0.0.0.0"

advertise {
	http = "$advertise_ip:4646"
	rpc  = "$advertise_ip:4647"
	serf = "$advertise_ip:4648"
}

ports {
	http = 4646
	rpc  = 4647
	serf = 4648
}
$consul_block
data_dir = "$SCRIPT_DIR/data/nomad"

log_level       = "INFO"
enable_syslog   = false
log_file        = "$SCRIPT_DIR/logs/nomad.log"
log_rotate_bytes     = 10000000
log_rotate_duration  = "24h"
log_rotate_max_files = 100

leave_on_terminate = true
leave_on_interrupt = false

ui {
	enabled = true
}

limits {
	https_handshake_timeout    = "5s"
	http_max_conns_per_client  = "500"
	rpc_max_conns_per_client   = "500"
	rpc_handshake_timeout      = "5s"
}

server {
	enabled          = true
	bootstrap_expect = 1

	rejoin_after_leave        = false
	node_gc_threshold         = "24h"
	eval_gc_threshold         = "1h"
	job_gc_threshold          = "4h"
	deployment_gc_threshold   = "1h"
	raft_protocol             = 3

	default_scheduler_config {
		scheduler_algorithm              = "spread"
		memory_oversubscription_enabled  = true
		reject_job_registration          = false
		pause_eval_broker                = false

		preemption_config {
			batch_scheduler_enabled    = true
			system_scheduler_enabled   = true
			service_scheduler_enabled  = true
			sysbatch_scheduler_enabled = true
		}
	}
}
$server_join_block
client {
	enabled           = true
	network_interface = "${iface:-lo}"
	max_kill_timeout  = "30s"

	gc_interval            = "1m"
	gc_max_allocs          = 50
	gc_disk_usage_threshold = 80
	gc_inode_usage_threshold = 70
	gc_parallel_destroys   = 2

	cni_path       = "/opt/cni/bin"
	cni_config_dir = "/opt/cni/config"
}

telemetry {
	publish_allocation_metrics = true
	publish_node_metrics       = true
	prometheus_metrics         = true
}

plugin "raw_exec" {
	config {
		enabled = true
	}
}

plugin "docker" {
	config {
		endpoint        = "unix:///var/run/docker.sock"
		allow_privileged = true

		auth {}

		extra_labels = ["job_name", "job_id", "task_group_name", "task_name", "namespace", "node_name", "node_id"]

		volumes {
			enabled = true
		}
	}
}
EOF

	echo "nomad config written to $SCRIPT_DIR/conf/nomad.hcl"
	if [[ "$use_consul" == true ]]; then
		echo "consul integration enabled (localhost:8500)"
	fi
}

# ── validate ─────────────────────────────────────────────────────────────────

cmd_validate() {
	local ok=true
	check() {
		local label="$1"; shift
		if "$@" &>/dev/null; then
			echo "  [OK]  $label"
		else
			echo "  [!!]  $label"
			ok=false
		fi
	}
	check_file() {
		local label="$1"
		local path="$2"
		if [[ -f "$path" ]]; then
			echo "  [OK]  $label: $path"
		else
			echo "  [!!]  $label: $path (missing)"
			ok=false
		fi
	}
	check_dir() {
		local label="$1"
		local path="$2"
		if [[ -d "$path" ]]; then
			echo "  [OK]  $label: $path"
		else
			echo "  [!!]  $label: $path (missing)"
			ok=false
		fi
	}

	echo "── binaries ────────────────────────────────────────────"
	check_file   "consul binary"    "$CONSUL_BIN"
	check_file   "nomad binary"     "$NOMAD_BIN"
	check_file   "terraform binary" "$TERRAFORM_BIN"
	check        "consul version"   "$CONSUL_BIN" version
	check        "nomad version"    "$NOMAD_BIN" version
	check        "terraform version" "$TERRAFORM_BIN" version
	check        "docker"           command -v docker
	check        "tmux"             command -v tmux
	check_file   "CNI bridge"       /opt/cni/bin/bridge
	check_file   "CNI loopback"     /opt/cni/bin/loopback

	echo "── configs ─────────────────────────────────────────────"
	check_file   "consul.hcl"       "$SCRIPT_DIR/conf/consul.hcl"
	check_file   "nomad.hcl"        "$SCRIPT_DIR/conf/nomad.hcl"

	echo "── directories ─────────────────────────────────────────"
	check_dir    "consul data dir"  "$SCRIPT_DIR/data/consul"
	check_dir    "nomad data dir"   "$SCRIPT_DIR/data/nomad"
	check_dir    "logs dir"         "$SCRIPT_DIR/logs"
	check_dir    "files dir"        "$SCRIPT_DIR/files"
	check_dir    "CNI bin dir"      /opt/cni/bin

	echo "── downloaded archives ──────────────────────────────────"
	check_file   "consul zip"       "$SCRIPT_DIR/files/consul_${CONSUL_VERSION}_linux_$(detect_arch).zip"
	check_file   "nomad zip"        "$SCRIPT_DIR/files/nomad_${NOMAD_VERSION}_linux_$(detect_arch).zip"
	check_file   "terraform zip"    "$SCRIPT_DIR/files/terraform_${TERRAFORM_VERSION}_linux_$(detect_arch).zip"
	check_file   "CNI tarball"      "$SCRIPT_DIR/files/cni-plugins-linux-$(detect_arch)-${CNI_VERSION}.tgz"
	check_file   "docker installer" "$SCRIPT_DIR/files/install-docker.sh"

	echo "── runtime ─────────────────────────────────────────────"
	if tmux has-session -t hashicorp 2>/dev/null; then
		echo "  [OK]  tmux session 'hashicorp' is running"
	else
		echo "  [--]  tmux session 'hashicorp' not running (run: $0 start)"
	fi
	if "$CONSUL_BIN" members &>/dev/null; then
		echo "  [OK]  consul agent reachable"
	else
		echo "  [--]  consul agent not reachable"
	fi
	if "$NOMAD_BIN" node status &>/dev/null; then
		echo "  [OK]  nomad agent reachable"
	else
		echo "  [--]  nomad agent not reachable"
	fi

	echo "────────────────────────────────────────────────────────"
	if [[ "$ok" == true ]]; then
		echo "  all checks passed"
	else
		echo "  some checks failed — see [!!] above"
		return 1
	fi
}

# ── start (tmux) ──────────────────────────────────────────────────────────────

cmd_start() {
	if ! command -v tmux &>/dev/null; then
		echo "error: tmux is not installed" >&2
		exit 1
	fi

	local session="hashicorp"

	if tmux has-session -t "$session" 2>/dev/null; then
		echo "session '$session' already exists — stopping it first"
		cmd_stop
	fi

	# Single window: top row = consul (left) | nomad (right), bottom row = panel
	tmux new-session -d -s "$session" -n "main"

	# Split top/bottom first (pane 0 = top, pane 1 = bottom panel)
	tmux split-window -v -t "$session:main" -p 30

	# Split top pane horizontally: consul (left) | nomad (right)
	tmux split-window -h -t "$session:main.0"

	# Start consul in top-left (pane 0)
	tmux send-keys -t "$session:main.0" \
		"$CONSUL_BIN agent -config-file=$SCRIPT_DIR/conf/consul.hcl" Enter

	# Start nomad in top-right (pane 1)
	tmux send-keys -t "$session:main.1" \
		"$NOMAD_BIN agent -config=$SCRIPT_DIR/conf/nomad.hcl" Enter

	# Focus bottom panel (pane 2)
	tmux select-pane -t "$session:main.2"

	echo "tmux session '$session' started"
	tmux attach-session -t "$session"
}

# ── stop ─────────────────────────────────────────────────────────────────────

cmd_stop() {
	local session="hashicorp"

	# Send leave signals to agents before killing the session
	if "$CONSUL_BIN" members &>/dev/null; then
		echo "stopping consul..."
		"$CONSUL_BIN" leave || true
	fi
	if "$NOMAD_BIN" node status &>/dev/null; then
		echo "stopping nomad..."
		pkill -SIGINT -f "files/nomad agent" || true
		sleep 2
	fi

	if tmux has-session -t "$session" 2>/dev/null; then
		tmux kill-session -t "$session"
		echo "tmux session '$session' killed"
	else
		echo "tmux session '$session' not running"
	fi
}

# ── dispatch ──────────────────────────────────────────────────────────────────

TOOL="${1:-}"
CMD="${2:-}"

case "$TOOL" in
	consul)
		shift 2 || true
		case "$CMD" in
			install)   cmd_consul_install "$@" ;;
			bootstrap) cmd_consul_bootstrap ;;
			*) usage ;;
		esac
		;;
	nomad)
		shift 2 || true
		case "$CMD" in
			install)   cmd_nomad_install "$@" ;;
			bootstrap) cmd_nomad_bootstrap "$@" ;;
			*) usage ;;
		esac
		;;
	terraform)
		shift 2 || true
		case "$CMD" in
			install) cmd_terraform_install "$@" ;;
			*) usage ;;
		esac
		;;
	docker)
		shift 2 || true
		case "$CMD" in
			install) cmd_docker_install ;;
			*) usage ;;
		esac
		;;
	start)
		cmd_start
		;;
	validate)
		cmd_validate
		;;
	stop)
		cmd_stop
		;;
	install)
		cmd_install
		;;
	*)
		usage
		;;
esac
