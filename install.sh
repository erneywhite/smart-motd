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

C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'

echo "${C_BOLD}smart-motd installer${C_RESET}"

# ---- distro detect ----
DISTRO_ID="unknown"; DISTRO_FAMILY="other"
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    case " ${ID:-} ${ID_LIKE:-} " in
        *" debian "*|*" ubuntu "*) DISTRO_FAMILY="debian" ;;
        *" rhel "*|*" fedora "*|*" centos "*|*" rocky "*|*" almalinux "*|*" ol "*) DISTRO_FAMILY="rhel" ;;
        *" arch "*|*" manjaro "*) DISTRO_FAMILY="arch" ;;
        *" suse "*|*" opensuse "*|*" opensuse-leap "*|*" opensuse-tumbleweed "*) DISTRO_FAMILY="suse" ;;
        *" alpine "*) DISTRO_FAMILY="alpine" ;;
    esac
fi
echo "  Detected: $DISTRO_ID (family: $DISTRO_FAMILY)"

# ---- ensure deps ----
NEED=()
command -v curl >/dev/null 2>&1 || NEED+=("curl")
command -v tar  >/dev/null 2>&1 || NEED+=("tar")
command -v awk  >/dev/null 2>&1 || NEED+=("gawk")
if [[ ${#NEED[@]} -gt 0 ]]; then
    echo "  Installing missing prerequisites: ${NEED[*]}"
    case "$DISTRO_FAMILY" in
        debian) apt-get update -qq && apt-get install -y --no-install-recommends "${NEED[@]}" ;;
        rhel)   (command -v dnf >/dev/null && dnf install -y "${NEED[@]}") || yum install -y "${NEED[@]}" ;;
        suse)   zypper --non-interactive install "${NEED[@]}" ;;
        arch)   pacman -Sy --noconfirm "${NEED[@]}" ;;
        alpine) apk add --no-cache "${NEED[@]}" ;;
        *) echo "  ${C_YELLOW}Cannot auto-install on this distro; please install manually: ${NEED[*]}${C_RESET}" ;;
    esac
fi

# ---- fetch source ----
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [[ -n "$SOURCE_DIR" ]]; then
    echo "  Using local source: $SOURCE_DIR"
    cp -a "$SOURCE_DIR"/. "$WORK/"
else
    URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
    echo "  Fetching ${URL}"
    curl -fsSL "$URL" | tar -xz -C "$WORK" --strip-components=1
fi

# ---- install files ----
echo "  Installing to $PREFIX"
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

# ---- example config if none ----
if [[ ! -f "$CONFIG_DIR/config.conf" ]] && [[ -f "$WORK/config.example.conf" ]]; then
    cp "$WORK/config.example.conf" "$CONFIG_DIR/config.conf"
    chmod 0644 "$CONFIG_DIR/config.conf"
    echo "  Wrote example config to $CONFIG_DIR/config.conf"
fi

# ---- distro-specific MOTD hook ----
case "$DISTRO_FAMILY" in
    debian)
        echo "  Wiring MOTD via /etc/update-motd.d/01-smart-motd"
        cat >/etc/update-motd.d/01-smart-motd <<'EOF'
#!/usr/bin/env bash
exec /usr/local/lib/smart-motd/bin/motd-generate
EOF
        chmod +x /etc/update-motd.d/01-smart-motd
        if $DISABLE_DEFAULT_MOTD; then
            for f in /etc/update-motd.d/10-help-text \
                     /etc/update-motd.d/50-motd-news \
                     /etc/update-motd.d/00-header \
                     /etc/update-motd.d/80-livepatch \
                     /etc/update-motd.d/91-release-upgrade \
                     /etc/update-motd.d/97-overlayroot; do
                if [[ -x "$f" ]]; then
                    chmod -x "$f" || true
                fi
            done
        fi
        # Truncate static /etc/motd so it's not duplicated.
        : >/etc/motd 2>/dev/null || true
        ;;
    *)
        echo "  Wiring MOTD via systemd timer (writes /etc/motd every 5 minutes)"
        if command -v systemctl >/dev/null 2>&1 && [[ -d /etc/systemd/system ]]; then
            install -m 0644 "$WORK"/systemd/smart-motd-render.service /etc/systemd/system/smart-motd-render.service
            install -m 0644 "$WORK"/systemd/smart-motd-render.timer   /etc/systemd/system/smart-motd-render.timer
            systemctl daemon-reload
            systemctl enable --now smart-motd-render.timer
            # Render once immediately.
            "$PREFIX/bin/motd-generate" >/etc/motd 2>/dev/null || true
        else
            # Fallback: cron @5min
            if command -v crontab >/dev/null 2>&1; then
                ( crontab -l 2>/dev/null | grep -v 'smart-motd' ; \
                  echo "*/5 * * * * /usr/local/lib/smart-motd/bin/motd-generate >/etc/motd 2>/dev/null" ) | crontab -
            fi
            "$PREFIX/bin/motd-generate" >/etc/motd 2>/dev/null || true
        fi
        ;;
esac

# ---- systemd cache timer (all distros that have systemd) ----
if command -v systemctl >/dev/null 2>&1 && [[ -d /etc/systemd/system ]]; then
    install -m 0644 "$WORK"/systemd/smart-motd-cache.service /etc/systemd/system/smart-motd-cache.service
    install -m 0644 "$WORK"/systemd/smart-motd-cache.timer   /etc/systemd/system/smart-motd-cache.timer
    systemctl daemon-reload
    systemctl enable --now smart-motd-cache.timer
elif command -v crontab >/dev/null 2>&1; then
    ( crontab -l 2>/dev/null | grep -v 'motd-cache-update' ; \
      echo "*/5 * * * * /usr/local/lib/smart-motd/bin/motd-cache-update >/dev/null 2>&1" ) | crontab -
fi

# ---- run setup wizard ----
echo
echo "${C_GREEN}smart-motd installed.${C_RESET}"

# When invoked via `curl ... | sudo bash`, stdin is the curl pipe, not a tty.
# Re-open /dev/tty for the interactive setup wizard.
if $RUN_SETUP && [[ -r /dev/tty && -w /dev/tty ]]; then
    echo "Running interactive setup…"
    sleep 1
    "$PREFIX/bin/motd-setup" </dev/tty
else
    echo "${C_YELLOW}Non-interactive install: skipping setup wizard.${C_RESET}"
    echo "  Run it manually with:  sudo smart-motd setup"
    echo "  Preview with:          smart-motd show"
fi
