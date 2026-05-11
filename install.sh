#!/usr/bin/env bash
# smart-motd installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/erneywhite/smart-motd/main/install.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/erneywhite/smart-motd/main/install.sh | sudo bash -s -- --no-setup
#
# Flags:
#   --no-setup       Skip running the interactive wizard at the end.
#   --no-disable-default-motd   Don't disable Ubuntu's default update-motd.d scripts.
#   --branch BRANCH  Install from a specific git branch (default: main).
#   --source DIR     Install from a local directory instead of cloning (used in CI/testing).

set -euo pipefail

# Ensure Ctrl+C / TERM aborts the installer cleanly. Without an explicit
# trap, signal handling inside `read -r` and pipelines is inconsistent
# across shells/distros and the user can get stuck.
trap 'printf "\n\033[33m! Installation aborted by user.\033[0m\n" >&2; exit 130' INT TERM

REPO="${SMART_MOTD_REPO:-erneywhite/smart-motd}"
BRANCH="${SMART_MOTD_BRANCH:-main}"
PREFIX="/usr/local/lib/smart-motd"
BIN_DIR="/usr/local/bin"
CONFIG_DIR="/etc/smart-motd"
CACHE_DIR="/var/cache/smart-motd"
SOURCE_DIR=""
RUN_SETUP=true
DISABLE_DEFAULT_MOTD=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-setup) RUN_SETUP=false ;;
        --no-disable-default-motd) DISABLE_DEFAULT_MOTD=false ;;
        --branch) BRANCH="$2"; shift ;;
        --source) SOURCE_DIR="$2"; shift ;;
        --help|-h)
            sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

if [[ "$EUID" -ne 0 ]]; then
    echo "This installer must run as root. Try: curl ... | sudo bash" >&2
    exit 1
fi

# ---------- styling ----------
# Force color when output is a terminal-ish destination. The pam_motd /
# subprocess case isn't relevant here (we run interactively).
if [[ -t 1 ]] || [[ -n "${FORCE_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_MAGENTA=$'\033[35m'
    C_CYAN=$'\033[36m'
    C_GREY=$'\033[90m'
    C_BRIGHT_GREEN=$'\033[92m'
    C_BRIGHT_CYAN=$'\033[96m'
else
    C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""
    C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_GREY=""
    C_BRIGHT_GREEN=""; C_BRIGHT_CYAN=""
fi

# ---------- visual helpers ----------

step()  { printf '  %s▸%s %s\n' "${C_DIM}" "${C_RESET}" "$1"; }
ok()    { printf '  %s✓%s %s\n' "${C_BRIGHT_GREEN}" "${C_RESET}" "$1"; }
warn()  { printf '  %s!%s %s\n' "${C_YELLOW}" "${C_RESET}" "$1"; }
err()   { printf '  %s✗%s %s\n' "${C_RED}" "${C_RESET}" "$1" >&2; }
note()  { printf '    %s%s%s\n' "${C_DIM}" "$1" "${C_RESET}"; }

# Repeat a single character N times.
_repeat() {
    local ch="$1" n="$2" out="" i
    for ((i = 0; i < n; i++)); do out+="$ch"; done
    printf '%s' "$out"
}

# Drop-in cp+chmod replacement for `install -m MODE SRC DST`. We can't rely
# on GNU coreutils' install being first in PATH — some images ship a
# different `install` binary (e.g. helm, AUR helpers) that takes
# "install [PACKAGE...]" instead.
#
# IMPORTANT: write to a temp file in the destination directory and then
# rename it into place, rather than cp-ing onto the existing file. A plain
# `cp -f DST` truncates and rewrites the SAME inode — fine for inert files,
# but FATAL when DST is currently being read (e.g. /usr/local/bin/smart-motd
# is the script that just kicked off this upgrade). Without atomic rename
# the parent bash keeps reading from the byte offset where it left off,
# picks up garbled NEW content where it expected OLD, and mis-executes the
# rest of the file. `mv` swaps the inode atomically — the running
# process's open file descriptor stays bound to the now-orphaned old inode,
# which the kernel keeps alive until that FD closes. New code only takes
# effect on the NEXT invocation, which is what we want.
_inst() {
    local mode="$1" src="$2" dst="$3"
    local dir tmp
    dir=$(dirname "$dst")
    # Stage the file inside the destination directory so `mv` is on the
    # same filesystem (otherwise it would degrade to copy-then-unlink,
    # which races just like cp does).
    tmp=$(mktemp -p "$dir" ".smart-motd-inst.XXXXXX" 2>/dev/null) \
        || tmp="${dst}.smart-motd-inst.$$"
    cp -f "$src" "$tmp"
    chmod "$mode" "$tmp"
    mv -f "$tmp" "$dst"
}

# Banner with auto-computed inner width based on the longest content line.
# No matter how short or long each line is, the right "│" always lines up.
print_banner() {
    local lines=(
        "smart-motd"
        "customizable MOTD for Linux servers"
        "github.com/${REPO}"
    )
    local maxlen=0 s
    for s in "${lines[@]}"; do
        (( ${#s} > maxlen )) && maxlen=${#s}
    done
    local pad_inner=4
    local inner=$(( maxlen + pad_inner * 2 ))
    local hr blank lpad
    hr=$(_repeat '─' "$inner")
    blank=$(_repeat ' ' "$inner")
    lpad=$(_repeat ' ' "$pad_inner")

    _line() {
        local content="$1" color="${2:-}" rpad
        rpad=$(_repeat ' ' $((maxlen - ${#content})))
        printf '  %s│%s%s%s%s%s%s%s%s│%s\n' \
            "${C_CYAN}" "${C_RESET}" \
            "$lpad" \
            "$color" "$content" "${C_RESET}" \
            "$rpad" "$lpad" \
            "${C_CYAN}" "${C_RESET}"
    }

    printf '\n'
    printf '  %s╭%s╮%s\n' "${C_CYAN}" "$hr" "${C_RESET}"
    printf '  %s│%s%s%s│%s\n' "${C_CYAN}" "${C_RESET}" "$blank" "${C_CYAN}" "${C_RESET}"
    _line "${lines[0]}" "${C_BOLD}${C_BRIGHT_CYAN}"
    _line "${lines[1]}" "${C_DIM}"
    _line "${lines[2]}" "${C_DIM}"
    printf '  %s│%s%s%s│%s\n' "${C_CYAN}" "${C_RESET}" "$blank" "${C_CYAN}" "${C_RESET}"
    printf '  %s╰%s╯%s\n' "${C_CYAN}" "$hr" "${C_RESET}"
    printf '\n'
}

print_summary() {
    printf '\n'
    printf '  %s%s installed successfully%s\n' "${C_BRIGHT_GREEN}${C_BOLD}" "✓ smart-motd" "${C_RESET}"
    printf '\n'
    printf '  %sLocations%s\n' "${C_BOLD}" "${C_RESET}"
    printf '    runtime  %s%s%s\n' "${C_DIM}" "$PREFIX" "${C_RESET}"
    printf '    config   %s%s/config.conf%s\n' "${C_DIM}" "$CONFIG_DIR" "${C_RESET}"
    printf '    cache    %s%s%s\n' "${C_DIM}" "$CACHE_DIR" "${C_RESET}"
    printf '    cli      %s%s/smart-motd%s\n' "${C_DIM}" "$BIN_DIR" "${C_RESET}"
    printf '\n'
    printf '  %sCommands%s\n' "${C_BOLD}" "${C_RESET}"
    printf '    %ssmart-motd show%s             preview the MOTD\n' "${C_BRIGHT_CYAN}" "${C_RESET}"
    printf '    %ssudo smart-motd setup%s       re-run the wizard\n' "${C_BRIGHT_CYAN}" "${C_RESET}"
    printf '    %ssmart-motd doctor%s           diagnose the install\n' "${C_BRIGHT_CYAN}" "${C_RESET}"
    printf '    %ssudo smart-motd upgrade%s     pull the latest release\n' "${C_BRIGHT_CYAN}" "${C_RESET}"
    printf '    %ssudo smart-motd uninstall%s   remove smart-motd\n' "${C_BRIGHT_CYAN}" "${C_RESET}"
    printf '\n'
}

print_banner

# ---------- distro detect ----------
DISTRO_ID="unknown"; DISTRO_VERSION=""; DISTRO_FAMILY="other"
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_VERSION="${VERSION_ID:-}"
    case " ${ID:-} ${ID_LIKE:-} " in
        *" debian "*|*" ubuntu "*) DISTRO_FAMILY="debian" ;;
        *" rhel "*|*" fedora "*|*" centos "*|*" rocky "*|*" almalinux "*|*" ol "*) DISTRO_FAMILY="rhel" ;;
        *" arch "*|*" manjaro "*) DISTRO_FAMILY="arch" ;;
        *" suse "*|*" opensuse "*|*" opensuse-leap "*|*" opensuse-tumbleweed "*) DISTRO_FAMILY="suse" ;;
        *" alpine "*) DISTRO_FAMILY="alpine" ;;
    esac
fi
ok "Detected ${C_BOLD}${DISTRO_ID}${C_RESET} ${DISTRO_VERSION}${DISTRO_VERSION:+ }${C_DIM}(family: ${DISTRO_FAMILY})${C_RESET}"

# ---------- ensure deps ----------
NEED=()
command -v curl >/dev/null 2>&1 || NEED+=("curl")
command -v tar  >/dev/null 2>&1 || NEED+=("tar")
command -v awk  >/dev/null 2>&1 || NEED+=("gawk")
if [[ ${#NEED[@]} -gt 0 ]]; then
    step "Installing prerequisites: ${NEED[*]}"
    case "$DISTRO_FAMILY" in
        debian) apt-get update -qq >/dev/null && apt-get install -y --no-install-recommends "${NEED[@]}" >/dev/null ;;
        rhel)   (command -v dnf >/dev/null && dnf install -y -q "${NEED[@]}" >/dev/null) || yum install -y -q "${NEED[@]}" >/dev/null ;;
        suse)   zypper --non-interactive --quiet install "${NEED[@]}" >/dev/null ;;
        arch)   pacman -Sy --noconfirm --quiet "${NEED[@]}" >/dev/null ;;
        alpine) apk add --no-cache --quiet "${NEED[@]}" >/dev/null ;;
        *) warn "Cannot auto-install on this distro; please install manually: ${NEED[*]}" ;;
    esac
    ok "Prerequisites installed"
else
    ok "Prerequisites already present (curl, tar, awk)"
fi

# ---------- fetch source ----------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [[ -n "$SOURCE_DIR" ]]; then
    step "Using local source: $SOURCE_DIR"
    cp -a "$SOURCE_DIR"/. "$WORK/"
    ok "Source copied"
else
    URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
    step "Downloading smart-motd from GitHub (${BRANCH})"
    curl -fsSL "$URL" | tar -xz -C "$WORK" --strip-components=1
    if [[ -r "$WORK/VERSION" ]]; then
        ok "Downloaded smart-motd $(cat "$WORK/VERSION")"
    else
        ok "Downloaded smart-motd"
    fi
fi

# ---------- install files ----------
step "Installing runtime to ${PREFIX}"
mkdir -p "$PREFIX/lib" "$PREFIX/bin" "$PREFIX/lib/sections" "$CONFIG_DIR" "$CACHE_DIR" "$BIN_DIR"
# Capture the previous install's version BEFORE we overwrite VERSION below.
# Empty when this is a fresh install (no prior smart-motd on the box).
OLD_VERSION=""
[[ -r "$PREFIX/VERSION" ]] && OLD_VERSION=$(cat "$PREFIX/VERSION" 2>/dev/null | tr -d ' \r\n')

_inst 0755 "$WORK"/bin/motd-generate     "$PREFIX/bin/motd-generate"
_inst 0755 "$WORK"/bin/motd-cache-update "$PREFIX/bin/motd-cache-update"
_inst 0755 "$WORK"/bin/motd-setup        "$PREFIX/bin/motd-setup"
_inst 0755 "$WORK"/bin/motd-doctor       "$PREFIX/bin/motd-doctor"
_inst 0755 "$WORK"/bin/motd-ssh-alert    "$PREFIX/bin/motd-ssh-alert"
_inst 0755 "$WORK"/bin/motd-recap        "$PREFIX/bin/motd-recap"
_inst 0755 "$WORK"/bin/motd-uninstall    "$PREFIX/bin/motd-uninstall"
_inst 0755 "$WORK"/bin/smart-motd        "$BIN_DIR/smart-motd"
_inst 0644 "$WORK"/lib/common.sh         "$PREFIX/lib/common.sh"
_inst 0644 "$WORK"/lib/cache.sh          "$PREFIX/lib/cache.sh"
_inst 0644 "$WORK"/lib/wizard.sh         "$PREFIX/lib/wizard.sh"
for f in "$WORK"/lib/sections/*.sh; do
    _inst 0644 "$f" "$PREFIX/lib/sections/$(basename "$f")"
done
[[ -f "$WORK/VERSION" ]] && _inst 0644 "$WORK/VERSION" "$PREFIX/VERSION"
[[ -f "$WORK/config.example.conf" ]] && _inst 0644 "$WORK/config.example.conf" "$PREFIX/config.example.conf"
# Ship CHANGELOG.md alongside the runtime so upgrades can quote it.
[[ -f "$WORK/CHANGELOG.md" ]] && _inst 0644 "$WORK/CHANGELOG.md" "$PREFIX/CHANGELOG.md"
ok "Installed binaries, libs, and section modules"

# Bash tab completion. Prefer the modern bash-completion location, fall back
# to the legacy one. Either gets auto-loaded by bash-completion at shell
# start-up — no further wiring needed.
if [[ -f "$WORK/completions/smart-motd.bash" ]]; then
    if [[ -d /usr/share/bash-completion/completions ]]; then
        _inst 0644 "$WORK/completions/smart-motd.bash" \
            /usr/share/bash-completion/completions/smart-motd
        ok "Bash tab completion installed (open a new shell to activate)"
    elif [[ -d /etc/bash_completion.d ]]; then
        _inst 0644 "$WORK/completions/smart-motd.bash" \
            /etc/bash_completion.d/smart-motd
        ok "Bash tab completion installed (open a new shell to activate)"
    fi
fi

# ---------- example config if none ----------
if [[ ! -f "$CONFIG_DIR/config.conf" ]] && [[ -f "$WORK/config.example.conf" ]]; then
    cp "$WORK/config.example.conf" "$CONFIG_DIR/config.conf"
    chmod 0644 "$CONFIG_DIR/config.conf"
    ok "Created default config at ${CONFIG_DIR}/config.conf"
else
    ok "Existing config kept at ${CONFIG_DIR}/config.conf"
fi

# Reset the upgrade-available cache. Without this, an `smart-motd upgrade`
# from version A to version B leaves the file holding "B" — and the very
# next login renders 'smart-motd vB available (you have vB)' until the
# next cache tick (~5 min) refreshes it. Truncating now means the section
# stays silent until the cache job runs and writes a real signal.
: > "$CACHE_DIR/upgrade_available" 2>/dev/null || true

# ---------- distro-specific MOTD hook ----------
case "$DISTRO_FAMILY" in
    debian)
        step "Wiring login banner via /etc/update-motd.d/01-smart-motd"
        cat >/etc/update-motd.d/01-smart-motd <<'EOF'
#!/usr/bin/env bash
# pam_motd captures stdout, which makes [[ -t 1 ]] false; force-enable colors.
SMART_MOTD_FORCE_COLOR=1 exec /usr/local/lib/smart-motd/bin/motd-generate
EOF
        chmod +x /etc/update-motd.d/01-smart-motd
        ok "Hook installed"

        if $DISABLE_DEFAULT_MOTD; then
            # Disable EVERY existing script in /etc/update-motd.d/ except our
            # own. Hard-coding a list of "known" Ubuntu defaults is fragile —
            # new releases add scripts (50-landscape-sysinfo, 88-esm-announce,
            # 90-updates-available, etc.) and those leak into the banner.
            disabled_count=0
            for f in /etc/update-motd.d/*; do
                [[ -e "$f" ]] || continue
                [[ "$(basename "$f")" == "01-smart-motd" ]] && continue
                if [[ -x "$f" ]]; then
                    chmod -x "$f" 2>/dev/null || true
                    disabled_count=$((disabled_count + 1))
                fi
            done
            if (( disabled_count > 0 )); then
                ok "Disabled ${disabled_count} default Ubuntu MOTD script(s)"
            fi
        fi
        # Truncate static /etc/motd so the second pam_motd line in
        # /etc/pam.d/sshd doesn't add anything below our banner.
        : >/etc/motd 2>/dev/null || true
        # Also nuke /etc/motd.d/ contents (some Ubuntu releases route through
        # there): leave the directory but clear executable bits.
        if [[ -d /etc/motd.d ]]; then
            for f in /etc/motd.d/*; do
                [[ -e "$f" ]] || continue
                [[ -x "$f" ]] && chmod -x "$f" 2>/dev/null || true
            done
        fi
        ;;
    *)
        # Detect whether systemd is actually RUNNING (not just installed).
        # Docker containers and chroots often have the systemctl binary +
        # /etc/systemd/system, but no systemd as PID 1 — `daemon-reload`
        # then bombs with "Failed to connect to system scope bus". The
        # /run/systemd/system directory is the canonical "systemd is up"
        # marker (created by systemd at boot; absent without it).
        if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
            step "Wiring login banner via systemd timer (renders /etc/motd every 5 min)"
            _inst 0644 "$WORK"/systemd/smart-motd-render.service /etc/systemd/system/smart-motd-render.service
            _inst 0644 "$WORK"/systemd/smart-motd-render.timer   /etc/systemd/system/smart-motd-render.timer
            systemctl daemon-reload 2>/dev/null \
              && systemctl enable --now smart-motd-render.timer >/dev/null 2>&1 \
              && ok "systemd render timer enabled" \
              || warn "Couldn't enable smart-motd-render.timer — try 'systemctl enable --now smart-motd-render.timer' manually"
            SMART_MOTD_FORCE_COLOR=1 "$PREFIX/bin/motd-generate" >/etc/motd 2>/dev/null || true
        elif command -v crontab >/dev/null 2>&1; then
            step "Wiring login banner via cron (renders /etc/motd every 5 min)"
            ( crontab -l 2>/dev/null | grep -v 'smart-motd' ; \
              echo "*/5 * * * * SMART_MOTD_FORCE_COLOR=1 /usr/local/lib/smart-motd/bin/motd-generate >/etc/motd 2>/dev/null" ) | crontab - \
              && ok "cron render entry added" \
              || warn "Couldn't write crontab entry — render /etc/motd yourself or set up a timer manually"
            SMART_MOTD_FORCE_COLOR=1 "$PREFIX/bin/motd-generate" >/etc/motd 2>/dev/null || true
        else
            warn "Neither systemd nor cron available — /etc/motd won't auto-refresh"
            note "Run 'smart-motd update-cache && smart-motd show > /etc/motd' periodically yourself."
            SMART_MOTD_FORCE_COLOR=1 "$PREFIX/bin/motd-generate" >/etc/motd 2>/dev/null || true
        fi
        ;;
esac

# ---------- cache refresh job (every 5 min) ----------
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    step "Enabling cache refresh timer (every 5 min)"
    _inst 0644 "$WORK"/systemd/smart-motd-cache.service /etc/systemd/system/smart-motd-cache.service
    _inst 0644 "$WORK"/systemd/smart-motd-cache.timer   /etc/systemd/system/smart-motd-cache.timer
    systemctl daemon-reload 2>/dev/null \
      && systemctl enable --now smart-motd-cache.timer >/dev/null 2>&1 \
      && ok "smart-motd-cache.timer enabled" \
      || warn "Couldn't enable smart-motd-cache.timer — try 'systemctl enable --now smart-motd-cache.timer' manually"
elif command -v crontab >/dev/null 2>&1; then
    step "Adding cache refresh cron entry (every 5 min)"
    ( crontab -l 2>/dev/null | grep -v 'motd-cache-update' ; \
      echo "*/5 * * * * /usr/local/lib/smart-motd/bin/motd-cache-update >/dev/null 2>&1" ) | crontab - \
      && ok "cron entry added" \
      || warn "Couldn't write crontab entry — run 'smart-motd update-cache' periodically yourself"
else
    warn "No scheduler (systemd / cron) detected — cache won't auto-refresh"
    note "Run 'sudo smart-motd update-cache' periodically yourself."
fi

# ---------- SSH login alert PAM hook ----------
# We always wire the hook so users can flip TELEGRAM_ALERTS_ENABLED on
# later via `sudo smart-motd setup` without re-touching pam.d. The script
# itself bails immediately when the feature is off (zero overhead).
if [[ -f /etc/pam.d/sshd ]]; then
    PAM_LINE="session optional pam_exec.so $PREFIX/bin/motd-ssh-alert"
    if grep -q "motd-ssh-alert" /etc/pam.d/sshd 2>/dev/null; then
        ok "SSH alert PAM hook already in /etc/pam.d/sshd"
    else
        # Backup once before our first edit so the operator can restore.
        if [[ ! -f /etc/pam.d/sshd.smart-motd.bak ]]; then
            cp /etc/pam.d/sshd /etc/pam.d/sshd.smart-motd.bak 2>/dev/null || true
        fi
        if printf '\n# smart-motd SSH login alert hook\n%s\n' "$PAM_LINE" >> /etc/pam.d/sshd 2>/dev/null; then
            ok "Wired SSH alert hook into /etc/pam.d/sshd"
            note "Backup at /etc/pam.d/sshd.smart-motd.bak; uninstall removes the line."
        else
            warn "Couldn't append to /etc/pam.d/sshd — SSH alert hook NOT installed"
        fi
    fi
else
    note "/etc/pam.d/sshd not present — skipping SSH alert hook (alerts won't fire on login)"
fi

print_summary

# Capture the just-installed version for upgrade-vs-fresh branching below.
NEW_VERSION=""
[[ -r "$PREFIX/VERSION" ]] && NEW_VERSION=$(cat "$PREFIX/VERSION" 2>/dev/null | tr -d ' \r\n')

# Print the CHANGELOG section for a given version, truncated to a sane
# number of lines. Reads /usr/local/lib/smart-motd/CHANGELOG.md (shipped
# alongside the runtime), extracts the "## [VERSION]" block, and prints
# it indented. Silent if the changelog is missing or the version isn't
# found there. Strips the **Re-setup:** marker line — that's parsed
# separately into a clear status message below.
CHANGELOG_MAX_LINES=20

show_changelog_for_version() {
    local v="$1" file="$PREFIX/CHANGELOG.md"
    [[ -r "$file" ]] || return
    local body total
    body=$(awk -v want="$v" '
        BEGIN { in_block = 0; printed = 0; pending = "" }
        $0 ~ "^## \\[" want "\\]" { in_block = 1; next }
        in_block && /^## \[/      { exit }
        in_block {
            if ($0 ~ /\*\*Re-setup:\*\*/) next       # parsed separately
            if (printed == 0 && $0 ~ /^[[:space:]]*$/) next
            if ($0 ~ /^[[:space:]]*$/) {
                pending = pending "\n"
            } else {
                if (pending != "") { printf "%s", pending; pending = "" }
                print
                printed = 1
            }
        }
    ' "$file")
    [[ -z "$body" ]] && return
    total=$(printf '%s\n' "$body" | wc -l | tr -d ' ')

    printf '\n  %sWhat'\''s new in v%s%s\n' "${C_BOLD}" "$v" "${C_RESET}"
    printf '  %s──────────────────────────────────────────────%s\n' "${C_DIM}" "${C_RESET}"
    local i=0
    while IFS= read -r line; do
        i=$((i + 1))
        if (( i > CHANGELOG_MAX_LINES )); then
            local remaining=$(( total - CHANGELOG_MAX_LINES ))
            printf '  %s… %d more line(s) — see %s/CHANGELOG.md for the full entry%s\n' \
                "${C_DIM}" "$remaining" "$PREFIX" "${C_RESET}"
            break
        fi
        printf '  %s\n' "$line"
    done <<<"$body"
}

# Parse the Re-setup marker line from a CHANGELOG entry. Returns one of:
#   "not required" | "optional" | "recommended" | ""  (no marker)
get_resetup_status() {
    local v="$1" file="$PREFIX/CHANGELOG.md"
    [[ -r "$file" ]] || return
    awk -v want="$v" '
        $0 ~ "^## \\[" want "\\]" { in_block = 1; next }
        in_block && /^## \[/      { exit }
        in_block && /\*\*Re-setup:\*\*/ {
            sub(/^.*\*\*Re-setup:\*\*[[:space:]]*/, "")
            sub(/[[:space:]]*[.,].*$/, "")
            sub(/[[:space:]]*$/, "")
            print tolower($0)
            exit
        }
    ' "$file"
}

# ---------- post-install: fresh vs upgrade ----------

if [[ -z "$OLD_VERSION" ]]; then
    # Fresh install — no prior VERSION on disk. Offer the wizard as
    # before; first-time setup is genuinely useful.
    if $RUN_SETUP && [[ -r /dev/tty && -w /dev/tty ]]; then
        printf '  %sPress Enter%s to launch the interactive setup, or %sCtrl+C%s to skip and configure later.\n' \
            "${C_BOLD}" "${C_RESET}" "${C_BOLD}" "${C_RESET}"
        printf '  '
        read -r _ </dev/tty || true
        printf '\n'
        "$PREFIX/bin/motd-setup" </dev/tty
    else
        printf '  %s!%s Non-interactive install: setup wizard skipped.\n' "${C_YELLOW}" "${C_RESET}"
        printf '    Run it manually with: %ssudo smart-motd setup%s\n' "${C_BRIGHT_CYAN}" "${C_RESET}"
    fi
elif [[ "$OLD_VERSION" == "$NEW_VERSION" ]]; then
    # Same version re-installed (e.g. someone re-ran the curl|bash on the
    # latest tag they already had). No changelog to show; just confirm.
    printf '  %sNo version change — re-installed v%s.%s\n\n' \
        "${C_DIM}" "$NEW_VERSION" "${C_RESET}"
else
    # Real upgrade — show what's new, but DON'T auto-launch the wizard.
    # The previous behavior of jumping into the wizard after every upgrade
    # was annoying when nothing actually needs reconfiguring.
    printf '\n  %s✓ Upgraded smart-motd v%s → v%s%s\n' \
        "${C_BRIGHT_GREEN}${C_BOLD}" "$OLD_VERSION" "$NEW_VERSION" "${C_RESET}"
    show_changelog_for_version "$NEW_VERSION"

    # Tell the operator whether they need to re-run setup or not, based on
    # the "Re-setup:" marker the release author put in the CHANGELOG entry.
    resetup=$(get_resetup_status "$NEW_VERSION")
    printf '\n'
    case "$resetup" in
        "not required")
            printf '  %s✓ No re-setup needed%s — your existing config keeps working.\n' \
                "${C_BRIGHT_GREEN}" "${C_RESET}"
            printf '    %sIf you do want to change settings later, run:%s %ssudo smart-motd setup%s\n\n' \
                "${C_DIM}" "${C_RESET}" "${C_BRIGHT_CYAN}" "${C_RESET}"
            ;;
        "optional")
            printf '  %s↪ Optional re-setup%s — new opt-in features are available.\n' \
                "${C_BRIGHT_CYAN}" "${C_RESET}"
            printf '    %sTo enable them, run:%s %ssudo smart-motd setup%s\n\n' \
                "${C_DIM}" "${C_RESET}" "${C_BRIGHT_CYAN}" "${C_RESET}"
            ;;
        "recommended")
            printf '  %s⚠ Re-setup recommended%s — new features need configuration.\n' \
                "${C_YELLOW}${C_BOLD}" "${C_RESET}"
            printf '    %sRun:%s %ssudo smart-motd setup%s\n\n' \
                "${C_DIM}" "${C_RESET}" "${C_BRIGHT_CYAN}" "${C_RESET}"
            ;;
        *)
            # No marker in the changelog entry — fall back to the generic
            # hint. This covers older entries that pre-date the marker.
            printf '  %sIf any new options need configuring, run:%s %ssudo smart-motd setup%s\n\n' \
                "${C_DIM}" "${C_RESET}" "${C_BRIGHT_CYAN}" "${C_RESET}"
            ;;
    esac
fi
