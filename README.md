# smart-motd

A modular, customizable **MOTD** (message of the day) for Linux servers — the banner you see right after `ssh user@host`.

Pure bash, zero runtime dependencies beyond what your distro already ships, one `curl … | sudo bash` to install. Works on Debian, Ubuntu, RHEL, CentOS, Rocky, Alma, Fedora, Arch and openSUSE. A paged interactive wizard with live previews handles configuration — you don't edit a config file by hand unless you want to.

[![CI](https://github.com/erneywhite/smart-motd/actions/workflows/ci.yml/badge.svg)](https://github.com/erneywhite/smart-motd/actions/workflows/ci.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-blue)
![Version](https://img.shields.io/badge/version-v1.13.3-brightgreen)
![Distro support](https://img.shields.io/badge/distros-Debian%20%7C%20RHEL%20%7C%20Arch%20%7C%20openSUSE-blue)

---

## What it looks like

```
W e l c o m e   t o   y o u r   s e r v e r
================================================================
 Welcome to: web-01 (production)
 Web    : https://example.com
 Admin  : admin@example.com

 Warning: Authorized access only!
 All connections are logged and monitored.
================================================================
-------------------- System status --------------------
 Hostname   : web-01
 OS         : Ubuntu 22.04.3 LTS
 Uptime     : 4 days, 18 hours, 16 minutes
 Load       : 0.05, 0.07, 0.02
 Memory     : 1238 / 32088 MB
 Disk /     : 11G / 1007G (2% used)
 Disk sdb1  : 273G / 492G (56% used)
 Sessions   : 1 active login(s)
-------------------------------------------------------
------------------ Package updates --------------------
 Updates    : 12 available, 3 security
 Reboot     : required (kernel/library update applied)
 Checked    : 4m ago
-------------------------------------------------------
--------------------- Services ------------------------
   active       nginx
   active       postgresql
   failed       redis-server
-------------------------------------------------------
--------------------- Network -------------------------
 Public     : 203.0.113.42
 eth0       : 10.0.0.5         ↓ 12.3 KB/s  ↑ 4.5 KB/s
 wg0        : 10.8.0.1         ↓ 1.2 KB/s   ↑ 0.8 KB/s
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

 ↑ smart-motd v1.14.0 available (you have v1.13.3) — run sudo smart-motd upgrade
```

Colors are real — accent on headings, green for healthy, yellow for warnings, red for problems. Twenty visual themes and thirteen color palettes ship in the box; pick during setup with live preview.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/erneywhite/smart-motd/main/install.sh | sudo bash
```

The installer:

1. Detects your distro and installs missing prerequisites (`curl`, `tar`, `awk`).
2. Drops the runtime into `/usr/local/lib/smart-motd/` and a CLI at `/usr/local/bin/smart-motd`.
3. Wires into the right hook for your distro:
   - **Debian / Ubuntu** — `/etc/update-motd.d/01-smart-motd`. Every other script in `/etc/update-motd.d/` and `/etc/motd.d/` is disabled (`chmod -x`) so the distro's default `landscape-sysinfo`, `motd-news`, ESM-announce, etc. don't leak under our banner. `motd-news.timer` is also masked — with its script disabled the unit would otherwise fail on every fire and sit in `systemctl --failed` forever. Uninstall reverses both.
   - **Everything else** — a systemd timer that renders the banner into `/etc/motd` every 5 minutes (cron fallback if no systemd).
4. Sets up a 5-minute systemd timer (`smart-motd-cache.timer`) to refresh expensive data sources in the background.
5. Drops you into the interactive wizard so you can pick sections, theme, and palette.

For Ansible / cloud-init you can skip the wizard:

```bash
curl -fsSL https://raw.githubusercontent.com/erneywhite/smart-motd/main/install.sh | sudo bash -s -- --no-setup
```

The default configuration is sensible out of the box — you can run the wizard later with `sudo smart-motd setup`.

---

## Usage

```
smart-motd show                       # preview the MOTD right now
smart-motd watch [SEC]                # re-render every SEC seconds (default 5), alt-screen
sudo smart-motd setup                 # re-run the interactive wizard
sudo smart-motd update-cache          # refresh cached values immediately
sudo smart-motd edit                  # open the config in $EDITOR
smart-motd config get [KEY]           # print one value (or full config)
sudo smart-motd config set KEY VAL    # set one scalar value without re-running setup
sudo smart-motd test-alert [ssh|recap] # fire a Telegram alert right now (verification)
smart-motd status                     # show install paths and cache freshness
smart-motd doctor                     # diagnose every wired component
smart-motd benchmark [N]              # time each section to spot slow ones
smart-motd version                    # installed version + check for updates
sudo smart-motd upgrade               # pull and install the latest release
sudo smart-motd uninstall             # remove smart-motd
```

If the banner ever stops looking right, `smart-motd doctor` walks through every wired component (config, cache files, distro hook, systemd timers, `/run/motd.dynamic` freshness, generator dry-run, GitHub reachability) and reports each as `✓` / `!` / `✗` with a hint on how to fix it.

---

## Sections

Every section is independent — toggle on/off in the wizard's first page or directly in `/etc/smart-motd/config.conf`. Sections marked **auto** only render if the underlying tool exists on the host (nothing breaks if `docker` / `kubectl` / `smartctl` aren't installed).

| Section | What it shows |
|---|---|
| **Header** | Custom banner text — letter-spaced, UPPER, lower, or plain |
| **Welcome** | Server title + optional key/value lines (URLs, admin contacts, …) |
| **Warning** | Legal / authorized-access notice |
| **System status** | Hostname, OS (`Ubuntu 22.04` / `Debian 12` / …), uptime, load, memory, **all local disks**, active sessions. Disks are auto-detected — mount one later and it appears at the next login, no re-setup. Only real block devices are listed (no tmpfs, snap, docker layers, `/boot`, or FUSE mounts like Proxmox's `/etc/pve`), and rows are labeled by device: `Disk sdb1`, `Disk nvme0n1p1` |
| **Maintenance** | "Reboot required" notice (Debian flag, RHEL `needs-restarting`) |
| **Package updates** | Pending updates, security count, **cross-distro reboot-required indicator**, last-check freshness |
| **Services** | Configured systemd units with `active` / `failed` / `inactive`. Optional auto-show of any unit in the failed state (`SERVICES_SHOW_FAILED=true`) — catches crashes you didn't know to look for |
| **Network** | Public IP, internal interface IPs, optional rx/tx rate per interface (5-min averaged) |
| **SSL certs** | Days until expiry, color-coded. **Auto-detects** certs from Let's Encrypt, control panels (aaPanel, ISPmanager, FastPanel, HestiaCP, Plesk, cPanel) and any `ssl_certificate` / `SSLCertificateFile` directive in nginx / apache configs. Manual remote checks like `example.com:8443` are also supported. |
| **Security** | Failed SSH attempts (last 24h), fail2ban bans across all jails |
| **Temperature** | CPU temp via `lm-sensors` or `/sys/class/thermal` *(auto)* |
| **SMART** | Per-disk health and temperature via `smartctl` *(auto)* |
| **Docker** | Running / total containers + per-container status; detects `healthy` / `unhealthy` *(auto)* |
| **Podman** | Same shape as Docker *(auto)* |
| **Kubernetes** | Context, ready nodes, namespace count *(auto)* |
| **VPN** | WireGuard interfaces (peers + last handshakes), OpenVPN daemons *(auto)* |
| **Time sync** | NTP server, offset, sync state via `timedatectl` / `chronyc` / `ntpq` *(auto)* |
| **Storage arrays** | mdadm RAID + ZFS pools, color-coded by health *(auto)* |
| **Directories** | Custom labeled paths with sizes; entries flagged `\|backup` also show the age of the newest file inside, color-coded by staleness |
| **Recent logins** | Last N successful SSH logins |
| **Weather** | One-line `wttr.in` summary; auto-detects your city via IP *(off by default)* |
| **Footer** | Custom closing line under the banner |
| **Telegram SSH alerts** | Not visible in the banner — fires a Telegram message on every SSH login *(off by default; see below)* |
| **Upgrade notice** | One-line `↑ smart-motd vX.Y.Z available` at the bottom when a newer release is on GitHub. Hidden when up-to-date |

---

## Themes and palettes

The wizard's theme picker shows a **live preview using your actual header text** so you can see exactly how the banner will look before committing.

**Twenty themes:** `classic`, `slim`, `heavy`, `double`, `dotted`, `ascii`, `arrows`, `stars`, `wave`, `block`, `pipes`, `retro`, `compact`, `chevrons`, `bullets`, `cross`, `plus`, `cosmic`, `sharp`, `zen`.

**Thirteen color palettes** for the heading accent (status colors stay green/yellow/red regardless): `default`, `ocean`, `forest`, `sunset`, `amber`, `mono`, `matrix`, `neon`, `coral`, `mint`, `sky`, `gold`, `snow`.

Mix-and-match individual characters with `THEME=custom` and the `THEME_BANNER_CHAR` / `THEME_DIVIDER_CHAR` / `THEME_KV_SEPARATOR` / `THEME_HEADING_STYLE` knobs in `config.conf` — those win over the named theme's defaults.

### A note on fonts

The **wizard chrome** (cursor, scroll markers, checkboxes) uses ASCII only — `>`, `^`, `v`, `[x]`, `[ ]` — so it works in any terminal regardless of font.

The **theme presets** are a different story. Themes like `stars` (`★`), `arrows` (`▶ ▸ →`), `chevrons` (`» «`), `sharp` (`◢ ◣ ◆`) need a Unicode-rich font on **your local terminal** (iTerm2, Alacritty, Kitty, Windows Terminal, gnome-terminal, …). If you see `■` rectangles, your local font lacks those glyphs — install a Nerd Font on your laptop.

**Exception** — when you connect via VNC / RDP / xrdp or sit at a local TTY (`tty1`–`tty6`), the rendering happens **on the server**, so install Nerd Fonts server-side instead (`apt install fonts-jetbrains-mono`, `zypper install nerd-fonts-jetbrains-mono-fonts`, etc.).

Or just stick to the ASCII-friendly themes that work everywhere: `classic`, `slim`, `double`, `ascii`, `pipes`, `retro`, `compact`.

---

## Telegram SSH login alerts

Optional — when enabled, fires a Telegram message on every successful SSH login:

```
🔓 SSH login
👤 User: root
🌐 IP: 198.51.100.42
🌐 rDNS: client.example.net
🖥 Server: web-01 (203.0.113.42)
🕐 2026-05-08 22:12:46 UTC
```

**Setup**: tick "Telegram SSH login alerts" in the wizard's first page, then on the configuration page:

- **Bot token** — create one via [@BotFather](https://t.me/BotFather) (`/newbot`, copy the API token).
- **Destination type** — personal DM or group / channel. The follow-up question adapts.
- **Chat / user ID** — get yours via [@userinfobot](https://t.me/userinfobot). Personal user IDs are positive; group / channel IDs are negative (e.g. `-1001234567890`). For DMs, press `/start` to your bot once first — bots can't initiate conversations.
- **Thread ID** (groups with Topics only, optional).
- **Alert language** — `en` or `ru`, independent from the wizard language.
- **IP whitelist** — list of IPs / CIDR blocks that don't trigger an alert (your home / office / VPN ranges).
- **Daily recap** — opt-in once-a-day summary message: SSH login count, failed attempts, pending updates, reboot status, uptime, 24h-averaged load and memory, root disk usage.
- **Additional destinations** — extra `bot_token|chat_id|thread_id` tuples. Every alert is fanned out to the primary destination AND each extra in parallel. Useful when the same login alert needs to land in your own chat *and* a client's chat from different bots.
- **Test send** — the wizard offers a test message before saving. Fire one any time later via `sudo smart-motd test-alert [ssh|recap]`.

**Under the hood**: a single `session optional pam_exec.so /usr/local/lib/smart-motd/bin/motd-ssh-alert` line is appended to `/etc/pam.d/sshd` at install time (the original is backed up to `/etc/pam.d/sshd.smart-motd.bak`). The handler does an rDNS lookup with a 3 s timeout and fires the Telegram POST in a detached background subshell — **login is never delayed by the network call**.

**Security**:

- Bot token, chat ID, thread ID and the multi-dest array live in `/etc/smart-motd/secrets.conf` with mode `0600` (root-only). `config.conf` stays world-readable without leaking credentials.
- The PAM hook is `optional`, so even if `pam_exec` somehow fails, SSH still works.
- `smart-motd uninstall` removes the PAM line and the secrets file cleanly.

---

## How caching keeps login fast

The on-login generator has to be fast — you feel every millisecond between `ssh` and a shell prompt. Some checks aren't naturally fast:

- counting pending package updates (apt / dnf can take seconds)
- resolving the public IP (one HTTPS request)
- expiring SSL certs (one connection per remote check, plus `openssl x509` on PEM files)
- `du -sh` on large directories
- `smartctl` on multiple disks
- `journalctl` for SSH-fail counts (slow when the journal has thousands of matches)
- `docker ps` / `podman ps` / `kubectl get` (each takes 100 ms+)
- `wttr.in`

These run in a 5-minute systemd timer (`smart-motd-cache.timer`); the on-login path just sources the cached files. On systems without systemd the installer drops a `crontab` entry instead. On Debian / Ubuntu the same job also regenerates `/run/motd.dynamic` so `pam_motd` always shows the latest banner.

If something feels slow, run `smart-motd benchmark` — it times every section so you can spot the culprit and either disable it or raise the cache interval.

---

## Config

`/etc/smart-motd/config.conf` is sourced as bash. The wizard writes it for you; you can also edit by hand. See [`config.example.conf`](config.example.conf) for every available variable with comments.

Quick edits without the wizard:

```bash
smart-motd config get               # dump the whole file
smart-motd config get THEME         # one scalar value
smart-motd config get SSL_DOMAINS   # arrays print one element per line
sudo smart-motd config set THEME slim
sudo smart-motd config set HEADER_TEXT "production"
```

Array values are read-only via `config set` (use `sudo smart-motd edit` or re-run the wizard). Secret keys (`TELEGRAM_BOT_TOKEN`, etc.) live in `/etc/smart-motd/secrets.conf` (mode `0600`) and require root to read or write.

The knobs people reach for most often:

```bash
SYSTEM_DISK_AUTO=true          # list every local disk; false = fixed list below
SYSTEM_DISK_PATHS=('/mnt/nas') # extra mountpoints; bypasses every filter
SYSTEM_DISK_EXCLUDE=('/srv/*') # hide mountpoints from the auto list (globs ok)
SERVICES_SHOW_FAILED=true      # also surface any systemd unit in 'failed'
SSL_WARN_DAYS=14               # days before expiry that turn a cert yellow
```

---

## Distro support

| Family | Install hook | MOTD method | Tested |
|---|---|---|---|
| Debian / Ubuntu | `apt-get` | `/etc/update-motd.d/` + `/run/motd.dynamic` refresh | ✅ Ubuntu 22.04 / 24.04, Debian 12 / 13 |
| RHEL / CentOS / Rocky / Alma / Fedora | `dnf` / `yum` | systemd timer → `/etc/motd` | ✅ Rocky 9, CentOS 10 |
| openSUSE | `zypper` | systemd timer → `/etc/motd` | ✅ openSUSE Leap 15.6 |
| Arch / Manjaro | `pacman` | systemd timer → `/etc/motd` | ✅ Arch |

---

## Security

- The installer is plain shell. Read it before piping it to root: [`install.sh`](install.sh).
- The runtime never opens listening sockets and only makes outbound HTTPS calls when you enable optional sections (public IP, SSL remote check, weather, weather-city geolocation).
- All cached values are world-readable in `/var/cache/smart-motd/`. Don't put secrets in the warning text or welcome lines — those end up in the banner everyone sees.
- The cache update job runs as root via systemd (it needs Docker / journalctl / fail2ban access). Cache files are written atomically.

---

## Uninstall

```bash
sudo smart-motd uninstall
```

Removes the install dir, the CLI, systemd units, cron entries, the PAM hook and the `update-motd.d` hook. Re-enables every script in `/etc/update-motd.d/` and `/etc/motd.d/` that the installer disabled and unmasks `motd-news`, so the distro's original banner is fully restored. Leaves `/etc/smart-motd/` in place so you can re-install without losing your config — wipe it manually if you want a clean slate.

---

## Contributing

PRs welcome. The codebase is intentionally small:

```
bin/
  motd-generate          # main entry; sources sections in configured order
  motd-cache-update      # 5-min systemd timer target; refreshes cached snippets
  motd-setup             # paged interactive wizard
  motd-doctor            # diagnostic command (smart-motd doctor)
  motd-benchmark         # per-section timing (smart-motd benchmark)
  motd-ssh-alert         # PAM-hook target; fires Telegram on SSH login
  motd-recap             # daily Telegram summary
  motd-uninstall
  smart-motd             # CLI wrapper
lib/
  common.sh              # colors, theme presets, distro detect, formatting
  cache.sh               # cache writers (heavy queries live here)
  wizard.sh              # paged-UI primitives (yes/no, select, multi-select, list editor)
  sections/              # one .sh per visible section
systemd/                 # timer units + dropins
completions/             # bash completion
.github/workflows/       # shellcheck + bash -n + e2e smoke test on every PR
install.sh               # curl|sudo bash entrypoint
config.example.conf
CHANGELOG.md
```

Adding a new section is one file in `lib/sections/`. See e.g. [`services.sh`](lib/sections/services.sh) for the pattern.

Adding a new theme is one `case` arm in [`lib/common.sh`](lib/common.sh) inside `apply_theme`, plus one entry in the wizard's `wizard_select_preview` call. Same for color palettes in `apply_color_theme`.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full history.

Highlights:

- **v1.13.3** — fail2ban states are reported distinctly: *installed but not running* (yellow), *running but no jails configured* (red), or the normal ban count. v1.13.2 hid the line entirely in the middle case, which was worse than the problem it fixed.
- **v1.13.2** — Security section no longer paints a green "0 banned across 0 jail(s)" when fail2ban is running with **no jails configured** — that's now a red warning, since the host is unprotected. SMART keeps the `-d TYPE` from `smartctl --scan`, so drives in USB enclosures (JMicron & co.) stop vanishing from the list, and a disk is no longer dropped just because `smartctl` exits non-zero — which it does precisely when a disk is failing. The installer now masks `motd-news` instead of leaving it permanently in `failed`.
- **v1.13.1** — Only real disks are listed: a row shows up when its source is an actual block device, which drops `/boot` and FUSE mounts like Proxmox's `/etc/pve` that a filesystem-type blacklist kept missing. Rows are labeled by device (`Disk sdb1`, `Disk nvme0n1p1`) so they line up with `lsblk` and the SMART section.
- **v1.13.0** — Disks are detected automatically: System status now lists every local filesystem, and a disk you mount later appears at the next login without re-running the wizard. Pseudo filesystems are filtered by type (snaps, docker layers, tmpfs), disks mounted twice are deduplicated, and network mounts are skipped so a stale NFS server can't hang the login banner. Panel-style mountpoints (`/srv/dev-disk-by-uuid-…`) are labeled by device (`Disk sdb1`), and the label column widens so long names like `Disk nvme0n1p2` fit in full. Also fixed the wizard's disk picker, which detected *nothing* — it used `df -P --output=target`, a combination GNU coreutils rejects outright.
- **v1.12.5** — Dropped Alpine Linux support. It was best-effort only and real-world testing confirmed it doesn't work cleanly (busybox login has no PAM for the alert hook; OpenRC instead of systemd for the timers). The installer now refuses on Alpine with a clear message instead of half-installing.
- **v1.12.4** — `motd-news.service` no longer shows as failed in the failed-units auto-list — it fails as a side effect of smart-motd disabling the `update-motd.d` scripts, so it's filtered by default. New `SERVICES_FAILED_IGNORE=()` (glob-capable) suppresses other noisy units.
- **v1.12.3** — Wizard now works with the Russian keyboard layout. Action keys like `c` (clear), `d` (delete), `a` (add) silently failed on Russian-JCUKEN before because `read -rsn1` only grabbed one byte of the two-byte Cyrillic UTF-8 sequence. New `_wiz_readkey` helper reads the full character and case patterns accept both Latin and Cyrillic equivalents (`c|C|с|С`, `a|A|ф|Ф`, etc.).
- **v1.12.2** — List editor (used by SSL targets, network interfaces, custom services, etc.) rewritten as cursor-based. `[d]` now deletes the **highlighted** entry instead of the last one; `[e]` edits in place pre-filled with the current value; `[c]` clears all with a one-keystroke confirm. Arrow-key navigation with viewport scrolling for long lists.
- **v1.12.1** — SSL auto-detect now finds certs in control-panel paths (aaPanel, ISPmanager, FastPanel, HestiaCP, Plesk, cPanel) and aaPanel's nginx configs (which live outside `/etc/nginx/`). The wizard's redundant "Auto-discover Let's Encrypt? Y/N" page is gone — one consolidated multi-select covers everything detected.
- **v1.12.0** — Reboot-required indicator in the Package updates block (cross-distro). Unified SSL multi-select. Opt-in `SERVICES_SHOW_FAILED=true` surfaces any failed systemd unit. New `smart-motd benchmark` diagnostic times every section.
- **v1.11.0** — Multiple Telegram destinations. One alert can fan out to N `(bot, chat, thread)` tuples in parallel — useful when the same login needs to land in your own chat *and* a client's chat from different bots.
- **v1.10.0** — Backup-age annotation in Monitored directories. Flag an entry as `|backup` and the MOTD shows the age of the newest file inside, color-coded by staleness.
- **v1.9.x** — `sudo smart-motd test-alert [ssh|recap]` fires a Telegram alert immediately for verification. `smart-motd config get/set KEY [VALUE]` for surgical edits without re-running the wizard. Fixed a `cp`-vs-running-script race during upgrade.
- **v1.8.x** — Upgrade flow no longer auto-launches the wizard; instead prints the CHANGELOG entry for the new version plus a single Re-setup status line.
- **v1.7.x** — Daily Telegram recap includes 24h-averaged load and memory, plus root disk usage. Cache job collects 5-min samples for the moving average.
- **v1.6.x** — Passive upgrade notice at the bottom of the MOTD when a newer release is published on GitHub (system parameter, always on).
- **v1.5.x** — Telegram alert IP whitelist (CIDR-aware), `smart-motd watch [SEC]` for live re-render, opt-in once-a-day Telegram recap. Server identity uses kernel `hostname` + primary-interface IP (works behind NAT).
- **v1.4.x** — Telegram SSH-login alerts with PAM-hook + bilingual messages (en/ru). Bash tab completion. Setup wizard preserves existing config / credentials on re-runs.
- **v1.3.x** — Per-interface rx/tx byte rate (5-min averaged) in the Network section. Installer hardened for Docker / chroot environments.
- **v1.2.0** — OS line in System status. Wizard chrome switched to ASCII so it works on minimal-font terminals.
- **v1.1.x** — Network section split into independent public-IP / internal-interfaces toggles with multi-select of detected interfaces.
- **v1.0.x** — First stable release. CI passes (`shellcheck` + `bash -n` + e2e smoke test). Installer disables every script in `/etc/update-motd.d/` so newer Ubuntu defaults don't leak under the banner.
- **v0.5.0** — `smart-motd doctor` diagnostic. New sections: VPN, NTP, storage arrays.
- **v0.4.x** — Paged wizard with viewport scrolling, 20 themes, 13 color palettes, RU translations, `smart-motd upgrade`.
- **v0.3.x** — Caching for heavy sections (security / docker / podman / k8s), bilingual wizard.
- **v0.2.0** — Paged interactive wizard with live previews; theme system.
- **v0.1.0** — Initial cross-distro release.

---

## License

[MIT](LICENSE)
