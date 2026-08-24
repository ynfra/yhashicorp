# ynfra / yhashicorp

Local single-node Consul + Nomad dev stack driven by one script. No systemd,
no custom users — both agents run in a tmux session from binaries in `./files/`.

## Prerequisites

- Linux (amd64 or arm64)
- `sudo` / root for the `install` commands
- `tmux`, `curl`, `unzip`, `jq`, `make` (installed by `sudo ./hashicorp.sh install`)

## Usage

```bash
# 1. Install system deps + binaries (root; downloads are cached in ./files/)
sudo ./hashicorp.sh install
sudo ./hashicorp.sh consul install
sudo ./hashicorp.sh nomad install

# 2. Write configs
./hashicorp.sh consul bootstrap
./hashicorp.sh nomad bootstrap --consul   # wire nomad → consul

# 3. Start both agents in tmux
./hashicorp.sh start
```

Consul UI at `http://<bind_ip>:8500/ui`, Nomad API/UI on port 4646.

## Commands

| Command | Key fact | Description |
|---|---|---|
| `install` | root | apt-get: `tmux curl unzip jq make` |
| `consul install [--global]` | root · Consul 1.22.6 | Download + SHA256-verify to `./files/`; `--global` also copies to `/usr/local/bin` |
| `consul bootstrap` | writes `conf/consul.hcl` | Single-node server, UI on :8500 |
| `nomad install [--global]` | root · Nomad 1.11.3 + CNI v1.9.1 | Binary to `./files/`, CNI plugins to `/opt/cni/` |
| `nomad bootstrap [--consul]` | writes `conf/nomad.hcl` | Combined server + client; `--consul` adds Consul integration |
| `terraform install [--global]` | root · Terraform 1.14.8 | Download + SHA256-verify to `./files/` |
| `docker install` | root | `get.docker.com` install script (cached) |
| `start` | tmux session `hashicorp` | One window: consul pane, nomad pane, ad-hoc shell pane; attaches |
| `stop` | | Graceful `consul leave` + SIGINT to nomad, then kills the session |
| `validate` | | Checks binaries, configs, dirs, archives, and running agents |

## Notes

- Try it in the ad-hoc pane: `consul members`, `consul catalog services`, `nomad node status`, `nomad status`.
- Stop with `./hashicorp.sh stop` (falls back to `tmux kill-session -t hashicorp`).
- Upgrade: bump the version variables at the top of `hashicorp.sh`, delete the cached archives in `./files/`, re-run the installs.
- `data/`, `logs/`, `files/` are gitignored runtime dirs; `conf/` is tracked.
- Local dev only — no TLS/ACLs; multi-node clusters live in `yansible/`, Nomad jobs in `yterraform/`.

See [AGENTS.md](AGENTS.md) for conventions, config internals, and day-2 operations.
