# Changelog

All notable changes to smart-motd are listed here.
The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
