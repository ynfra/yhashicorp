datacenter = "dc1"
domain     = "consul"

performance {
	raft_multiplier  = 1
	leave_drain_time = "5s"
	rpc_hold_timeout = "7s"
}

bind_addr            = "192.168.139.209"
advertise_addr       = "192.168.139.209"
advertise_addr_wan   = "192.168.139.209"
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

data_dir  = "/srv/ynfra/yhashicorp/data/consul"
log_level = "INFO"
log_file  = "/srv/ynfra/yhashicorp/logs/consul.log"

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
