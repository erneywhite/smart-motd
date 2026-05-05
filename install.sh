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
    printf '    %ssudo smart-motd update-cache%s force a cache refresh\n' "${C_BRIGHT_CYAN}" "${C_RESET}"
    printf '    %ssudo smart-motd uninstall%s    remove smart-motd\n' "${C_BRIGHT_CYAN}" "${C_RESET}"
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
install -m 0755 "$WORK"/bin/motd-generate     "$PREFIX/bin/motd-generate"
install -m 0755 "$WORK"/bin/motd-cache-update "$PREFIX/bin/motd-cache-update"
install -m 0755 "$WORK"/bin/motd-setup        "$PREFIX/bin/motd-setup"
install -m 0755 "$WORK"/bin/motd-uninstall    "$PREFIX/bin/motd-uninstall"
install -m 0755 "$WORK"/bin/smart-motd        "$BIN_DIR/smart-motd"
install -m 0644 "$WORK"/lib/common.sh         "$PREFIX/lib/common.sh"
install -m 0644 "$WORK"/lib/cache.sh          "$PREFIX/lib/cache.sh"
install -m 0644 "$WORK"/lib/wizard.sh         "$PREFIX/lib/wizard.sh"
for f in "$WORK"/lib/sections/*.sh; do
    install -m 0644 "$f" "$PREFIX/lib/sections/$(basename "$f")"
done
[[ -f "$WORK/VERSION" ]] && install -m 0644 "$WORK/VERSION" "$PREFIX/VERSION"
[[ -f "$WORK/config.example.conf" ]] && install -m 0644 "$WORK/config.example.conf" "$PREFIX/config.example.conf"
ok "Installed binaries, libs, and section modules"

# ---------- example config if none ----------
if [[ ! -f "$CONFIG_DIR/config.conf" ]] && [[ -f "$WORK/config.example.conf" ]]; then
    cp "$WORK/config.example.conf" "$CONFIG_DIR/config.conf"
    chmod 0644 "$CONFIG_DIR/config.conf"
    ok "Created default config at ${CONFIG_DIR}/config.conf"
else
    ok "Existing config kept at ${CONFIG_DIR}/config.conf"
fi

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
            disabled_count=0
            for f in /etc/update-motd.d/10-help-text \
                     /etc/update-motd.d/50-motd-news \
                     /etc/update-motd.d/00-header \
                     /etc/update-motd.d/80-livepatch \
                     /etc/update-motd.d/91-release-upgrade \
                     /etc/update-motd.d/97-overlayroot; do
                if [[ -x "$f" ]]; then
                    chmod -x "$f" || true
                    disabled_count=$((disabled_count + 1))
                fi
            done
            if (( disabled_count > 0 )); then
                ok "Disabled ${disabled_count} default Ubuntu MOTD scripts"
            fi
        fi
        # Truncate static /etc/motd so it's not duplicated.
        : >/etc/motd 2>/dev/null || true
        ;;
    *)
        step "Wiring login banner via systemd timer (renders /etc/motd every 5 min)"
        if command -v systemctl >/dev/null 2>&1 && [[ -d /etc/systemd/system ]]; then
            install -m 0644 "$WORK"/systemd/smart-motd-render.service /etc/systemd/system/smart-motd-render.service
            install -m 0644 "$WORK"/systemd/smart-motd-render.timer   /etc/systemd/system/smart-motd-render.timer
            systemctl daemon-reload
            systemctl enable --now smart-motd-render.timer >/dev/null 2>&1
            SMART_MOTD_FORCE_COLOR=1 "$PREFIX/bin/motd-generate" >/etc/motd 2>/dev/null || true
            ok "systemd render timer enabled"
        else
            if command -v crontab >/dev/null 2>&1; then
                ( crontab -l 2>/dev/null | grep -v 'smart-motd' ; \
                  echo "*/5 * * * * SMART_MOTD_FORCE_COLOR=1 /usr/local/lib/smart-motd/bin/motd-generate >/etc/motd 2>/dev/null" ) | crontab -
            fi
            SMART_MOTD_FORCE_COLOR=1 "$PREFIX/bin/motd-generate" >/etc/motd 2>/dev/null || true
            ok "cron render entry added (no systemd detected)"
        fi
        ;;
esac

# ---------- systemd cache timer (refreshes heavy data every 5 min) ----------
if command -v systemctl >/dev/null 2>&1 && [[ -d /etc/systemd/system ]]; then
    step "Enabling cache refresh timer (every 5 min)"
    install -m 0644 "$WORK"/systemd/smart-motd-cache.service /etc/systemd/system/smart-motd-cache.service
    install -m 0644 "$WORK"/systemd/smart-motd-cache.timer   /etc/systemd/system/smart-motd-cache.timer
    systemctl daemon-reload
    systemctl enable --now smart-motd-cache.timer >/dev/null 2>&1
    ok "smart-motd-cache.timer enabled"
elif command -v crontab >/dev/null 2>&1; then
    step "Adding cache refresh cron entry (every 5 min)"
    ( crontab -l 2>/dev/null | grep -v 'motd-cache-update' ; \
      echo "*/5 * * * * /usr/local/lib/smart-motd/bin/motd-cache-update >/dev/null 2>&1" ) | crontab -
    ok "cron entry added"
fi

print_summary

# ---------- run setup wizard ----------

if $RUN_SETUP && [[ -r /dev/tty && -w /dev/tty ]]; then
    printf '  %sPress Enter%s to launch the interactive setup, or %sCtrl+C%s to skip and configure later.\n' \
        "${C_BOLD}" "${C_RESET}" "${C_BOLD}" "${C_RESET}"
    printf '  '
    # Wait for Enter (or Ctrl+C / EOF). If the user does Ctrl+C, the trap
    # will clean up the workdir and the wizard simply isn't launched.
    read -r _ </dev/tty || true
    printf '\n'
    "$PREFIX/bin/motd-setup" </dev/tty
else
    printf '  %s!%s Non-interactive install: setup wizard skipped.\n' "${C_YELLOW}" "${C_RESET}"
    printf '    Run it manually with: %ssudo smart-motd setup%s\n' "${C_BRIGHT_CYAN}" "${C_RESET}"
fi
