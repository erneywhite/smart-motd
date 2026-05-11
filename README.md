# smart-motd

A customizable, modular **MOTD** (message of the day) for Linux servers — the banner you see right after `ssh user@host`.

Cross-distro (Debian / Ubuntu / RHEL / CentOS / Rocky / Alma / Fedora / Arch / openSUSE / Alpine), pure-bash, no runtime dependencies beyond what your distro already ships. One `curl … | sudo bash`, a paged interactive wizard with live previews, and you're done.

[![CI](https://github.com/erneywhite/smart-motd/actions/workflows/ci.yml/badge.svg)](https://github.com/erneywhite/smart-motd/actions/workflows/ci.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-blue)
![Version](https://img.shields.io/badge/version-v1.12.0-brightgreen)
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
 OS         : Ubuntu 22.04.3 LTS
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
----------------------- Weather -----------------------
   Berlin: ☀ +21°C, Sunny
-------------------------------------------------------

 ↑ smart-motd v1.6.0 available (you have v1.5.4) — run sudo smart-motd upgrade
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
- **Optional Telegram SSH-login alerts** — get a notification with user / IP / rDNS / hostname / timestamp on every login. Bot token stored root-only; English or Russian message language; IP whitelist (CIDR-aware) to suppress alerts for your own home/office/VPN ranges; optional once-a-day recap with login counts + pending updates + reboot status. PAM-hooked, runs in the background so login is never delayed.
- **Cross-distro install** — the installer detects your distro family and wires into the right hook automatically (`/etc/update-motd.d/` for Debian-family, systemd timer → `/etc/motd` for RHEL/openSUSE/Arch, cron fallback for Alpine).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/erneywhite/smart-motd/main/install.sh | sudo bash
```

The installer:

1. Detects your distro family and installs missing prerequisites (`curl`, `tar`, `awk`).
2. Drops the runtime into `/usr/local/lib/smart-motd/` and a CLI at `/usr/local/bin/smart-motd`.
3. Wires it into the right place for your distro:
   - **Debian / Ubuntu**: `/etc/update-motd.d/01-smart-motd`. Every other script in `/etc/update-motd.d/` and `/etc/motd.d/` is disabled (chmod -x), so the distro's default `landscape-sysinfo`, `motd-news`, ESM-announce, etc. don't leak under our banner.
   - **Everything else**: a systemd timer that renders the banner into `/etc/motd` every 5 minutes (cron fallback if no systemd).
4. Sets up a 5-minute systemd timer (`smart-motd-cache.timer`) to refresh expensive data sources.
5. Drops you into the interactive wizard so you can pick sections, theme, and color palette.

To skip the wizard during install (e.g. for Ansible / cloud-init):

```bash
curl -fsSL https://raw.githubusercontent.com/erneywhite/smart-motd/main/install.sh | sudo bash -s -- --no-setup
```

## Usage

```
smart-motd show                       # preview the MOTD right now
smart-motd watch [SEC]                # re-render every SEC seconds (default 5)
sudo smart-motd setup                 # re-run the interactive wizard
sudo smart-motd update-cache          # refresh cached values immediately
sudo smart-motd edit                  # open the config in $EDITOR
smart-motd config get [KEY]           # print one value (or full config)
sudo smart-motd config set KEY VAL    # set one scalar value without re-running setup
sudo smart-motd test-alert [ssh|recap] # fire a Telegram alert right now
smart-motd status                     # show install paths and cache freshness
smart-motd doctor                     # diagnose the install
smart-motd benchmark [N]              # time each section to spot slow ones (N iters, default 3)
smart-motd version                    # installed version + check for updates
sudo smart-motd upgrade               # pull and install the latest release
sudo smart-motd uninstall             # remove smart-motd
```

If the login banner ever stops looking right, `smart-motd doctor` runs through every wired component (config, cache files, distro hook, systemd timers, `/run/motd.dynamic` freshness, generator dry-run, GitHub reachability) and reports each as `✓` / `!` / `✗` with a hint on how to fix it.

## What it shows

Each section is independent and can be turned on/off in the config (or via the wizard's first page).

| Section | What it shows | Notes |
|---|---|---|
| **Header** | Custom banner text | Letter spacing, UPPER, lower, plain styles |
| **Welcome** | Server title + custom KV lines (URLs, admin, …) | |
| **Warning** | Legal / authorized-access notice | |
| **System status** | Hostname, OS (Ubuntu 22.04 / Debian 12 / …), uptime, load, memory, disk(s), sessions | Mountpoints autodiscovered via `df`; OS pulled from `/etc/os-release` |
| **Maintenance** | "Reboot required" notice | Detects Debian flag, RHEL `needs-restarting` |
| **Package updates** | Pending updates, security count | apt / dnf / yum / zypper / pacman / apk |
| **Services** | Configured systemd units + status | `active` / `failed` / `inactive`; multiselect autodiscover |
| **Network** | Public IP, internal interface IPs, optional rx/tx rate per interface | Three independent toggles; interface multiselect; 5-min averaged rate |
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
| **Directories** | Custom labeled paths with sizes; optional backup-age annotation | E.g. backups, big project dirs; backup-flagged entries show `newest: Nh ago` color-coded by staleness |
| **Recent logins** | Last N successful logins | |
| **Weather** | One-line wttr.in summary | Off by default; auto-detects your city via IP |
| **Telegram SSH alerts** | (not visible in MOTD) Sends a Telegram message on every SSH login | Off by default; PAM-hooked; bot token in root-only `/etc/smart-motd/secrets.conf`; EN/RU message language |
| **Upgrade notice** | One-line "↑ smart-motd vX.Y.Z available" at the bottom when a newer release is published | Always on (system parameter, can't be disabled). Checked via GitHub API in the cache job; nothing shown when up-to-date |

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

### A note on fonts

The wizard chrome itself (cursor, scroll indicators, checkboxes, navigation hints) only uses widely-supported ASCII characters — `>`, `^`, `v`, `[x]`, `[ ]` — so it works in any terminal regardless of font.

The **theme presets** are a different matter. Themes like `stars` (`★`), `arrows` (`▶ ▸ →`), `chevrons` (`» «`), `sharp` (`◢ ◣ ◆`), `cosmic` (`◇`) need a Unicode-rich font on **your local terminal application** (iTerm2, Alacritty, Kitty, Windows Terminal, gnome-terminal, …). If you see `■` rectangles instead of the intended characters, your local terminal's font lacks those glyphs.

The font lives on your **client**, not the server — installing fonts via `apk`/`apt` on the box you ssh INTO doesn't help, because what you're seeing is rendered by the program running on your laptop. Common ways to fix it:

- macOS Terminal.app / iTerm2: install [JetBrainsMono Nerd Font](https://www.nerdfonts.com/) or any "Mono Nerd Font" variant.
- Windows Terminal: same — install a Nerd Font and set it in your profile.
- Linux gnome-terminal / kitty: install `fonts-firacode` / `ttf-jetbrains-mono-nerd` and pick it.

**Exception — VNC / RDP / xrdp**: when you connect to a remote desktop session and open a terminal inside it, the terminal program is running on the **server**, so the fonts that matter are *server-side* in that case. Install Nerd Fonts on the server (`apt install fonts-jetbrains-mono`, `zypper install nerd-fonts-jetbrains-mono-fonts`, etc.) and re-launch the session. Same applies to logging into the local TTY console directly (`tty1`–`tty6`) — fonts come from `console-setup` / `kbd`.

Or just stick to the ASCII-friendly themes that work everywhere: `classic`, `slim`, `double`, `ascii`, `pipes`, `retro`, `compact`.

## Telegram SSH login alerts

`smart-motd` can fire a Telegram notification on every successful SSH login:

```
🔓 SSH login
👤 User: root
🌐 IP: 198.51.100.42
🌐 rDNS: client.example.net
🖥 Server: web-01.example.com (203.0.113.42)
🕐 2026-05-08 22:12:46 UTC
```

**Setup**: tick "Telegram SSH login alerts" in the wizard's first multiselect, then on the configuration page:
- **Bot token** — create one via [@BotFather](https://t.me/BotFather) (`/newbot`, copy the API token).
- **Destination type** — pick "Personal chat (DM)" if you want the bot to message you directly, or "Group / channel" if it should post to a shared chat. The follow-up question changes accordingly.
- **Chat / user ID** — get yours by sending `/start` to [@userinfobot](https://t.me/userinfobot). Your own user ID is positive; group / channel IDs are negative (e.g. `-1001234567890`). For personal chats: open the bot in Telegram and press `/start` once first — bots can't initiate DMs.
- **Thread ID** (groups only, optional) — if your group has Topics enabled and you want alerts in a specific topic.
- **Alert language** — `en` or `ru`, independent from the wizard language.
- **IP whitelist** — list of IPs / CIDR blocks that DON'T trigger an alert (e.g. your own home/office/VPN ranges). Optional.
- **Daily recap** — opt-in once-a-day summary message (logins / failed attempts / pending updates / reboot status / uptime + 24h-averaged load and memory + root disk usage).
- **Additional destinations** — optional list of extra `token|chat|thread` tuples. Every alert is sent to the primary destination AND to each extra one in parallel. Useful for managed-services contexts (you + a client both get the same alert from different bots).
- **Test send** — the wizard offers to send a test message before saving the config. You can also fire one any time via `sudo smart-motd test-alert [ssh|recap]`.

**Mechanism**: a single `session optional pam_exec.so /usr/local/lib/smart-motd/bin/motd-ssh-alert` line is appended to `/etc/pam.d/sshd` at install time. Backup of the original goes to `/etc/pam.d/sshd.smart-motd.bak`. The handler script does an rDNS lookup with a 3 s timeout and fires the Telegram POST in a detached background subshell — login is **not** delayed by the network call.

**Security**:
- Bot token + chat ID + thread ID live in `/etc/smart-motd/secrets.conf` with mode `0600` (root-only) — `config.conf` stays world-readable without leaking credentials.
- The PAM hook is `optional`, so even if `pam_exec` somehow fails, your SSH session still proceeds.
- `smart-motd uninstall` removes the PAM line and the secrets file cleanly.

**Caveats**:
- Editing `/etc/pam.d/sshd` is invasive — back up your config separately if you have a custom PAM stack. The installer keeps a `.smart-motd.bak` of the file before its first edit.
- The hook fires on every successful authentication including `sftp`/`scp` if your sshd allows them. To filter on shell logins only you'd need additional checks inside `motd-ssh-alert`.

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
| RHEL / CentOS / Rocky / Alma / Fedora | `dnf` / `yum` | systemd timer → `/etc/motd` | ✅ Rocky 9, CentOS 10 |
| openSUSE | `zypper` | systemd timer → `/etc/motd` | ✅ openSUSE Leap 15.6 |
| Arch / Manjaro | `pacman` | systemd timer → `/etc/motd` | ✅ Arch, Nyarch |
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

Removes the install dir, binaries, systemd units, cron entries, and the `update-motd.d` hook. Re-enables every script in `/etc/update-motd.d/` and `/etc/motd.d/` that the installer disabled, so the distro's original banner is fully restored. Leaves `/etc/smart-motd/` so you can re-install without losing your config — wipe it manually if you want a clean slate.

## Contributing

PRs welcome. The codebase is intentionally small:

```
bin/
  motd-generate         # main entry, sources sections in order
  motd-cache-update     # refreshes cached snippets (and /run/motd.dynamic on Debian)
  motd-setup            # paged interactive wizard
  motd-doctor           # diagnostic command (smart-motd doctor)
  motd-uninstall
  smart-motd            # CLI wrapper
lib/
  common.sh             # colors, theme presets, distro detect, formatting
  cache.sh              # cache writers (heavy queries live here)
  wizard.sh             # paged-UI primitives (text/yesno/select/multiselect/list/preview)
  sections/             # one .sh per visible section
systemd/
.github/workflows/      # shellcheck + bash -n + e2e smoke test on every PR
install.sh              # curl|sudo bash entrypoint
config.example.conf
CHANGELOG.md
```

Adding a new section is one file in `lib/sections/`. See the existing ones (e.g. [`services.sh`](lib/sections/services.sh)) for the pattern.

Adding a new theme is a `case` arm in [`lib/common.sh`](lib/common.sh) inside `apply_theme`, plus one entry in the wizard's `wizard_select_preview` call. Same for color palettes in `apply_color_theme`.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full history.

Highlights:

- **v1.12.0** — Reboot-required indicator in the Package updates block (cross-distro: Debian/Ubuntu file marker, openSUSE marker + `zypper needs-rebooting`, RHEL/Fedora `dnf needs-restarting -r`). SSL auto-detect grep's nginx / apache configs so panels (ISPmanager, aaPanel, FastPanel, HestiaCP, Plesk, …) work out of the box — the wizard offers a multi-select over every detected cert. Opt-in `SERVICES_SHOW_FAILED=true` surfaces any unit in the failed state, even if it's not on your explicit list. New `smart-motd benchmark` diagnostic times every section so you can spot slow ones.
- **v1.11.0** — Multiple Telegram destinations: one alert can now go to N (bot, chat, thread) tuples at once. Useful for managed-services contexts where the same login alert needs to land in your own chat *and* a client's chat.
- **v1.10.0** — Backup-age annotation in Monitored directories. Flag an entry as `|backup` and the MOTD shows the age of the newest file inside, color-coded by staleness (`newest: 2h ago` = green, ≥2d yellow, ≥7d or empty red).
- **v1.9.x** — Two new CLI commands: `sudo smart-motd test-alert [ssh|recap]` fires a Telegram alert immediately for verification, and `smart-motd config get/set KEY [VALUE]` for surgical edits without re-running the wizard. Also fixed a `cp`-vs-running-script race during upgrade.
- **v1.8.x** — Upgrade flow no longer auto-launches the wizard. Instead it prints the CHANGELOG entry for the new version + a single Re-setup status line (`✓ No re-setup needed` / `↪ Optional` / `⚠ Recommended`) parsed from a `**Re-setup:**` marker in each release entry.
- **v1.7.x** — Daily Telegram recap now includes average load + memory (24-hour rolling) and root disk usage. Cache job collects 5-min samples for the moving average.
- **v1.6.x** — Passive upgrade notice at the bottom of the MOTD when a newer release is published on GitHub (system parameter, always on, hidden when up-to-date). Sanity-check + post-install cache reset so no false-positive right after `smart-motd upgrade`.
- **v1.5.x** — Telegram alert IP whitelist (CIDR-aware), `smart-motd watch [SEC]` for live re-render with alt-screen, opt-in once-a-day Telegram recap (logins / failed attempts / pending updates / reboot status / uptime). Personal-chat-or-group destination picker. Server identity in alerts now uses kernel `hostname` + primary-interface IP — works correctly behind NAT and on cloud VMs where DNS-resolved FQDN returns auto-generated junk.
- **v1.4.x** — Telegram SSH-login alerts with PAM-hook + bilingual messages (en/ru) + test-send in the wizard. Bash tab completion. Setup wizard preserves existing config / credentials on re-runs (no more Enter-mashing wipe).
- **v1.3.x** — Per-interface rx/tx byte rate (5-min averaged) in the Network section, with column alignment. Installer hardened for Docker / chroot environments and for hosts with a non-coreutils `install` binary in `$PATH`.
- **v1.2.0** — OS line in System status (`Ubuntu 22.04.3 LTS` / `Debian GNU/Linux 12` / …). Wizard chrome switched to ASCII so it works on minimal-font terminals.
- **v1.1.x** — Network section split into independent public-IP / internal-interfaces toggles with multiselect of detected interfaces. Fixed a latent bash empty-array bug that was silently hiding internal interface IPs since v0.1.0.
- **v1.0.x** — First stable release. CI passes (`shellcheck` + `bash -n` + e2e smoke test). Installer now disables EVERY script in `/etc/update-motd.d/` (not just six hard-coded names), so newer Ubuntu defaults like `landscape-sysinfo` and `esm-announce` no longer leak under the banner.
- **v0.5.0** — `smart-motd doctor` diagnostic command. New sections: VPN (WireGuard / OpenVPN), Time sync (NTP), Storage arrays (mdadm / ZFS).
- **v0.4.x** — Paged wizard with viewport scrolling, 20 themes, 13 color palettes, RU translations, `smart-motd upgrade`, Ctrl+C exits cleanly.
- **v0.3.x** — Login color force, cache the four heaviest sections (security/docker/podman/k8s), bilingual wizard.
- **v0.2.0** — Paged interactive wizard with live previews; theme system.
- **v0.1.0** — Initial cross-distro release.

## License

[MIT](LICENSE)
