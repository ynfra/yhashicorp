# yhashicorp — Agent & Developer Guide

## Overview

`yhashicorp` is a self-contained directory for running Consul and Nomad locally on a single machine. It is part of the `ynfra` monorepo alongside:

- `yansible/` — Ansible roles for provisioning servers (includes `consul` and `nomad` roles)
- `yterraform/` — Terraform modules for deploying Nomad jobs
- `ysandbox/` — Docker Compose examples

This directory is the "run it locally right now" alternative to the Ansible approach.

## Key file: `hashicorp.sh`

Single entry point for all operations. Full subcommand list:

```
hashicorp.sh install                        # apt-get: tmux curl unzip jq make (root)

hashicorp.sh consul install [--global]      # download + SHA256-verify; --global copies to /usr/local/bin
hashicorp.sh consul bootstrap               # write conf/consul.hcl

hashicorp.sh nomad install [--global]       # download + SHA256-verify + CNI plugins; --global copies to /usr/local/bin
hashicorp.sh nomad bootstrap [--consul]     # write conf/nomad.hcl

hashicorp.sh terraform install [--global]   # download + SHA256-verify; --global copies to /usr/local/bin

hashicorp.sh docker install                 # curl https://get.docker.com | sh (cached)

hashicorp.sh start                          # launch tmux session
hashicorp.sh stop                           # graceful shutdown + kill tmux session
hashicorp.sh validate                       # check binaries, configs, dirs, archives, runtime
```

## How it works

### install (system deps)
- `sudo ./hashicorp.sh install`
- Runs `apt-get install -y tmux curl unzip jq make`

### consul/nomad/terraform install
- Downloads zip + SHA256SUMS to `./files/` (cached — skipped if file exists; re-run is safe)
- Verifies SHA256 checksum from HashiCorp's release page
- Extracts binary to `./files/`; `--global` additionally installs to `/usr/local/bin/`
- `nomad install` also downloads and installs CNI plugins to `/opt/cni/bin/` and `/opt/cni/config/`
- All `install` commands require root

### bootstrap
- Detects the local IP via `ip route get 1.1.1.1` (consul) or `ip route` default iface (nomad)
- Writes HCL config to `./conf/consul.hcl` or `./conf/nomad.hcl`
- Config uses absolute paths (based on `SCRIPT_DIR`) for `data_dir` and `log_file`
- Creates `./conf/`, `./data/{consul,nomad}/`, `./logs/` directories
- Safe to re-run — overwrites the config

### start
- If session `hashicorp` exists, stops it first (calls `stop`), then recreates
- Creates one tmux window (`main`) split into 3 panes:
  - top-left (pane 0): `consul agent -config-file=./conf/consul.hcl`
  - top-right (pane 1): `nomad agent -config=./conf/nomad.hcl`
  - bottom (pane 2, 30% height): plain shell for ad-hoc commands, focused on attach
- Attaches to the session after creation

### stop
- Sends `consul leave` if consul is reachable
- Sends `SIGINT` to the nomad process if nomad is reachable, waits 2 s
- Kills the tmux session `hashicorp`

### validate
Checks and prints `[OK]` / `[!!]` / `[--]` for:
- Binaries: `consul`, `nomad`, `terraform` in `./files/`; `docker`, `tmux` in PATH; CNI bridge + loopback
- Configs: `conf/consul.hcl`, `conf/nomad.hcl`
- Directories: `data/consul`, `data/nomad`, `logs`, `files`, `/opt/cni/bin`
- Downloaded archives: zips, tarballs, docker installer script
- Runtime: tmux session alive, consul agent reachable, nomad agent reachable

## Versions (update at the top of `hashicorp.sh`)

| Variable | Value |
|---|---|
| `CONSUL_VERSION` | `1.22.6` |
| `NOMAD_VERSION` | `1.11.3` |
| `CNI_VERSION` | `v1.9.1` |
| `TERRAFORM_VERSION` | `1.14.8` |

## Consul config highlights (`conf/consul.hcl`)

- Single-node server (`server=true`, `bootstrap_expect=1`, `bootstrap=true`)
- UI enabled at `http://<bind_ip>:8500/ui`
- Consul Connect enabled
- DNS on port 8600, HTTP on 8500, gRPC on 8502, HTTPS disabled (-1)
- Recursors: `1.1.1.1`, `8.8.8.8`, `8.8.4.4`
- Log rotation: 10 MB / 24 h / max 100 files
- Data in `./data/consul/`, logs in `./logs/consul.log`

## Nomad config highlights (`conf/nomad.hcl`)

- Combined server + client (single-node dev setup), `bootstrap_expect=1`
- Scheduler: `spread` algorithm, memory oversubscription enabled
- Docker plugin (privileged, volumes enabled) at `unix:///var/run/docker.sock` + raw_exec plugin
- CNI plugins at `/opt/cni/bin/`, config at `/opt/cni/config/`
- Log rotation: 10 MB / 24 h / max 100 files
- Data in `./data/nomad/`, logs in `./logs/nomad.log`
- With `--consul`: consul stanza pointing to `localhost:8500`, `server_auto_join=true`, `client_auto_join=true`
- Without `--consul`: `server_join` with `retry_join=["127.0.0.1"]`, `retry_max=3`, `retry_interval=15s`

## Conventions

- `#!/bin/bash` with `SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)`
- `set -exo pipefail` inside each subcommand function
- Tab indentation (4-wide)
- `require_root()` guard on all `install` commands
- `detect_arch()` maps `uname -m` → `amd64`/`arm64`; fails on unsupported arch
- Files in `data/`, `logs/`, `files/` are gitignored; `conf/` is tracked

## Common tasks

**Upgrade versions:** Edit the version variables at the top of `hashicorp.sh`, delete the cached archives in `./files/`, then re-run the install commands.

**Reset data:** Run `./hashicorp.sh stop`, delete `./data/consul/` and/or `./data/nomad/`, then run `./hashicorp.sh start`.

**Add a new subcommand:** Add a `cmd_<tool>_<action>()` function and wire it into the `case` dispatch at the bottom of `hashicorp.sh`.

## Out of scope

- Multi-node clusters → use `yansible/` with the `consul` and `nomad` roles
- Nomad job definitions → see `yterraform/`
- TLS / ACLs → not configured here; this is a local dev setup
