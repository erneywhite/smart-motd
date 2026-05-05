# smart-motd

A customizable, modular **MOTD** (message of the day) for Linux servers — the banner you see right after `ssh user@host`.

Cross-distro (Debian / Ubuntu / RHEL / CentOS / Rocky / Alma / Fedora / Arch / openSUSE / Alpine), pure-bash, no runtime dependencies beyond what your distro already ships. One `curl … | sudo bash` and an interactive wizard — done.

![License: MIT](https://img.shields.io/badge/license-MIT-green)
![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-blue)
![Status](https://img.shields.io/badge/status-v0.1-orange)

## Preview

```
W e l c o m e   t o   y o u r   s e r v e r
================================================================
 Welcome to: web-01 (production)
 Web    : https://example.com
 Admin  : admin@example.com

 Warning: Authorized access only!
 All connections are logged and monitored.
 Unauthorized use may be subject to criminal prosecution.
================================================================
-------------------- System status --------------------
 Hostname : web-01.example.net
 Uptime   : 4 days, 18 hours, 16 minutes
 Load     : 0.05, 0.07, 0.02
 Memory   : 1238 / 32088 MB
 Disk /   : 11G / 1007G (2% used)
 Sessions : 1 active login(s)
-------------------------------------------------------
------------------ Package updates --------------------
 Updates  : 12 available, 3 security
 Checked  : 4m ago
-------------------------------------------------------
--------------------- Services ------------------------
   active       nginx
   active       postgresql
   failed       redis-server
-------------------------------------------------------
--------------------- Network -------------------------
 Public   : 203.0.113.42
 eth0     : 10.0.0.5
-------------------------------------------------------
---------------- SSL certificates ---------------------
   example.com              84d left
   api.example.com          11d left (expiring soon)
-------------------------------------------------------
--------------------- Security ------------------------
 SSH fails: 7 in last 24h
 fail2ban : 0 banned across 2 jail(s)
-------------------------------------------------------
------------------ Docker containers ------------------
 Containers: 3 running / 3 total
   nginx                       Up 32 minutes
   postgres                    Up 3 days (healthy)
   redis                       Up 12 hours
-------------------------------------------------------
```

(Colors are real — green for healthy, yellow for warnings, red for problems.)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/erneywhite/smart-motd/main/install.sh | sudo bash
```

The installer:
1. Detects your distro family and installs prerequisites if missing (`curl`, `tar`, `awk`).
2. Drops the runtime into `/usr/local/lib/smart-motd/` and a CLI at `/usr/local/bin/smart-motd`.
3. Wires it into the right place for your distro:
   - **Debian / Ubuntu**: `/etc/update-motd.d/01-smart-motd` (and disables the default Ubuntu help-text/news scripts).
   - **Everything else**: a systemd timer that renders the banner into `/etc/motd` every 5 minutes (cron fallback if no systemd).
4. Sets up a 5-minute systemd timer (`smart-motd-cache.timer`) to refresh "expensive" data — pending updates count, public IP, SSL expiry, directory sizes, weather.
5. Launches an interactive wizard so you can pick the sections you want.

To skip the wizard during install (e.g. for ansible / cloud-init):

```bash
curl -fsSL https://raw.githubusercontent.com/erneywhite/smart-motd/main/install.sh | sudo bash -s -- --no-setup
```

## Usage

```
smart-motd show           # preview the MOTD right now
sudo smart-motd setup     # re-run the interactive wizard
sudo smart-motd update-cache   # refresh cached values immediately
sudo smart-motd edit      # open the config in $EDITOR
smart-motd status         # show install paths and cache freshness
sudo smart-motd uninstall # remove smart-motd
```

## What it shows

Each section is independent and can be turned on/off in the config:

| Section | What it shows | Notes |
|---|---|---|
| **Header** | Custom banner text | Optional letter spacing |
| **Welcome** | Server title + custom KV lines (URLs, admin, …) | |
| **Warning** | Legal / authorized-access notice | |
| **System status** | Hostname, uptime, load, memory, disk(s), sessions | |
| **Maintenance** | "Reboot required" notice | Detects Debian flag, RHEL `needs-restarting` |
| **Package updates** | Pending updates, security count | apt / dnf / yum / zypper / pacman / apk |
| **Services** | Configured systemd units + status | `active` / `failed` / `inactive` |
| **Network** | Public IP, internal interface IPs | |
| **SSL certs** | Days until expiry, color-coded | Auto-discovers Let's Encrypt; supports remote checks `host:port` and PEM files |
| **Security** | Failed SSH attempts (24h), fail2ban bans | |
| **Temperature** | CPU temp via `lm-sensors` or `/sys/class/thermal` | |
| **SMART** | Per-disk health + temp via `smartctl` | |
| **Docker** | Running / total containers + per-container status | Detects healthy / unhealthy |
| **Podman** | Same as Docker | |
| **Kubernetes** | Context, ready nodes, namespace count | |
| **Directories** | Custom labeled paths with sizes | E.g. backups, big project dirs |
| **Recent logins** | Last N successful logins | |
| **Weather** | One-line wttr.in summary | Off by default |

Sections marked `auto` only render if the relevant tool/file exists on the host. Nothing breaks if `docker`, `kubectl`, `smartctl`, etc. aren't installed.

## How caching works

The on-login generator must be fast — under ~100ms. Some checks aren't:

- counting pending package updates (apt / dnf can take seconds)
- resolving the public IP (one HTTPS request)
- expiring SSL certs (one per domain)
- `du -sh` on large directories
- `smartctl` on multiple disks
- `wttr.in`

Those run in a 5-minute systemd timer (`smart-motd-cache.timer`), and the on-login path just `cat`s the cached values. On systems without systemd, the installer drops a `crontab` entry instead.

## Config

`/etc/smart-motd/config.conf` — sourced as bash. The setup wizard generates it for you; you can also edit it directly. See [config.example.conf](config.example.conf) for every available variable.

## Distro support

| Family | Auto-install hook | MOTD method | Tested |
|---|---|---|---|
| Debian / Ubuntu | `apt-get` | `/etc/update-motd.d/` | ✅ Ubuntu 22.04, Debian 12 |
| RHEL / CentOS / Rocky / Alma / Fedora | `dnf` / `yum` | systemd timer → `/etc/motd` | ✅ Rocky 9 |
| openSUSE | `zypper` | systemd timer → `/etc/motd` | (best-effort) |
| Arch / Manjaro | `pacman` | systemd timer → `/etc/motd` | (best-effort) |
| Alpine | `apk` | cron → `/etc/motd` | (best-effort) |

## Security

- The installer is plain shell. Read it before piping it to root: [`install.sh`](install.sh).
- The runtime never opens listening sockets and only makes outbound HTTPS calls when you enable optional sections (public IP, SSL remote check, weather).
- All cached values are world-readable in `/var/cache/smart-motd/` — don't put secrets in the warning text.

## Uninstall

```bash
sudo smart-motd uninstall
```

Removes the install dir, binaries, systemd units, cron entries, and the `update-motd.d` hook. Leaves `/etc/smart-motd/` so you can re-install without losing your config.

## Contributing

PRs welcome. The codebase is intentionally small:

```
bin/
  motd-generate         # main entry, sources sections in order
  motd-cache-update     # refreshes cached snippets
  motd-setup            # interactive wizard
  motd-uninstall
  smart-motd            # CLI wrapper
lib/
  common.sh             # colors, distro detect, formatting
  cache.sh              # cache writers (heavy queries live here)
  sections/             # one .sh per visible section
systemd/
install.sh              # curl|sudo bash entrypoint
config.example.conf
```

Adding a new section is one file in `lib/sections/`. See the existing ones (e.g. [`services.sh`](lib/sections/services.sh)) for the pattern.

## License

[MIT](LICENSE)
