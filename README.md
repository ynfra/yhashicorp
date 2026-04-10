# yhashicorp

Local Consul + Nomad setup via a single script. No systemd, no custom users — agents run in a tmux session.

## Prerequisites

- Linux (amd64 or arm64)
- `sudo` / root for `install` commands
- `tmux` for `start`
- `curl`, `unzip` (installed automatically by `install`)

## Directory layout

```
yhashicorp/
├── hashicorp.sh         # main script
├── conf/
│   ├── consul.hcl       # written by: consul bootstrap
│   └── nomad.hcl        # written by: nomad bootstrap [--consul]
├── files/               # downloaded archives + extracted binaries (.gitignored)
├── data/{consul,nomad}/ # runtime data (.gitignored)
└── logs/                # runtime logs (.gitignored)
```

## Quickstart

```bash
# 1. Install binaries (requires root)
sudo ./hashicorp.sh consul install
sudo ./hashicorp.sh nomad install

# 2. Write configs
./hashicorp.sh consul bootstrap
./hashicorp.sh nomad bootstrap --consul   # wire nomad → consul

# 3. Start both agents in tmux
./hashicorp.sh start
```

## Commands

| Command | Description |
|---|---|
| `consul install` | Download Consul, install to `/usr/local/bin` |
| `consul bootstrap` | Write `conf/consul.hcl` (single-node server) |
| `nomad install` | Download Nomad + CNI plugins |
| `nomad bootstrap` | Write `conf/nomad.hcl` (standalone) |
| `nomad bootstrap --consul` | Write `conf/nomad.hcl` with Consul integration |
| `start` | Launch tmux session `hashicorp` (consul / nomad / adhoc windows) |

## Versions

| Tool | Version |
|---|---|
| Consul | 1.22.6 |
| Nomad | 1.11.3 |
| CNI plugins | v1.9.1 |

## Useful commands (in adhoc window)

```bash
consul members
consul catalog services

nomad node status
nomad status
```

## Stopping

```bash
tmux kill-session -t hashicorp
```
