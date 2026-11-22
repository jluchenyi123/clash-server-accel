# Clash Server Accelerator

**English** | [简体中文](README.zh-CN.md)

Manage Clash / mihomo subscriptions on a headless Linux server and run any
command through the proxy.

Two commands do most of the work:

- **`clash`** — subscription manager: add, update and switch profiles, test
  nodes, control the service, and enable system-wide TUN mode.
- **`accel`** — command accelerator: run a single command through the proxy
  without changing the rest of your shell.

No desktop environment is required. Designed for SSH-managed servers,
homelabs and remote development boxes.

![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20systemd-blue)
![Python](https://img.shields.io/badge/python-3.8%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> Group names, node names and subscription content belong to your provider
> and are not part of this repository.

## Features

- Paste a subscription URL to download, validate, activate and restart the
  service in one step
- Multiple subscription profiles with a small metadata store
- Node latency tests and interactive node / group selection
- Two runtime modes:
  - **HTTP proxy** — per-shell via `proxy_on`, or per-command via `accel`
  - **TUN mode** — system-wide, with automatic DNS takeover and rollback
- Configs are validated with `mihomo -t` before they replace the live config
- LAN and Tailscale traffic stay direct in TUN mode
- Optional web dashboard (Clash Dashboard / yacd / Metacubexd)
- Import subscriptions from Clash Verge
- No GUI, no Electron, no desktop session required

## How it works

```text
 subscription URL
        │   clash add / clash update
        │   (curl, provider-friendly User-Agent, proxy fallback)
        ▼
 ~/.config/mihomo/profiles/<slug>.yaml      raw Clash YAML, mode 600
        │
        │   build_runtime(): force ports / DNS / rules,
        │   validate with mihomo -t
        ▼
 config.yaml  (HTTP mode)   config-tun.yaml  (TUN mode)
        │
        ▼
 mihomo (systemd)
        ├── 127.0.0.1:7899   mixed HTTP + SOCKS5 proxy
        └── 127.0.0.1:9090   controller / REST API / optional UI
```

The generated runtime configs are **derived artifacts**. Do not edit
`config.yaml` or `config-tun.yaml` by hand — they are rebuilt from the active
profile whenever you run `clash use`, `clash update` or `clash tun on`.

## Requirements

- Linux with systemd (Ubuntu / Debian and similar)
- [mihomo](https://github.com/MetaCubeX/mihomo) (Clash.Meta core)
- Python 3.8+ with PyYAML
- `curl`
- For TUN mode: root, `/dev/net/tun`, systemd-resolved and NetworkManager

### Install mihomo

Download the binary for your architecture from
[MetaCubeX/mihomo Releases](https://github.com/MetaCubeX/mihomo/releases):

```bash
sudo install -m 755 mihomo /usr/local/bin/mihomo
mihomo -v
```

> If mihomo is installed elsewhere, update `ExecStart` in `mihomo.service`,
> or set `MIHOMO_BIN=/path/to/mihomo` for `clash`.

### Install PyYAML

```bash
sudo apt install python3-yaml
```

## Installation

```bash
git clone https://github.com/jluchenyi123/clash-server-accel.git
cd clash-server-accel
./install.sh
```

`install.sh` is a per-user installer (do not run it with sudo). It installs:

- `clash` and `accel` into `~/.local/bin`
- helper commands `clash-menu` and `clash-status` for desktop launchers
- the systemd user service `~/.config/systemd/user/mihomo.service`
- the TUN installer into `~/.config/mihomo/install-tun.sh`
- a desktop launcher in the XDG desktop directory, when one exists
- `proxy_on` / `proxy_off` / `proxy_status` shell functions in `~/.bashrc`

If `~/.local/bin` is not in your `PATH`, log in again or run:

```bash
source ~/.bashrc
```

### GeoIP data

Before the first config is generated, place `Country.mmdb`, `geoip.dat` and
`geosite.dat` in `~/.config/mihomo/`. `ASN.mmdb` is optional.

If Clash Verge is installed, `clash` copies these files from its data
directory automatically. Otherwise download them from
[MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat/releases).

## Quick start

```bash
clash
```

Choose `1` in the menu and paste a subscription URL. Or:

```bash
clash add "https://your-subscription-url"
```

After a profile is active, use the proxy in the current shell:

```bash
proxy_on          # enable proxy variables
proxy_status      # show status
proxy_off         # disable
```

Or accelerate a single command without touching the shell:

```bash
accel git clone https://github.com/owner/repo.git
accel npx skills add owner/repo --list
accel pip install -r requirements.txt
accel status
```

## Command reference

### clash

| Command | Description |
|---|---|
| `clash` | Interactive menu |
| `clash add "<url>"` | Add a subscription, generate configs and activate it |
| `clash add "<url>" --name NAME` | Add with a custom profile name |
| `clash add "<url>" --no-start` | Generate configs without restarting the service |
| `clash list` | List profiles (`*` marks the active one) |
| `clash use <name>` | Switch to a profile |
| `clash update [name]` | Update a subscription (default: active) |
| `clash nodes` | Show nodes and current selections |
| `clash nodes --test` | Test latency and select a node interactively |
| `clash status` | Show service, nodes and connectivity |
| `clash start` / `stop` / `restart` | Manage the service |
| `clash logs [-f]` | Show or follow logs |
| `clash remove <name>` | Remove a profile (not the active one) |
| `clash import-verge [--use NAME]` | Import subscriptions from Clash Verge |
| `clash tun on` / `off` / `status` | System-wide TUN mode |

Clash YAML subscriptions are supported, including base64-wrapped YAML. If a
direct download fails, the tool retries through the local proxy. Plain
ss/vmess/trojan share-link lists are not supported — convert them to a Clash
YAML subscription first.

### accel

| Command | Description |
|---|---|
| `accel <command> [args...]` | Run the command with proxy variables |
| `accel -- <command>` | Same (use when the command name is `status`, etc.) |
| `accel status` | Status, current node, exit IP and location |
| `accel test` | Connectivity test |
| `accel restart` | Restart mihomo |
| `accel help` | Show usage |

For the duration of the command, `accel` sets:

```text
http_proxy / https_proxy / all_proxy
HTTP_PROXY / HTTPS_PROXY / ALL_PROXY
npm_config_proxy / npm_config_https_proxy
no_proxy (LAN, mDNS and Tailscale excluded)
```

It exits with the same status code as the wrapped command. If the service is
not running, `accel` tries to start it first.

### Shell helpers

`install.sh` adds these functions to `~/.bashrc` (if not already present):

- `proxy_on` — enable proxy variables in the current shell
- `proxy_off` — remove proxy variables
- `proxy_status` — show service state and test connectivity

## Ports

Defaults:

- `127.0.0.1:7899` — HTTP + SOCKS5 mixed proxy
- `127.0.0.1:9090` — controller / REST API

To change them:

- edit `MIXED_PORT` / `CTRL_PORT` in `clash`
- set `ACCEL_PORT` / `ACCEL_CTRL_PORT` / `ACCEL_HOST`, or edit `accel`
- update the port in the `proxy_on` block in `~/.bashrc` if you use it

## TUN mode

```bash
clash tun on      # requires sudo
clash tun off     # restore HTTP proxy mode
```

`clash tun on` generates `config-tun.yaml` from the active profile and runs
`install-tun.sh`. The installer:

- creates a TUN interface and takes over system traffic
- points system DNS at mihomo (anti-pollution, fake-IP)
- keeps LAN and Tailscale addresses direct
- validates the config before starting the service
- automatically rolls back if installation fails or is not confirmed within
  5 minutes (protects you if SSH drops)

TUN mode depends on NetworkManager for DNS configuration. It also writes
`/etc/systemd/system/mihomo-tun.service` and changes DNS settings. A rollback
script is stored at `~/.config/mihomo/rollback-tun.sh`.

## File layout

Repository:

```text
clash                          # subscription manager (Python)
accel                          # command accelerator (Bash)
start-menu.sh
check-status.sh
clash-accelerator.desktop.in   # desktop launcher template
mihomo.service                 # systemd user service
install.sh                     # per-user installer
install-tun.sh                 # TUN mode installer
README.md
README.zh-CN.md
LICENSE
.gitignore
```

Runtime files (not committed):

```text
~/.config/mihomo/
├── config.yaml              # active HTTP config (generated)
├── config-tun.yaml          # active TUN config (generated)
├── subscriptions.json       # subscription metadata (contains URLs, mode 600)
├── profiles/                # raw subscription YAML files (mode 600)
├── ui/                      # optional web dashboard
├── Country.mmdb
├── geoip.dat
└── geosite.dat
```

## Web dashboard

The controller listens on localhost only. Open an SSH tunnel from your
computer:

```bash
ssh -L 9090:127.0.0.1:9090 user@server
```

Then open <http://127.0.0.1:9090/ui/>.

If Clash Verge dashboard assets are not available, download
[yacd](https://github.com/haishanh/yacd) or
[Metacubexd](https://github.com/MetaCubeX/metacubexd) into
`~/.config/mihomo/ui/`.

## Uninstall

```bash
clash tun off                       # only if TUN mode is installed
systemctl --user disable --now mihomo
rm -f ~/.local/bin/{clash,accel,clash-menu,clash-status}
rm -f ~/.config/systemd/user/mihomo.service
```

Then remove the block between `# >>> clash-server-accel >>>` and
`# <<< clash-server-accel <<<` from `~/.bashrc`. Your subscriptions and
configs stay in `~/.config/mihomo/` — delete that directory to remove them
as well.

## FAQ

### `clash: command not found`

```bash
source ~/.bashrc
```

### `gnutls_handshake() failed` / GitHub TLS error

Direct connections are being interfered with. Use the accelerator:

```bash
accel git clone https://github.com/owner/repo.git
```

### Subscription download fails

- Make sure the link is a **Clash YAML** subscription, not a list of
  ss/vmess share links
- If direct access fails, the tool retries through the local proxy; the local
  proxy must already be running
- Check logs with `clash logs`

### `loc=CN` or the exit IP is still the local ISP

Traffic is not going through the proxy:

```bash
proxy_on          # current shell
clash status      # service state
clash tun on      # for system-wide traffic
```

### TUN mode breaks connectivity

```bash
clash tun off
# or, if the CLI is unavailable:
sudo bash ~/.config/mihomo/rollback-tun.sh
```

### Nodes are slow

```bash
clash nodes --test
clash nodes
```

### My edits to `config.yaml` disappeared

Expected: `config.yaml` and `config-tun.yaml` are generated. Change the
subscription or the generator in `clash`, then rebuild with `clash use`.

## Security

- `subscriptions.json` and `profiles/` contain subscription URLs and node
  credentials; keep them mode `600`
- The controller listens on `127.0.0.1` only
- `allow-lan` defaults to `false`
- TUN mode writes a system service and changes DNS; review `install-tun.sh`
  before running it
- Do not commit runtime configs to Git (`.gitignore` covers them)
- Before pushing to GitHub, confirm that no personal subscription URL appears
  in any file

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

This project is intended for personal network management and learning.
Follow your local laws and your service provider's terms.
