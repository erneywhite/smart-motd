# smart-motd

A customizable, modular **MOTD** (message of the day) for Linux servers — the banner you see right after `ssh user@host`.

Cross-distro (Debian / Ubuntu / RHEL / CentOS / Rocky / Alma / Fedora / Arch / openSUSE / Alpine), pure-bash, no runtime dependencies beyond what your distro already ships. One `curl … | sudo bash`, a paged interactive wizard with live previews, and you're done.

[![CI](https://github.com/erneywhite/smart-motd/actions/workflows/ci.yml/badge.svg)](https://github.com/erneywhite/smart-motd/actions/workflows/ci.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-blue)
![Version](https://img.shields.io/badge/version-v0.5.0-brightgreen)
![Distro support](https://img.shields.io/badge/distros-Debian%20%7C%20RHEL%20%7C%20Arch%20%7C%20openSUSE%20%7C%20Alpine-blue)

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
 Hostname   : web-01.example.net
 Uptime     : 4 days, 18 hours, 16 minutes
 Load       : 0.05, 0.07, 0.02
 Memory     : 1238 / 32088 MB
 Disk /     : 11G / 1007G (2% used)
 Sessions   : 1 active login(s)
-------------------------------------------------------
------------------ Package updates --------------------
 Updates    : 12 available, 3 security
 Checked    : 4m ago
-------------------------------------------------------
--------------------- Services ------------------------
   active       nginx
   active       postgresql
   failed       redis-server
-------------------------------------------------------
--------------------- Network -------------------------
 Public     : 203.0.113.42
 eth0       : 10.0.0.5
-------------------------------------------------------
---------------- SSL certificates ---------------------
   example.com              84d left
   api.example.com          11d left (expiring soon)
-------------------------------------------------------
--------------------- Security ------------------------
 SSH fails  : 7 in last 24h
 fail2ban   : 0 banned across 2 jail(s)
-------------------------------------------------------
------------------ Docker containers ------------------
 Containers : 3 running / 3 total
   nginx                       Up 32 minutes
   postgres                    Up 3 days (healthy)
   redis                       Up 12 hours
-------------------------------------------------------
----------------------- Weather -----------------------
   Berlin: ☀ +21°C, Sunny
-------------------------------------------------------
```

(Colors are real — accent on headings, green for healthy, yellow for warnings, red for problems.)

## Features at a glance

- **Paged interactive setup** with arrow-key navigation, live previews of every theme/style choice, and zero flicker on redraw.
- **Bilingual wizard** — first page asks `English / Русский`. The rendered MOTD itself stays in the system locale.
- **Smart autodiscover** during setup — lists installed `systemd` services, real disk mountpoints, and your geolocated city for weather, all as multiselect lists. No more typos in unit names.
- **20 visual themes** — `classic`, `slim`, `heavy`, `double`, `dotted`, `ascii`, `arrows`, `stars`, `wave`, `block`, `pipes`, `retro`, `compact`, `chevrons`, `bullets`, `cross`, `plus`, `cosmic`, `sharp`, `zen`. Mix-and-match the banner / divider / KV-separator characters via `THEME=custom`.
- **13 color palettes** — `default`, `ocean`, `forest`, `sunset`, `amber`, `mono`, `matrix`, `neon`, `coral`, `mint`, `sky`, `gold`, `snow`.
- **Heavy data is cached** — every slow query (apt/dnf updates, public IP, SSL expiry, `du` on big dirs, `smartctl`, journalctl SSH-fail counts, docker/podman/kubernetes lists, weather) refreshes in a 5-minute systemd timer. The on-login path just sources cache files — login stays under ~50 ms even on busy hosts with thousands of failed-SSH log entries.
- **`pam_motd` integration** — on Debian/Ubuntu the cache job also regenerates `/run/motd.dynamic`, so config changes show up at the very next login (instead of waiting for pam_motd's own refresh schedule to skip a few logins).
- **Cross-distro install** — the installer detects your distro family and wires into the right hook automatically (`/etc/update-motd.d/` for Debian-family, systemd timer → `/etc/motd` for RHEL/openSUSE/Arch, cron fallback for Alpine).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/erneywhite/smart-motd/main/install.sh | sudo bash
```

The installer:

1. Detects your distro family and installs missing prerequisites (`curl`, `tar`, `awk`).
2. Drops the runtime into `/usr/local/lib/smart-motd/` and a CLI at `/usr/local/bin/smart-motd`.
3. Wires it into the right place for your distro:
   - **Debian / Ubuntu**: `/etc/update-motd.d/01-smart-motd` (and disables the default Ubuntu help-text/news scripts).
   - **Everything else**: a systemd timer that renders the banner into `/etc/motd` every 5 minutes (cron fallback if no systemd).
4. Sets up a 5-minute systemd timer (`smart-motd-cache.timer`) to refresh expensive data sources.
5. Drops you into the interactive wizard so you can pick sections, theme, and color palette.

To skip the wizard during install (e.g. for Ansible / cloud-init):

```bash
curl -fsSL https://raw.githubusercontent.com/erneywhite/smart-motd/main/install.sh | sudo bash -s -- --no-setup
```

## Usage

```
smart-motd show                # preview the MOTD right now
sudo smart-motd setup          # re-run the interactive wizard
sudo smart-motd update-cache   # refresh cached values immediately
sudo smart-motd edit           # open the config in $EDITOR
smart-motd status              # show install paths and cache freshness
smart-motd doctor              # diagnose the install (checks hooks/timers/freshness)
smart-motd version             # show installed version + check for updates
sudo smart-motd upgrade        # pull and install the latest release
sudo smart-motd uninstall      # remove smart-motd
```

If the login banner ever stops looking right, `smart-motd doctor` runs through every wired component (config, cache files, distro hook, systemd timers, `/run/motd.dynamic` freshness, generator dry-run, GitHub reachability) and reports each as `✓` / `!` / `✗` with a hint on how to fix it.

## What it shows

Each section is independent and can be turned on/off in the config (or via the wizard's first page).

| Section | What it shows | Notes |
|---|---|---|
| **Header** | Custom banner text | Letter spacing, UPPER, lower, plain styles |
| **Welcome** | Server title + custom KV lines (URLs, admin, …) | |
| **Warning** | Legal / authorized-access notice | |
| **System status** | Hostname, uptime, load, memory, disk(s), sessions | Mountpoints autodiscovered via `df` |
| **Maintenance** | "Reboot required" notice | Detects Debian flag, RHEL `needs-restarting` |
| **Package updates** | Pending updates, security count | apt / dnf / yum / zypper / pacman / apk |
| **Services** | Configured systemd units + status | `active` / `failed` / `inactive`; multiselect autodiscover |
| **Network** | Public IP, internal interface IPs | |
| **SSL certs** | Days until expiry, color-coded | Auto-discovers Let's Encrypt; supports remote checks `host:port` and PEM files |
| **Security** | Failed SSH attempts (24h), fail2ban bans | journalctl + fail2ban-client |
| **Temperature** | CPU temp via `lm-sensors` or `/sys/class/thermal` | |
| **SMART** | Per-disk health + temp via `smartctl` | |
| **Docker** | Running / total containers + per-container status | Detects `healthy` / `unhealthy` |
| **Podman** | Same shape as Docker | |
| **Kubernetes** | Context, ready nodes, namespace count | Skips silently if no cluster reachable |
| **VPN** | WireGuard interfaces (peers + handshakes), OpenVPN daemons | Cached (wg requires root) |
| **Time sync** | NTP server, offset, sync state | `timedatectl` / `chronyc` / `ntpq` |
| **Storage arrays** | mdadm RAID + ZFS pools | Color-coded by health |
| **Directories** | Custom labeled paths with sizes | E.g. backups, big project dirs |
| **Recent logins** | Last N successful logins | |
| **Weather** | One-line wttr.in summary | Off by default; auto-detects your city via IP |

Sections marked `auto` only render if the relevant tool/file exists on the host. Nothing breaks if `docker`, `kubectl`, `smartctl`, etc. aren't installed — the wizard's first page also no longer pre-checks these on hosts where the underlying tool isn't present.

## Visual themes & color palettes

Pick the visual style during setup. Each picker page shows a **live preview using your actual header text** so you can see exactly what your MOTD will look like before committing.

| Theme | Banner | Divider | KV sep | Heading style |
|---|---|---|---|---|
| `classic` | `=` | `-` | `:` | centered |
| `slim` | `─` | `─` | `:` | centered |
| `heavy` | `━` | `━` | `▸` | bracketed |
| `double` | `═` | `═` | `:` | centered |
| `dotted` | `┄` | `┄` | `▸` | left |
| `ascii` | `#` | `-` | `:` | left |
| `arrows` | `▶` | `▸` | `→` | arrows |
| `stars` | `★` | `·` | `·` | star-padded |
| `wave` | `~` | `~` | `~` | wavy |
| `block` | `█` | `▄` | `│` | bracketed |
| `pipes` | `═` | `─` | `│` | bracketed |
| `retro` | `=` | `=` | `=` | left |
| `compact` | `─` | (blank) | `:` | left |
| `chevrons` | `»` | `»` | `»` | `»» Title ««` |
| `bullets` | `•` | `•` | `•` | `• • • Title • • •` |
| `cross` | `╳` | `╳` | `╳` | bracketed |
| `plus` | `+` | `+` | `+` | left |
| `cosmic` | `·` | `·` | `◇` | star-padded |
| `sharp` | `◢` | `◣` | `◆` | bracketed |
| `zen` | `─` | (blank) | `─` | minimal |

Color palettes set the heading accent. Status colors (green/yellow/red) stay intact.

| Palette | Accent | Notes |
|---|---|---|
| `default` | cyan | Sane default |
| `ocean` | blue | |
| `forest` | green | |
| `sunset` | magenta | |
| `amber` | yellow | CRT-amber vibes |
| `mono` | bold (no color) | For colorless terminals |
| `matrix` | bright green | |
| `neon` | bright magenta | |
| `coral` | bright red | |
| `mint` | bright cyan | |
| `sky` | bright blue | |
| `gold` | bright yellow | |
| `snow` | bright white | |

You can also override individual `THEME_BANNER_CHAR` / `THEME_DIVIDER_CHAR` / `THEME_KV_SEPARATOR` / `THEME_HEADING_STYLE` in `/etc/smart-motd/config.conf` — those win over the named theme's defaults.

## How caching works

The on-login generator must be fast — under ~50 ms even on a saturated host. Some checks aren't:

- counting pending package updates (apt / dnf can take seconds)
- resolving the public IP (one HTTPS request)
- expiring SSL certs (one connection per domain)
- `du -sh` on large directories
- `smartctl` on multiple disks
- `journalctl` for SSH fails (slow when the journal has thousands of matches)
- `docker ps` / `podman ps` / `kubectl get` (each takes 100 ms+)
- `wttr.in`

Those run in a 5-minute systemd timer (`smart-motd-cache.timer`), and the on-login path just `cat`s / `source`s the cached files. On systems without systemd, the installer drops a `crontab` entry instead.

On Debian/Ubuntu the same job also regenerates `/run/motd.dynamic` so `pam_motd` always shows the latest banner — no waiting for its own refresh schedule.

## Config

`/etc/smart-motd/config.conf` — sourced as bash. The setup wizard generates it for you; you can also edit it directly. See [config.example.conf](config.example.conf) for every available variable with comments.

## Distro support

| Family | Auto-install hook | MOTD method | Tested |
|---|---|---|---|
| Debian / Ubuntu | `apt-get` | `/etc/update-motd.d/` + `/run/motd.dynamic` refresh | ✅ Ubuntu 22.04, Debian 12 |
| RHEL / CentOS / Rocky / Alma / Fedora | `dnf` / `yum` | systemd timer → `/etc/motd` | ✅ Rocky 9 |
| openSUSE | `zypper` | systemd timer → `/etc/motd` | best-effort |
| Arch / Manjaro | `pacman` | systemd timer → `/etc/motd` | best-effort |
| Alpine | `apk` | cron → `/etc/motd` | best-effort |

## Security

- The installer is plain shell. Read it before piping it to root: [`install.sh`](install.sh).
- The runtime never opens listening sockets and only makes outbound HTTPS calls when you enable optional sections (public IP, SSL remote check, weather, weather-city geolocation).
- All cached values are world-readable in `/var/cache/smart-motd/` — don't put secrets in the warning text or welcome lines.
- The cache update job runs as root via systemd to query Docker / journalctl / fail2ban etc.; cache files are written atomically.

## Uninstall

```bash
sudo smart-motd uninstall
```

Removes the install dir, binaries, systemd units, cron entries, and the `update-motd.d` hook. Re-enables the default Ubuntu help-text/news scripts where applicable. Leaves `/etc/smart-motd/` so you can re-install without losing your config — wipe it manually if you want a clean slate.

## Contributing

PRs welcome. The codebase is intentionally small:

```
bin/
  motd-generate         # main entry, sources sections in order
  motd-cache-update     # refreshes cached snippets (and /run/motd.dynamic on Debian)
  motd-setup            # paged interactive wizard
  motd-uninstall
  smart-motd            # CLI wrapper
lib/
  common.sh             # colors, theme presets, distro detect, formatting
  cache.sh              # cache writers (heavy queries live here)
  wizard.sh             # paged-UI primitives (text/yesno/select/multiselect/list/preview)
  sections/             # one .sh per visible section
systemd/
install.sh              # curl|sudo bash entrypoint
config.example.conf
```

Adding a new section is one file in `lib/sections/`. See the existing ones (e.g. [`services.sh`](lib/sections/services.sh)) for the pattern.

Adding a new theme is a `case` arm in [`lib/common.sh`](lib/common.sh) inside `apply_theme`, plus one entry in the wizard's `wizard_select_preview` call. Same for color palettes in `apply_color_theme`.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full history.

Highlights:

- **v0.5.0** — `smart-motd doctor` diagnostic command. New sections: VPN (WireGuard / OpenVPN), Time sync (NTP), Storage arrays (mdadm / ZFS).
- **v0.4.x** — Paged wizard with viewport scrolling, 20 themes, 13 color palettes, RU translations, `smart-motd upgrade`, Ctrl+C exits cleanly.
- **v0.3.x** — Login color force, cache the four heaviest sections (security/docker/podman/k8s), bilingual wizard.
- **v0.2.0** — Paged interactive wizard with live previews; theme system.
- **v0.1.0** — Initial cross-distro release.

## License

[MIT](LICENSE)
