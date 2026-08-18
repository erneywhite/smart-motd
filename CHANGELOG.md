# Changelog

All notable changes to smart-motd are listed here.
The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.15.0]

**Re-setup:** optional.

### Added — login location in SSH alerts (`TELEGRAM_ALERTS_GEOIP`)
- Optional `Location: City, Country` line, resolved from the
  connecting IP:
  ```
  🔓 SSH login
  👤 User: root
  🌐 IP: 203.0.113.9
  🌍 Location: Amsterdam, Netherlands
  🖥 Server: web-01 (198.51.100.7)
  🕐 2026-08-18 09:28:17 EEST
  ```
- **Off by default.** Enabling it sends the source IP of every SSH
  login to a third-party lookup service, which is the operator's
  call to make rather than something to inherit silently on
  upgrade. Turn it on with:
  ```bash
  sudo smart-motd config set TELEGRAM_ALERTS_GEOIP true
  ```
  The wizard asks about it too, right after the IP whitelist.
- Private, loopback, link-local and CGNAT addresses are **never
  sent anywhere** — they're filtered locally before any request,
  since a public lookup could only return noise for them.
- Two keyless HTTPS providers are tried in order (ipwho.is, then
  ipapi.co). Parsing is generic rather than provider-specific, so
  swapping in another service is a URL change. If none answer,
  the line is simply omitted rather than printed as "unknown".

### Fixed — reverse DNS was running on the login path
- The alert script's rDNS lookup ran inline, before the message
  was composed, with a 3-second timeout. On a slow or black-holed
  resolver that delay was added to **every SSH login**, despite
  the script's own header promising it wasn't. Only the Telegram
  POST was actually backgrounded.
- Both enrichment steps (rDNS and the new geo lookup) now run
  inside the detached subshell, so pam_exec gets its exit
  immediately and the message is composed and delivered in the
  background. Logins are no longer held up by DNS at all.

## [1.14.0]

**Re-setup:** not required.

### Changed — the daily Telegram recap lists every disk
- The recap reported only `/`, so a data or backup volume filling
  up went unmentioned in the one message that exists to catch
  exactly that. On a host with three disks it said `Диск /: 66G /
  94G` and nothing about the 1.8 TB volume at 72%.
- It now lists every disk the MOTD lists:
  ```
  💾 Disk /: 66G / 94G (74% used)
  💾 Disk nvme0n1p1: 307G / 938G (35% used)
  💾 Disk sda1: 1.3T / 1.8T (72% used)
  ```
- This reverses a deliberate v1.7.1 decision to keep the recap to
  `/` alone. That was right at the time: extra entries were
  hand-configured paths like `/var`, which really was noise in a
  once-a-day glance message. Since v1.13.0 the list is
  auto-detected real block devices, which is exactly what belongs
  in a daily summary.
- `motd-recap` reuses `disks_prepare()` from the system section
  rather than running its own `df`, so there is one definition of
  "what counts as a disk" — same filters, same `SYSTEM_DISK_*`
  config, same labels. `SYSTEM_DISK_EXCLUDE` and `SYSTEM_DISK_MAX`
  apply to the recap too. Falls back to `/` alone if the section
  library isn't readable.

## [1.13.4]

**Re-setup:** not required.

### Added — SMART falls back when `smartctl --scan` guesses wrong
- `smartctl --scan` gets the transport wrong often enough to
  matter. A plain SATA disk in a USB enclosure was announced as
  ```
  /dev/sda -d sntjmicron # /dev/sda [USB NVMe JMicron], NVMe device
  ```
  and the recommended `sntjmicron` driver returned nothing at all
  — while generic `-d sat` reported the model, health **and**
  temperature without complaint. The drive wasn't an NVMe at all;
  the bridge just presents itself that way.
- Each device is now tried with the scan-suggested driver first,
  then `-d sat`, then `-d scsi`, stopping at the first that
  answers. Bounded at three attempts, and only devices that fail
  cost extra invocations — this runs in the 5-minute cache job,
  never on the login path.
- Enclosures that refuse SMART passthrough under every driver are
  still skipped cleanly, with no row of `?` in the banner.

## [1.13.3]

**Re-setup:** not required.

### Fixed — v1.13.2 hid the fail2ban line instead of warning
- v1.13.2 gated the whole line on `fail2ban-client ping`, so a
  host where the package is installed but the **daemon isn't
  running** showed nothing at all — strictly worse than the
  misleading green line it replaced, since the state is
  security-relevant and now went unmentioned.
- The three states are now told apart properly:
  | state | line |
  |---|---|
  | not installed | *(no line)* |
  | installed, daemon down | `installed but not running` (yellow) |
  | running, no jails | `running but NO jails configured` (red) |
  | running, N jails | `X banned across N jail(s)` (green/yellow) |
- "Installed but not running" is deliberately a yellow notice
  rather than a red alarm: it's ambiguous. It can mean the daemon
  was forgotten after a reboot, or that something else took over
  brute-force protection (a hosting panel's own module, for
  instance).
- Cache keys are now `FAIL2BAN_PRESENT` / `FAIL2BAN_RUNNING`,
  replacing v1.13.2's single `FAIL2BAN_INSTALLED`.

### Note — SMART over USB bridges
- v1.13.2 made smart-motd pass the `-d TYPE` that
  `smartctl --scan` recommends, which is required for drives in a
  USB enclosure. Some bridges still refuse the passthrough
  entirely and answer `Read NVMe Identify Controller failed`
  whatever driver is used — that's a limitation of the enclosure
  firmware, not something a MOTD can work around. Those devices
  are skipped cleanly rather than rendering a row of `?`.

## [1.13.2]

**Re-setup:** not required.

### Fixed — fail2ban with no jails rendered green
- A host running fail2ban with **zero jails configured** showed:
  ```
   SSH fails  ▸ 3886 in last 24h
   fail2ban   ▸ 0 banned across 0 jail(s)
  ```
  in **green** — the banner reported everything was fine on a box
  where brute-force attempts were entirely unmitigated. The jail
  list comes back as whitespace in that state, which passed the
  section's "is it non-empty" test while counting zero entries.
- Now reported as `running but NO jails configured` in red, and
  the section no longer hides itself when fail2ban is up but
  unconfigured on an otherwise quiet host.

### Fixed — disks behind a USB bridge vanished from SMART
- `smartctl --scan` names the driver each device needs:
  ```
  /dev/sda -d sntjmicron # /dev/sda [USB NVMe JMicron], NVMe device
  ```
  The scan output was parsed for the device path only and the
  `-d TYPE` was thrown away, so drives in a USB enclosure
  (JMicron, ASMedia, SunplusIT, Realtek) were queried plainly,
  failed with `Read NVMe Identify Controller failed: scsi error
  unsupported field in scsi command`, and silently disappeared
  from the section. The type is now carried through.
- `SMART_DISKS` entries accept the same `device|type` form for
  enclosures the scan can't work out on its own.

### Fixed — a failing disk could be hidden from SMART
- The per-disk query bailed on any non-zero exit from `smartctl`.
  That status is a **bitmask**, and bits are set for "disk is
  failing" and "prefail attribute below threshold" as well as for
  real errors — so the check dropped precisely the disks worth
  showing. Rows are now judged on whether the output is usable.

### Changed — motd-news is masked instead of left failing
- The installer disables every script in `/etc/update-motd.d/`,
  which makes `motd-news.service` fail the next time its timer
  fires and tries to exec the now non-executable
  `/etc/update-motd.d/50-motd-news`. v1.12.4 hid that from
  smart-motd's own Services list, but `systemctl --failed` and any
  external monitoring still saw a permanently failed unit that we
  caused.
- The unit and its timer are now stopped and masked at install
  time (Debian/Ubuntu, systemd hosts only), and `smart-motd
  uninstall` unmasks them again.

## [1.13.1]

**Re-setup:** not required.

### Changed — only real disks are listed now
- v1.13.0's auto list was still showing service mounts: `/boot`
  on hosts with a separate boot partition, and Proxmox's
  `/etc/pve` (a FUSE mount that always reads `24K / 128M`).
- The filter is no longer a list of filesystem types to reject.
  A row is now shown only when its source resolves to an actual
  **block device** — which is what "a disk" means, and what a
  type blacklist kept failing to express. `/etc/pve` is backed by
  `/dev/fuse`, a *character* device, so it drops out on the same
  rule that drops sshfs, rclone and lxcfs mounts. ZFS datasets
  get an explicit pass since they have a pool/dataset source
  rather than a device node.
- `/boot` and `/boot/*` are hidden by default now (v1.13.0 kept
  `/boot` deliberately; in practice it's noise on every banner).

### Changed — disk rows are labeled by device
- Rows other than `/` are now named after their device
  (`Disk sdb1`, `Disk nvme0n1p1`) instead of their mountpoint.
  Labels line up with `lsblk` and with the SMART section, they
  stay consistent from host to host, and mountpoints that make
  terrible labels stop leaking into the banner — panel paths like
  `/srv/dev-disk-by-uuid-<uuid>` and Proxmox's
  `/mnt/pve/<storage-id>`.
- Before / after on a Proxmox host:
  ```
  - Disk /             ▸ 60G / 90G (67% used)
  - Disk nvme0n1p1     ▸ 300G / 900G (33% used)
  - Disk /mnt/pve/data ▸ 1.2T / 1.8T (67% used)
  - Disk /etc/pve      ▸ 24K / 128M (1% used)
  + Disk /             ▸ 60G / 90G (67% used)
  + Disk nvme0n1p1     ▸ 300G / 900G (33% used)
  + Disk sda1          ▸ 1.2T / 1.8T (67% used)
  ```
- Mountpoints listed explicitly in `SYSTEM_DISK_PATHS` keep the
  path the operator typed as their label, and bypass every
  filter — that's the escape hatch for anything the sweep drops
  on purpose.

## [1.13.0]

**Re-setup:** optional.

### Fixed — the disk picker in the wizard detected nothing at all
- `motd-setup` built its mountpoint list with
  `df -P --output=target`, but GNU coreutils rejects that
  combination outright:
  ```
  df: options -P and --output are mutually exclusive
  ```
  The error went to `/dev/null`, so the list came back **empty**
  and the page only ever offered whatever was already in the
  config. That's why mounting a new disk and re-running the
  wizard didn't help — nothing was ever discovered, not even `/`.
- The detection now parses `df -PT` and filters on the filesystem
  *type* column.

### Added — disks are detected automatically (`SYSTEM_DISK_AUTO`)
- System status now lists **every local filesystem** by default.
  Mount a disk today and it shows up at the next login — no
  re-running the wizard, no config edit.
- Pseudo filesystems are filtered by type rather than by
  mountpoint glob, so every snap (`squashfs`), container layer
  (`overlay`), `tmpfs`, `devtmpfs`, `efivarfs`, … disappears
  without a path list to maintain.
- A disk mounted twice (bind mounts, btrfs subvolumes) is
  deduplicated by device and shown once.
- Network filesystems are skipped: `df` blocks indefinitely on a
  stale NFS/CIFS mount, and this runs on **every SSH login**.
  Mounts you do want are still listed explicitly via
  `SYSTEM_DISK_PATHS`, and the sweep is wrapped in `timeout`.
- `/` is always shown, including inside containers where the root
  filesystem is an overlay and would otherwise be filtered out.
- New knobs, all optional:
  - `SYSTEM_DISK_AUTO=true` — set to `false` for the old
    fixed-list behaviour.
  - `SYSTEM_DISK_PATHS=()` — extra mountpoints on top of the auto
    list (e.g. an NFS share); the complete list when auto is off.
  - `SYSTEM_DISK_EXCLUDE=()` — hide mountpoints, globs allowed.
    `/boot/efi`, `/boot/firmware`, snap and container mounts are
    always hidden. `/boot` is deliberately kept — a full `/boot`
    breaks kernel upgrades.
  - `SYSTEM_DISK_MAX=10` — cap, so a NAS with dozens of ZFS
    datasets can't flood the banner. Extra disks collapse into a
    `+N more` line.
- Existing configs keep working. `SYSTEM_DISK_PATHS` entries are
  merged in and deduplicated, so nothing you picked before
  disappears.

### Changed — readable labels for panel-style mountpoints
- Labels used to be the mountpoint truncated to 10 characters,
  which turned OpenMediaVault's
  `/srv/dev-disk-by-uuid-<uuid>` into a useless `Disk /srv/`.
  Now the label is the mountpoint when it's short and human
  (`Disk /mnt/backup`), and the device name when it isn't
  (`Disk sdb1`). `/` stays `Disk /`.
- The shared key/value column widens automatically when a host
  needs the room, so a long device name is shown **in full**
  (`Disk nvme0n1p2`) instead of being cut. Hosts with short names
  keep the current compact layout — the width is computed once,
  before anything renders, so every section stays aligned.

## [1.12.5]

**Re-setup:** not required.

### Removed — Alpine Linux support
- Alpine was only ever "best-effort", and real-world testing
  confirmed the install doesn't come together on it: Alpine
  ships **busybox login without PAM** (so the SSH login-alert
  hook has nothing to attach to) and **OpenRC instead of
  systemd** (so the cache and render timers don't apply).
- The installer now detects Alpine (`/etc/os-release` ID or
  `/etc/alpine-release`) and exits early with a clear message
  instead of leaving a half-working setup behind.
- Dropped the `apk` prerequisite branch, the `alpine`
  distro-family arm in both the installer and `lib/common.sh`,
  and the `apk version` package-count path in `lib/cache.sh`.
- Supported distros are now Debian, Ubuntu, RHEL / CentOS /
  Rocky / Alma, Fedora, Arch and openSUSE.

## [1.12.4]

**Re-setup:** not required.

### Fixed — `motd-news.service` showing as failed in the auto-list
- When `SERVICES_SHOW_FAILED=true`, Debian/Ubuntu hosts saw
  `failed  motd-news.service` in the Services section. That's a
  side effect of smart-motd's own install: we `chmod -x` every
  script in `/etc/update-motd.d/`, so `motd-news.service` fails
  the next time it tries to exec `/etc/update-motd.d/50-motd-news`.
  It's expected, not a real problem — but it looked alarming.
- `motd-news.service` is now always filtered out of the
  failed-unit auto-list (built-in default, no config needed).
- Added `SERVICES_FAILED_IGNORE=()` so you can suppress other
  noisy units too. Glob patterns are supported, e.g.
  `('systemd-fsck@*.service' 'phpsessionclean.service')`.

## [1.12.3]

**Re-setup:** not required.

### Fixed — wizard ignored action keys typed on a Russian keyboard layout
- Every wizard primitive (yes/no, select, multi-select, list) read
  keys with `read -rsn1` — exactly **one byte**. A Cyrillic
  character is two bytes in UTF-8, so when the operator had the
  Russian layout active and pressed e.g. `c` (which produces
  Cyrillic `с` — visually identical to Latin `c`), the wizard
  saw only the first byte (`0xD1`), matched no case branch, and
  silently did nothing. Same problem for `a` → `ф`, `d` → `в`,
  `e` → `у`, `j` → `о`, `k` → `л`, `n` → `т`, `y` → `н`.
- Added a `_wiz_readkey` helper that reads a full UTF-8 character
  (1-4 bytes, based on the leading byte). All five key-handling
  loops now use it.
- Action-key case patterns accept both the Latin and the
  Russian-JCUKEN equivalents — `a|A|ф|Ф`, `d|D|в|В`, `c|C|с|С`,
  etc. Either layout now works without surprises.
- Escape sequences (arrow keys, Esc itself) are unaffected — they
  use ASCII bytes regardless of keyboard layout.

## [1.12.2]

**Re-setup:** not required.

### Fixed — wizard list editor: can't delete middle entries
- The list editor (`wizard_list` — used by SSL_DOMAINS,
  NETWORK_INTERFACES, WELCOME_LINES, custom services, etc.)
  previously only supported "delete the LAST entry". To
  remove an entry from the middle you had to delete everything
  after it and re-add — very easy to lose data.
- Rewrote as cursor-based: arrow keys move a `>` cursor over
  the list, `[d]` deletes the **highlighted** entry, `[a]` adds
  a new entry, `[e]` edits the highlighted entry in place
  (pre-filled with the current value for tweaks), `[c]` clears
  everything (with a one-keystroke confirm so you can't nuke
  the list by accident). Enter saves and exits.
- Viewport scrolling for long lists (matches the existing
  `wizard_multiselect` behavior).
- ASCII chrome (`>`, `^`, `v`) — same as everywhere else in
  the wizard, no Unicode glyphs that minimal-font TTYs render
  as boxes.

## [1.12.1]

**Re-setup:** optional.

### Changed — unified SSL cert auto-detect
- The wizard's "Auto-discover Let's Encrypt certs? Y/N" page is gone.
  It was redundant: the v1.12.0 multi-select already had to ask
  about every cert, so the LE-only yes/no on top of it was double
  work. Now there's a single page — pick whatever you want
  monitored from one consolidated list.
- The detector now scans more places, so panel-managed certs
  actually show up:
  - **Let's Encrypt** — `/etc/letsencrypt/live`,
    `/etc/letsencrypt/archive`.
  - **aaPanel** — `/www/server/panel/vhost/cert` and nginx
    configs under `/www/server/panel/vhost/nginx/` (the v1.12.0
    grep was rooted at `/etc/nginx/` only, which is why aaPanel
    found nothing).
  - **ISPmanager** — `/var/www/httpd-cert`,
    `/usr/local/mgr5/etc`.
  - **FastPanel** — `/etc/ssl/certs/fastpanel2`,
    `/var/www/<user>/data/ssl`.
  - **HestiaCP / VestaCP** — `/home/<user>/conf/web/<domain>/ssl`.
  - **Plesk** — `/usr/local/psa/var/certificates`.
  - **cPanel** — `/var/cpanel/ssl/installed/certs`.
  - **nginx / apache configs** anywhere else, including
    `/usr/local/nginx/conf/`, `/usr/local/etc/nginx/`.
- Detection prefers `fullchain.pem` over `cert.pem` when both
  exist in the same directory (matches the LE convention more
  modern tools use).
- **Backwards compatible.** If you upgrade and don't re-run
  `motd-setup`, your existing `SSL_AUTODISCOVER_LETSENCRYPT=true`
  config keeps working — `cache_update_ssl` honors it as a
  fallback whenever `SSL_CERT_PATHS` is still empty. When you do
  re-run setup, detected Let's Encrypt certs are pre-ticked on
  the migration path so Enter-walking the page doesn't lose
  monitoring.

## [1.12.0]

**Re-setup:** optional.

### Added — reboot-required indicator
- The **Package updates** block now also flags when a kernel
  or library update has applied and the box needs a reboot to
  pick up the new code:
  ```
  »»»»»»»»»» Package updates ««««««««««
   Updates    ▸ 0 (system up to date)
   Reboot     ▸ required (kernel/library update applied)
   Checked    ▸ 2m ago
  ```
- Detection is cross-distro:
  - Debian / Ubuntu — `/var/run/reboot-required` marker.
  - openSUSE — `/var/run/reboot-needed` marker and
    `zypper needs-rebooting` (exit 102).
  - RHEL / Fedora / Rocky / Alma — `dnf needs-restarting -r`
    (exit 1 = reboot required).
- The daily Telegram recap already had a Debian-only check;
  it now reads the same cross-distro cache and reports reboot
  status correctly on every distro family.

### Added — auto-detect SSL certs from nginx / apache configs
- New cache scanner greps `/etc/nginx/`, `/usr/local/nginx/conf/`,
  `/etc/apache2/`, `/etc/httpd/` for `ssl_certificate` /
  `SSLCertificateFile` directives. Each parseable PEM/CRT
  file becomes a candidate.
- Useful for hosts running a control panel (ISPmanager,
  aaPanel, FastPanel, HestiaCP, Plesk, cPanel, …) whose certs
  live outside `/etc/letsencrypt/live/`. Previously you had
  to enumerate them by hand in `SSL_DOMAINS`.
- The wizard's SSL page now shows a multi-select over every
  detected cert, with the primary CN as the human label —
  tick the ones you want monitored. Selections are stored in
  a new `SSL_CERT_PATHS` array and rendered alongside the
  existing Let's Encrypt auto-discovery and manual
  `SSL_DOMAINS`.
- Detection runs once per cache cycle (5 min) — zero
  overhead on the on-login render path. Re-run `motd-setup`
  to pick up new vhosts.

### Added — auto-show failed systemd units
- Optional `SERVICES_SHOW_FAILED=true` (off by default). When
  on, the Services section additionally lists every unit in
  the `failed` state, even if it wasn't on the explicit
  `SERVICES_LIST`. Catches crashes of background units you
  didn't know existed.
- Wizard adds a yes/no toggle on the services page right
  after the multi-select.

### Added — `smart-motd benchmark`
- New diagnostic subcommand. Runs each enabled section three
  times (configurable: `smart-motd benchmark 10`) and prints
  a sorted-descending table of average wall-clock milliseconds:
  ```
  smart-motd benchmark — 3 iterations per section

    Section                Avg (ms)
    -------                --------
    ssl                       412
    network                    87
    system                     45
    …
  ```
- Sections > 500 ms render red, 100-500 ms yellow, faster
  green. If something shows up red, it's a hint to either
  disable the section or raise the cache interval — the goal
  is to keep the on-login MOTD snappy.

## [1.11.0]

**Re-setup:** optional.

### Added — multiple Telegram destinations
- New `TELEGRAM_DESTS` array (in root-only `secrets.conf`)
  beyond the primary `TELEGRAM_BOT_TOKEN` / `_CHAT_ID` /
  `_THREAD_ID` tuple. Each entry is `BOT_TOKEN|CHAT_ID|
  THREAD_ID` — useful for the typical managed-services case:
  one alert needs to land in *both* your personal chat **and**
  a client's chat (with a different bot).
  ```bash
  TELEGRAM_DESTS=(
      '1234567:ABC...|-1001234567890|'          # group, no thread
      '9999999:XYZ...|987654321|'               # personal chat
      '4444444:DEF...|-1001112223334|42'        # group with topic 42
  )
  ```
- Both `motd-ssh-alert` and `motd-recap` now iterate every
  destination (primary + extras) in a detached background
  subshell each — a slow or unreachable destination doesn't
  hold up the others. For recap, the once-per-day state file
  is only updated when at least one destination accepted, so
  a single broken endpoint can't permanently mark the day as
  sent.
- Wizard adds a new "Additional Telegram destinations" list
  page right after the alert-language picker. Help text shows
  the format with examples for groups / personal / topics.
- `smart-motd config get TELEGRAM_DESTS` correctly prints
  one destination per line. `config set` refuses (it's an
  array — use the wizard or `smart-motd edit`).
- Fully backward compatible — existing single-destination
  configs keep working without re-setup.

## [1.10.0]

**Re-setup:** optional.

### Added — backup-age annotation in Monitored directories
- Each entry in `DIRECTORIES_LIST` can now optionally be flagged
  as a backup directory by appending `|backup` to the
  `Label|Path` format (`'Backups|/srv/backups|backup'`). For
  flagged entries, the MOTD additionally shows the age of the
  newest file inside the path, color-coded by staleness:
  ```
  Backups            396M  /srv/backups  (newest: 2h ago)    ← green
  DB dumps           1.2G  /srv/db       (newest: 6d ago)    ← yellow (≥2 days)
  Old archive        45G   /srv/archive  (newest: 45d ago)   ← red    (≥7 days)
  Stale              0     /srv/empty    (no files)          ← red
  ```
- Wizard adds a follow-up multiselect after the list editor:
  "Which directories are backups?" — tick the ones that hold
  rotating backup files. On re-runs, the previously-flagged
  entries are pre-checked.
- Newest-file mtime is computed in the cache job via
  `find -printf '%T@' | sort -n | head -1` (GNU find), so the
  on-login path stays free of the heavy scan.

## [1.9.1]

**Re-setup:** not required.

### Fixed
- `sudo smart-motd upgrade` could mis-execute random fragments
  of the newly-installed CLI after the install completed —
  symptoms included spurious `is: command not found`,
  `syntax error near unexpected token ';;'`, and even
  re-running the installer a second time.

  Root cause was the classic "modify a running script" race:
  the installer's `_inst` helper used `cp -f` which truncates
  and overwrites the destination file's inode in place. The
  outer bash process (the original `smart-motd` script that
  kicked off the upgrade) had its read-cursor mid-file when
  `_inst` rewrote `/usr/local/bin/smart-motd` underneath it,
  so subsequent `read()`s returned bytes from NEW code at
  offsets that used to hold OLD code — and bash interpreted
  the garbled mix as commands.

  Fixed by making `_inst` write to a temp file in the same
  directory and `mv` it into place. `mv` atomically swaps
  inodes; the running process keeps reading from the
  now-orphaned old inode (which the kernel preserves until
  the FD closes), and new code only takes effect on the
  NEXT invocation — which is the correct behavior.

## [1.9.0]

**Re-setup:** not required.

### Added — two new CLI commands

- **`sudo smart-motd test-alert [ssh|recap]`** — fire a fake
  Telegram alert immediately, without waiting for an SSH login
  or the configured recap hour. Lets you verify your bot
  token / chat ID / whitelist / language right after a config
  change instead of guessing.
  ```
  sudo smart-motd test-alert         # ssh-login alert (default)
  sudo smart-motd test-alert recap   # daily summary
  ```
  The recap fire uses `SMART_MOTD_FORCE_RECAP=1` to bypass the
  hour gate and the once-per-day state file — but skips writing
  the state file, so today's real recap still fires normally.

- **`smart-motd config get [KEY]`** / **`sudo smart-motd config
  set KEY VALUE`** — surgical edits to the config without
  re-running the full wizard. Useful for Ansible / cloud-init /
  shell scripts.
  ```
  smart-motd config get THEME
  smart-motd config get WELCOME_LINES        # one line per array element
  sudo smart-motd config set WEATHER_CITY Berlin
  sudo smart-motd config set NETWORK_SHOW_RATES false
  ```
  Secrets (`TELEGRAM_BOT_TOKEN` / `CHAT_ID` / `THREAD_ID`)
  automatically route to root-only `secrets.conf`. Array
  values (e.g. `SSL_DOMAINS`, `NETWORK_INTERFACES`) refuse
  `set` with a clear message — use `smart-motd edit` for those.
- Bash tab completion updated to suggest `get / set / help`
  for `config` and `ssh / recap / help` for `test-alert`.

## [1.8.1]

**Re-setup:** not required.

### Changed — clearer upgrade messaging
- The installer now prints a single explicit line about whether
  re-setup is needed, instead of the vague "if any new options
  need configuring…" hint. Each CHANGELOG entry carries a
  `**Re-setup:** not required | optional | recommended` marker
  that the installer parses and renders as:
  ```
  ✓ No re-setup needed — your existing config keeps working.
  ↪ Optional re-setup — new opt-in features are available.
  ⚠ Re-setup recommended — new features need configuration.
  ```
- Long CHANGELOG entries are now truncated to 20 lines in the
  installer output, with a hint to read the shipped
  `CHANGELOG.md` for the full entry.

## [1.8.0]

**Re-setup:** not required.

### Changed — installer output on upgrade
- `smart-motd upgrade` (and any re-install of a different
  version) no longer auto-launches the setup wizard. Instead
  the installer prints the CHANGELOG entry for the just-
  installed version and hints how to launch the wizard on
  demand if any new option needs configuring:
  ```
  ✓ Upgraded smart-motd v1.7.1 → v1.8.0

  What's new in v1.8.0
  ─────────────────────────────────────
  ### Changed — installer output on upgrade
  - ...

  If any new options need configuring, run: sudo smart-motd setup
  ```
  Fresh installs (no prior `VERSION` on disk) still offer to
  launch the wizard immediately, since first-time setup is
  genuinely useful. Re-installing the *same* version just
  prints "No version change — re-installed vX.Y.Z."
- `CHANGELOG.md` now ships into `/usr/local/lib/smart-motd/`
  alongside the runtime, so the installer can quote it on
  upgrade without re-downloading.

## [1.7.1]

**Re-setup:** not required.

### Changed
- Daily Telegram recap now reports only the root mountpoint
  (`/`) for disk usage, instead of every entry in
  `SYSTEM_DISK_PATHS`. Rationale: the recap is a once-a-day
  glance message — multiple disk lines bloat it. The full
  per-mountpoint listing remains in the on-login MOTD where
  the operator can scan it interactively.

## [1.7.0]

**Re-setup:** not required.

### Added — daily Telegram recap is more useful
- Recap now also includes:
  - **Average load (24h)** — `📈 Avg load (24h): 0.42`
  - **Average memory % (24h)** — `🧠 Avg memory (24h): 38%`
  - **Disk usage** for every mountpoint in `SYSTEM_DISK_PATHS`,
    same format as the System status section in the MOTD
    (`💾 Disk /: 11G / 50G (22% used)`).
- New cache helpers `cache_update_load_history` /
  `cache_update_mem_history` append a `<epoch> <value>` sample
  to `/var/cache/smart-motd/{load,mem}_samples` on every cache
  tick (5 min by default, so ~288 samples per day) and prune
  anything older than 24h in the same pass. Disk usage is just
  read live at recap time via `df` — it's slow-moving, no
  history needed.
- Bilingual labels (en/ru) follow the existing
  `TELEGRAM_ALERTS_LANG` setting.

## [1.6.2]

**Re-setup:** not required.

### Fixed
- Right after `sudo smart-motd upgrade`, the MOTD reported a
  bogus "↑ smart-motd vX.Y.Z available (you have vX.Y.Z)" until
  the cache job's next 5-minute tick. Two-layer fix:
  - **install.sh** truncates `/var/cache/smart-motd/upgrade_available`
    at the end of every install / upgrade. The notice stays silent
    until the next cache tick writes a real signal.
  - **`section_upgrade_notice`** now does its own sanity check
    before rendering: compares the cached "newer" string against
    the locally-installed VERSION via `sort -V`, and refuses to
    show the notice unless the cached version is *strictly*
    greater than local. So even if the cache file is out of date
    for any reason (manual `update-cache`, restored backup, etc.),
    no false-positive notice is shown. Verified against six
    edge cases including natural-version ordering (`1.10.0` >
    `1.9.0`).

## [1.6.1]

**Re-setup:** not required.

### Changed
- The upgrade-notice section is now a **system parameter** — no
  longer optional. Removed it from the wizard's first multiselect
  (one less question to answer) and `motd-generate` now forces
  `UPGRADE_NOTICE_ENABLED=true` after sourcing the config,
  overriding whatever's saved on disk. Rationale: surface the
  signal that a newer smart-motd is available — including
  potential security fixes — without giving operators a way to
  silently miss it. The notice still renders zero output when
  the install is up-to-date.

## [1.6.0]

**Re-setup:** not required.

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

**Re-setup:** optional.

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

**Re-setup:** recommended.

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
