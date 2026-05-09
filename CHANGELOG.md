# Changelog

All notable changes to smart-motd are listed here.
The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.6.0]

### Added — passive upgrade notice
- New section `upgrade_notice` (last in `SECTION_ORDER`) shows
  a single line at the bottom of the MOTD when a newer
  smart-motd release is published on GitHub:
  ```
   ↑ smart-motd v1.6.0 available (you have v1.5.4) — run sudo smart-motd upgrade
  ```
  Renders nothing when up-to-date, network is unavailable, or
  the local install is somehow ahead of the published release.
- New `cache_update_version_check` cache step. Runs every 5
  minutes alongside the other cache jobs, hits
  `https://api.github.com/repos/erneywhite/smart-motd/releases/latest`,
  compares to the local `VERSION` file with natural-version
  sort (`sort -V`), and writes the newer-version string to
  `/var/cache/smart-motd/upgrade_available`. Network failures
  preserve the previous cache value (no false "up-to-date"
  flicker from a transient curl error).
- Toggle in the wizard's first multiselect, default on.
  Disable in `/etc/smart-motd/config.conf` with
  `UPGRADE_NOTICE_ENABLED=false` if you'd rather check via
  `smart-motd version` manually.

## [1.5.4]

### Fixed
- Hostname resolution preferred `hostname -f` over `hostname`,
  but on cloud / NAT'd hosts `-f` does a DNS lookup that
  returns generic auto-generated names (e.g.
  `server-XXXXXX.localdomain`) instead of what the operator
  actually set via `hostnamectl set-hostname` / `/etc/hostname`.
  Example:
  ```
  $ hostname        # what the operator set
  web-01.example.com
  $ hostname -f     # what DHCP / cloud-init resolved
  server-XXXXXX.localdomain
  ```
  Switched to plain `hostname` everywhere (System status section,
  Telegram alerts, daily recap) so the operator's actual chosen
  hostname is what shows up. `hostname -f` is now only the
  fallback when `hostname` itself fails (essentially never).

## [1.5.3]

### Changed
- Server-IP detection in alert messages now prefers the local
  primary-interface IP (from `ip route get 1.1.1.1`) over the
  cached public IP. For servers behind NAT (home boxes, cloud
  VMs without a public IP attached, k8s nodes …) the public IP
  is the gateway's address — the same for every server behind
  that NAT, so it can't tell them apart. The local interface
  IP correctly identifies each individual server. The cached
  public IP is now only used as a last-resort fallback when
  the `ip` binary isn't available.

## [1.5.2]

### Changed
- Telegram alerts (per-login + daily recap) now show the server's
  full hostname plus its outward-facing IP in parentheses, instead
  of just `hostname -s`. Useful when you have several servers and
  want to identify the source of an alert at a glance:
  ```
  before:  🖥 Сервер: web
  after:   🖥 Сервер: web.example.com (203.0.113.42)
  ```
  IP source priority: `/var/cache/smart-motd/public_ip` (whatever
  the periodic cache job last fetched), then `ip route get
  1.1.1.1` (kernel routing-table source IP for the public default
  route — no actual traffic generated). If neither resolves, just
  the hostname is shown.

## [1.5.1]

### Changed
- Telegram credentials wizard now starts with a "Where should
  the alerts go?" picker — Personal chat (DM) or Group / channel.
  The follow-up prompt is contextual:
    · Personal — asks for the operator's user ID with a reminder
      that they must `/start` the bot first (otherwise the bot
      can't initiate DMs).
    · Group / channel — asks for the negative chat ID with bot-
      adding instructions, plus the optional thread ID for groups
      with Topics enabled.
  The thread-ID question is suppressed entirely for personal
  chats (they don't have threads). On re-runs the picker
  defaults to whatever type the saved chat ID implies (negative
  → group, positive → personal), so hitting Enter keeps the
  current setup.

## [1.5.0]

### Added

- **IP whitelist for Telegram SSH alerts** — new
  `TELEGRAM_ALERTS_IP_WHITELIST` array. Each entry is either a
  single IPv4 (`203.0.113.5`) or a CIDR block (`192.168.1.0/24`,
  `10.0.0.0/8`). Logins from matching addresses silently skip
  the Telegram notification. Useful for suppressing alerts about
  your own home / office / VPN IPs without losing visibility on
  external logins. Wizard adds a list-editor page.
- **`smart-motd watch [SEC]`** — re-renders the MOTD every SEC
  seconds (default 5). Uses an alternate-screen buffer
  (`\e[?1049h`) so your scrollback isn't filled with snapshots,
  and restores the cursor + scrollback on Ctrl+C. Handy for
  monitoring on a side terminal / dashboard.
- **Daily Telegram recap** — opt-in once-a-day summary message
  with the last 24h's SSH logins, failed-auth count, pending
  package updates (incl. security count), reboot-required flag
  and uptime. Configurable hour-of-day. Bilingual (en/ru, same
  pref as alerts). Triggered from the cache-refresh job at the
  matching hour, with a state file to guarantee at-most-once
  delivery per day.

## [1.4.2]

### Fixed
- Setup wizard didn't load `/etc/smart-motd/secrets.conf` on
  re-runs, so the Telegram bot-token / chat-ID fields rendered
  empty even when credentials were already saved. Hitting Enter
  through them then silently overwrote the saved values with
  empty strings, breaking alerts. Now secrets are loaded along
  with config.conf at the top of the wizard, so existing values
  pre-fill correctly via `read -e -i`.

### Added — fewer Enter-mashings on re-runs
- **Top-level skip gate**: when an existing config is detected
  (i.e. you're re-running setup, typically after `smart-motd
  upgrade` re-launches the wizard), the wizard now asks "Edit
  existing configuration?" right after the language picker.
  Default is **No** — Enter exits cleanly without any changes.
  Pick Yes to walk through every page as before.
- **Telegram credentials gate**: inside the Telegram config
  page, when bot token + chat ID are already saved, the wizard
  asks "Edit Telegram credentials?" first. Default **No** skips
  the token / chat / thread prompts and jumps straight to the
  language picker + test send (so you can verify alerts still
  work, or change message language, without retyping creds).

## [1.4.1]

### Added
- Bash tab completion for `smart-motd <subcommand>`. Type
  `smart-motd <TAB>` to see all commands; `smart-motd s<TAB>`
  cycles through `show / setup / status`. Installed to
  `/usr/share/bash-completion/completions/smart-motd` (or
  `/etc/bash_completion.d/smart-motd` if the modern dir doesn't
  exist). Activates in any new shell — no manual sourcing needed.
  Also works in zsh sessions that have run `bashcompinit`.

## [1.4.0]

### Added — Telegram SSH login alerts
- New opt-in feature: send a Telegram notification on every
  successful SSH login. Format matches the example from the
  feature request:
  ```
  🔓 SSH login   (or "🔓 SSH вход на сервер" in Russian)
  👤 User: root
  🌐 IP: 203.0.113.42
  🌐 rDNS: client.example.net
  🖥 Server: web-01
  🕐 2026-05-08 22:12:46 UTC
  ```
- Hooked into PAM via a single `session optional pam_exec.so …`
  line appended to `/etc/pam.d/sshd` (with a `.smart-motd.bak`
  backup taken before any edit). The handler script
  `bin/motd-ssh-alert` reads its config, does an rDNS lookup with
  a 3-second timeout, and fires the Telegram POST in a detached
  background subshell — login is never delayed.
- Wizard adds a checkbox to the section multiselect (placed
  right before Weather) and a configuration page collecting the
  bot token, chat ID, optional thread ID, and message language
  (independent of wizard language — you can configure in English
  but receive alerts in Russian, or vice versa). A "send a test
  message now?" prompt before the config is saved verifies the
  credentials work end-to-end.
- Bot token and chat ID live in a separate
  `/etc/smart-motd/secrets.conf` with mode 0600 (root-only).
  `config.conf` stays world-readable without leaking credentials.
- The PAM hook is always wired at install time (so users can
  enable alerts later via `sudo smart-motd setup` without
  re-touching pam.d). The handler script is a no-op when
  `TELEGRAM_ALERTS_ENABLED=false`, so zero overhead for users
  who don't enable the feature.
- `smart-motd uninstall` strips the hook line back out of
  `/etc/pam.d/sshd` and removes `secrets.conf` (credentials are
  not left lying around).

## [1.3.3]

### Fixed
- Installer aborted in Docker / chroot environments where the
  `systemctl` binary exists and `/etc/systemd/system/` is present
  but systemd is NOT running as PID 1. The crash looked like:
  ```
  System has not been booted with systemd as init system (PID 1).
  Failed to connect to system scope bus via local transport: Host is down
  ```
- Now the installer probes for `[[ -d /run/systemd/system ]]` —
  the canonical "systemd is currently up" marker — instead of
  the install-time-only `/etc/systemd/system/` directory. When
  systemd isn't actually running it falls through to the cron
  fallback (or, if cron isn't there either, prints a clear
  "no scheduler — refresh /etc/motd manually" warning).
- All `systemctl` invocations also now have non-fatal error
  handling (`|| warn …`) so a single failure doesn't abort the
  whole install. `motd-uninstall` and `motd-doctor` got the same
  guard.

## [1.3.2]

### Fixed
- Installer crashed on Arch Docker images (and any other host where
  `install` in `$PATH` resolves to something other than GNU coreutils
  — some AUR helpers, certain Cobra-based Go tools, etc. ship a
  binary called `install` that takes "install [PACKAGE...]" instead).
  Replaced every `install -m MODE SRC DST` in install.sh with a tiny
  `_inst` wrapper that does `cp -f` + `chmod` — no PATH lookup, works
  on any POSIX system.

## [1.3.1]

### Changed
- Network rate labels switched from `rx`/`tx` to ↓/↑ — more
  intuitive at-a-glance ("down arrow = traffic INTO the host",
  "up arrow = traffic OUT").
- IP and rate columns now right-padded (IP to 16 chars, rate
  to 10) so the rate values line up across interfaces regardless
  of IP length or magnitude. Previously the columns drifted
  whenever one interface had a long IP and another a short one,
  or one rate was in B/s and another in MB/s.

## [1.3.0]

### Added
- Network section can now show the rx/tx byte rate next to each
  interface's IP, averaged over the cache window (5 minutes by
  default). Output looks like:
  ```
   eth0       : 10.0.0.5  rx 12.3 KB/s  tx 4.5 KB/s
   wg0        : 10.8.0.1  rx 1.2 KB/s   tx 0.8 KB/s
  ```
  Rates are computed by snapshotting `/sys/class/net/<iface>/statistics/`
  on each cache run and diffing against the previous snapshot, so
  the on-login path stays free. New `NETWORK_SHOW_RATES` toggle
  (default `true`); a setup-wizard question lets you opt out.
  Auto-formats as B/s / KB/s / MB/s / GB/s. Counter resets clamp
  to 0. First cache cycle after install shows IP only — rates
  appear after the second tick (~5 minutes later).

## [1.2.0]

### Added
- System status section now shows the OS line right under
  Hostname (e.g. `Ubuntu 22.04.3 LTS`, `Debian GNU/Linux 12
  (bookworm)`, `openSUSE Tumbleweed`) — pulled from
  `/etc/os-release` `PRETTY_NAME`. Skipped silently on hosts
  without that file (i.e. nothing weird shown on macOS / BSD).

### Changed
- Wizard chrome (cursor pointer, scroll indicators, checkbox
  marks, navigation hints) switched from fancy Unicode glyphs
  (`❯` `↑` `↓` `✓`) to widely-supported ASCII (`>` `^` `v` `[x]`).
  Stock fonts on some distros (e.g. openSUSE's TTY default) lack
  the Misc-Symbols / Arrows blocks and rendered every fancy char
  as a `■` placeholder. The wizard itself no longer depends on
  font richness.
- Theme presets (`stars`, `arrows`, `chevrons`, `cosmic`, `sharp`)
  still use their fancy Unicode chars by design — they're an
  explicit visual choice. README now has a new "A note on fonts"
  section explaining the issue and pointing at Nerd Fonts as the
  fix on the operator's local terminal.

## [1.1.1]

### Fixed
- Network section never showed internal interface IPs when
  `NETWORK_INTERFACES` was empty (the default for "All interfaces"
  mode). Root cause: `("${arr[@]:-}")` for an empty source array
  expands to a single empty-string element — NOT an empty array —
  so the filter loop matched nothing and silently hid every
  interface. Latent bug since v0.1.0; only became visible with the
  v1.1.0 wizard prompt that introduced "All interfaces (auto)" as
  a deliberate choice. Fixed by guarding with
  `[[ ${#arr[@]} -gt 0 ]]` before populating the filter.

## [1.1.0]

### Added
- Network section now has an explicit yes/no toggle for showing
  internal interface IPs, separate from the public-IP toggle. The
  setup wizard asks both questions, and if interfaces are enabled
  it follows up with a multiselect of detected interfaces (with
  the IPv4 each one carries shown next to its name) plus an
  "All interfaces (auto)" option that shows every non-loopback
  interface (including future ones added after setup).
- New `NETWORK_SHOW_INTERFACES` config var. Empty `NETWORK_INTERFACES`
  + `NETWORK_SHOW_INTERFACES=true` means "show every non-loopback
  interface"; populated `NETWORK_INTERFACES` filters down to the
  listed ones; `NETWORK_SHOW_INTERFACES=false` hides the interface
  list entirely (useful for cluttered hosts where Docker/k8s/VPN
  add a dozen virtual interfaces).
- The Network section now skips its heading entirely when both
  toggles are off, instead of rendering an empty box.

## [1.0.1]

### Fixed
- Default Ubuntu MOTD scripts (`50-landscape-sysinfo`,
  `88-esm-announce`, `90-updates-available`, etc.) were leaking
  underneath our banner because the installer's hard-coded disable
  list only covered six specific scripts. Replaced with a glob that
  disables every existing script in `/etc/update-motd.d/` except
  `01-smart-motd` itself, so this is future-proof against new Ubuntu
  releases adding more scripts. Also clears executable bits from
  `/etc/motd.d/*` (some releases route through there).
- `motd-uninstall` now blanket-re-enables every script in
  `/etc/update-motd.d/` and `/etc/motd.d/`, so removing smart-motd
  cleanly restores the distro's original banner.

## [1.0.0]

First stable release. No new features versus v0.5.1 — this tag just
marks the project as production-ready. The codebase has been smoke-
tested end-to-end on Debian/Ubuntu in CI and battle-tested on a real
production server through every iteration.

### Fixed
- `lib/sections/docker.sh` case order: `*healthy*` matched before
  `*unhealthy*`, so unhealthy containers were rendered green. The
  unhealthy case is now checked first.
- `lib/wizard.sh` `_wiz_cols()` had two competing stderr redirects
  (`2>/dev/tty 2>/dev/null`) — only the second one was effective.
  Cleaned up to a single `2>/dev/null`.
- `bin/motd-setup` services-page case had two patterns (`systemd-*`
  and `systemd*`) where the second was dead code, plus `init.scope`
  was masked by `*\.scope`. Pruned both.
- CI uses `actions/checkout@v5` (v4 was deprecated by GitHub).

## [0.5.0]

### Added
- `smart-motd doctor` — diagnoses the install: checks runtime files,
  config syntax, cache freshness, distro hook, systemd timer state,
  `/run/motd.dynamic` age (Debian), generator dry-run, and GitHub
  reachability. Exits 1 if any error is found, so it's safe to wrap
  in monitoring.
- `lib/sections/vpn.sh` — WireGuard interfaces (peer count, recent
  handshakes) and OpenVPN systemd units. WireGuard data is cached
  because `wg show` requires root.
- `lib/sections/ntp.sh` — time sync status via `timedatectl`,
  `chronyc tracking`, or `ntpq -p` (whichever is installed).
  Shows server, offset, and sync state.
- `lib/sections/raid.sh` — mdadm arrays from `/proc/mdstat` (live)
  and ZFS pools from `zpool list` (cached, since scrubs make it slow).
  Color-coded by health state.
- The new sections appear in the wizard's first multiselect with
  proper auto-detection — VPN is only pre-checked if `wg` or any
  `openvpn*.service` exists, RAID only if `/proc/mdstat` has arrays
  or `zpool` is present, NTP only if a sync daemon is detected.

## [0.4.5]

### Added
- `sudo smart-motd upgrade` — re-runs the installer in place. No
  more copy-pasting the curl one-liner from the version output.

### Fixed
- Ctrl+C in the wizard / installer now actually exits. The previous
  trap restored the cursor but didn't `exit`, so bash kept going.

## [0.4.4]

### Fixed
- Wizard viewport off-by-one: when scrolling into a long list and
  the "↑ N more above" indicator appeared, the title bar would
  scroll off the top of the screen because the trailing footer
  newline pushed content past the visible area.

## [0.4.3]

### Added
- Version display in the wizard top bar (`smart-motd setup · v0.4.3`).
- `smart-motd version` checks GitHub for newer releases and prints
  either "✓ up to date" or "↑ newer version available: vX.Y.Z".
- `smart-motd status` now prints the version header.
- `Press Enter to launch interactive setup` pause after the
  installer summary, so the operator can read what was wired up.

### Fixed
- Wizard scrolling no longer flickers — `tput`, `_wrap | wc -l`
  and the step-counter tmpfile were being read on every keypress.
  Cached once per page.
- Installer banner box auto-pads each content line to the longest
  one. Right `│` always lines up.

## [0.4.2]

### Added
- Viewport scrolling in the wizard: long lists (themes, services)
  scroll inside the wizard chrome with `↑ N more above` /
  `↓ N more below` indicators instead of relying on the user's
  terminal scrollback.
- Installer redesign: ASCII-banner box, colored step markers
  (`▸` `✓` `!` `✗`), final summary block with install paths and
  the four most useful CLI commands.

### Fixed
- `directories` section: sizes padded to a fixed width so the path
  column lines up regardless of size length (4.0K vs 32K vs 1.2G).

## [0.4.1]

### Fixed
- UTF-8 wrap bug: replaced `fold -s -w` (counts BYTES, breaks
  Cyrillic and box-drawing chars mid-sequence) with a pure-bash
  word wrapper. Fixes the "garbled glyphs / question marks" in the
  wizard intro and help text.
- `wizard_text` / `wizard_password` / `wizard_intro` / `wizard_done`
  did not clear the screen tail before reading, so a previous
  multiselect or list editor would bleed through under the prompt.
- Step counter: `WIZ_STEP++` in subshell-invoked wizard functions
  never propagated to the parent. Switched to a tmpfile-backed
  counter that survives subshells.
- Long option labels overflowed past the right edge on narrow
  terminals; now truncated with `…`.

## [0.4.0]

### Added
- Flicker-free wizard: full-screen clear replaced with cursor-home
  + per-line clear-eol + trailing clear-tail. Content overwrites
  in place, no blank frame between renders.
- Service / mountpoint / weather-city autodiscover during setup.
  systemd unit list, `df` mountpoints, IP-based geolocation feed
  multiselect lists with current state shown.
- Seven new themes (chevrons, bullets, cross, plus, cosmic, sharp,
  zen) and seven new color palettes (matrix, neon, coral, mint,
  sky, gold, snow). Total: 20 themes, 13 palettes.
- First multiselect no longer pre-checks Docker/Podman/Kubernetes/
  SMART/temperature on hosts where the underlying tool isn't
  installed.

## [0.3.1]

### Fixed
- `/run/motd.dynamic` staleness on Ubuntu (login banner stale).
  The cache job now also regenerates `/run/motd.dynamic` from
  `/etc/update-motd.d/`.
- `services.sh` bad-substitution crash from invalid
  `${#arr[@]:-0}` syntax.
- Theme + KV-separator persistence across re-runs.
- Setup pages reordered so previews show the user's actual text.

## [0.3.0]

### Added
- Force ANSI colors at SSH login (pam_motd context isn't a TTY).
- Cached the four heaviest sections (security, docker, podman,
  kubernetes) so login stays under ~50 ms even on busy hosts.
- Seven additional themes.
- Bilingual setup wizard (EN / RU).

## [0.2.0]

### Added
- Paged interactive wizard with arrow-key navigation and live
  preview of each theme/style choice.
- Theme + color-theme system.

## [0.1.0]

Initial cross-distro release. Pure-bash MOTD generator with sections
for header / welcome / warning / system status / maintenance / package
updates / services / network / SSL / security / temperature / SMART /
docker / podman / kubernetes / monitored directories / recent logins /
weather. One `curl … | sudo bash` installer with auto-distro detection
(Debian / RHEL / Arch / openSUSE / Alpine).
