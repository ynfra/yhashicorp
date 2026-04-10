# yhashicorp — Agent & Developer Guide

## Overview

`yhashicorp` is a self-contained directory for running Consul and Nomad locally on a single machine. It is part of the `ynfra` monorepo alongside:

- `yansible/` — Ansible roles for provisioning servers (includes `consul` and `nomad` roles)
- `yterraform/` — Terraform modules for deploying Nomad jobs
- `ysandbox/` — Docker Compose examples

This directory is the "run it locally right now" alternative to the Ansible approach.

## Key file: `hashicorp.sh`

Single entry point for all operations. Subcommands:

```
hashicorp.sh consul install
hashicorp.sh consul bootstrap

hashicorp.sh nomad install
hashicorp.sh nomad bootstrap [--consul]

hashicorp.sh start
```

## How it works

### install
- Downloads the binary archive to `./files/` (cached — re-run is safe)
- Verifies SHA256 checksum from HashiCorp's release page
- Installs binary to `/usr/local/bin/`
- `nomad install` also installs CNI plugins to `/opt/cni/bin/`

### bootstrap
- Detects the local IP via `ip route get 1.1.1.1`
- Writes an HCL config to `./conf/consul.hcl` or `./conf/nomad.hcl`
- Config uses absolute paths (based on `SCRIPT_DIR`) for `data_dir` and `log_file`
- Safe to re-run — overwrites the config

### start
- Creates a tmux session named `hashicorp` with three windows:
  - `consul` — runs `consul agent -config-file=./conf/consul.hcl`
  - `nomad` — runs `nomad agent -config=./conf/nomad.hcl`
  - `adhoc` — plain shell for ad-hoc commands
- If the session already exists, attaches to it

## Versions (update in `hashicorp.sh` at the top)

| Variable | Value |
|---|---|
| `CONSUL_VERSION` | `1.22.6` |
| `NOMAD_VERSION` | `1.11.3` |
| `CNI_VERSION` | `v1.9.1` |

## Consul config highlights (`conf/consul.hcl`)

- Single-node server (`server=true`, `bootstrap_expect=1`)
- UI enabled at `http://<bind_ip>:8500/ui`
- Consul Connect enabled
- DNS on port 8600, gRPC on 8502
- Data in `./data/consul/`, logs in `./logs/consul.log`

## Nomad config highlights (`conf/nomad.hcl`)

- Combined server + client (single-node dev setup)
- `bootstrap_expect=1`
- Docker plugin (privileged, volumes enabled) + raw_exec plugin
- CNI plugins at `/opt/cni/bin/`
- Data in `./data/nomad/`, logs in `./logs/nomad.log`
- With `--consul`: consul stanza pointing to `localhost:8500` with `server_auto_join=true`
- Without `--consul`: `server_join` with `retry_join=["127.0.0.1"]`

## Conventions

- `#!/bin/bash` with `SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)`
- `set -exo pipefail` inside each subcommand function
- Tab indentation (4-wide)
- `require_root()` guard on install commands
- Files in `data/`, `logs/`, `files/` are gitignored

## Common tasks

**Upgrade versions:** Edit `CONSUL_VERSION`, `NOMAD_VERSION`, `CNI_VERSION` at the top of `hashicorp.sh` and delete the cached files in `./files/` before re-running install.

**Reset data:** Stop the tmux session, delete `./data/consul/` and/or `./data/nomad/`, then run `start` again.

**Add a new subcommand:** Add a `cmd_<tool>_<action>()` function and wire it into the `case` dispatch at the bottom of `hashicorp.sh`.

## Out of scope

- Multi-node clusters → use `yansible/` with the `consul` and `nomad` roles
- Nomad job definitions → see `yterraform/`
- TLS / ACLs → not configured here; this is a local dev setup
