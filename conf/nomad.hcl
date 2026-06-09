name       = "nomad"
region     = "global"
datacenter = "dc1"

enable_debug        = false
disable_update_check = false

bind_addr = "0.0.0.0"

advertise {
	http = "192.168.139.209:4646"
	rpc  = "192.168.139.209:4647"
	serf = "192.168.139.209:4648"
}

ports {
	http = 4646
	rpc  = 4647
	serf = 4648
}

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
data_dir = "/srv/ynfra/yhashicorp/data/nomad"

log_level       = "INFO"
enable_syslog   = false
log_file        = "/srv/ynfra/yhashicorp/logs/nomad.log"
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

client {
	enabled           = true
	network_interface = "eth0"
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
