#!/usr/bin/env bash
# smart-motd: shared helpers (colors, distro detection, formatting).
# Source-only — do not execute directly.

SMART_MOTD_PREFIX="${SMART_MOTD_PREFIX:-/usr/local/lib/smart-motd}"
SMART_MOTD_CONFIG="${SMART_MOTD_CONFIG:-/etc/smart-motd/config.conf}"
SMART_MOTD_CACHE_DIR="${SMART_MOTD_CACHE_DIR:-/var/cache/smart-motd}"

# ---------- colors ----------
# Disabled automatically when COLORS_ENABLED=false or stdout is not a tty
# (caching layer overrides isatty by setting SMART_MOTD_FORCE_COLOR=1).

_color_init() {
    local enabled="${COLORS_ENABLED:-true}"
    if [[ "$enabled" != "true" ]]; then
        enabled=false
    elif [[ -z "${SMART_MOTD_FORCE_COLOR:-}" ]] && [[ ! -t 1 ]]; then
        enabled=false
    fi

    if [[ "$enabled" == "true" ]]; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_RED=$'\033[31m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_BLUE=$'\033[34m'
        C_MAGENTA=$'\033[35m'
        C_CYAN=$'\033[36m'
        C_WHITE=$'\033[37m'
        C_GREY=$'\033[90m'
    else
        C_RESET=""; C_BOLD=""; C_DIM=""
        C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
        C_MAGENTA=""; C_CYAN=""; C_WHITE=""; C_GREY=""
    fi
}
_color_init

# ---------- distro detection ----------
# Sets DISTRO_ID (e.g. ubuntu), DISTRO_FAMILY (debian|rhel|arch|suse|alpine|other)

detect_distro() {
    DISTRO_ID="unknown"
    DISTRO_FAMILY="other"

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        local id_like="${ID_LIKE:-}"
        case " $DISTRO_ID $id_like " in
            *" debian "*|*" ubuntu "*) DISTRO_FAMILY="debian" ;;
            *" rhel "*|*" fedora "*|*" centos "*|*" rocky "*|*" almalinux "*|*" ol "*)
                DISTRO_FAMILY="rhel" ;;
            *" arch "*|*" manjaro "*) DISTRO_FAMILY="arch" ;;
            *" suse "*|*" opensuse "*|*" opensuse-leap "*|*" opensuse-tumbleweed "*)
                DISTRO_FAMILY="suse" ;;
            *" alpine "*) DISTRO_FAMILY="alpine" ;;
        esac
    fi

    export DISTRO_ID DISTRO_FAMILY
}

# ---------- formatting helpers ----------

# Print a section heading with rule lines.
# Usage: section_heading "Title"
section_heading() {
    local title="$1"
    local total=55
    local title_padded=" ${title} "
    local pad=$(( (total - ${#title_padded}) / 2 ))
    (( pad < 1 )) && pad=1
    local left right
    left=$(printf '%*s' "$pad" '' | tr ' ' '-')
    right=$(printf '%*s' $((total - pad - ${#title_padded})) '' | tr ' ' '-')
    printf "%s%s%s%s%s\n" "${C_GREY}" "$left" "${C_BOLD}${title_padded}${C_RESET}${C_GREY}" "$right" "${C_RESET}"
}

# Print a plain rule line.
section_rule() {
    printf "%s%s%s\n" "${C_GREY}" "$(printf '%*s' 55 '' | tr ' ' '-')" "${C_RESET}"
}

# Heavy double-rule used after the header.
section_thick_rule() {
    printf "%s%s%s\n" "${C_GREY}" "$(printf '%*s' 64 '' | tr ' ' '=')" "${C_RESET}"
}

# Print a labeled line: "  Label   : value"
# Usage: kv "Label" "value" [color]
kv() {
    local label="$1" value="$2" color="${3:-}"
    printf " %-9s: %s%s%s\n" "$label" "$color" "$value" "${C_RESET:-}"
}

# Right-pad a string with spaces between characters: "abc" -> "a b c"
spaced_text() {
    local s="$1" out="" i
    for ((i = 0; i < ${#s}; i++)); do
        out+="${s:$i:1} "
    done
    # trim trailing space
    printf '%s' "${out% }"
}

# ---------- utility ----------

# Returns 0 if command exists.
have() { command -v "$1" >/dev/null 2>&1; }

# Returns 0 if a section is enabled in config.
# Usage: section_enabled DOCKER       (checks $DOCKER_ENABLED)
# "auto" is treated as enabled — sections handle their own auto-detect.
section_enabled() {
    local var="${1}_ENABLED"
    local val="${!var:-false}"
    [[ "$val" == "true" || "$val" == "auto" ]]
}

# Returns 0 if value is "auto"
is_auto() { [[ "${1:-}" == "auto" ]]; }

# Print value with green/yellow/red based on threshold percent (used for disk/mem usage).
# Usage: pct_color 75   -> echoes a color code based on >=90 red, >=75 yellow, else green
pct_color() {
    local pct="$1"
    if (( pct >= 90 )); then printf '%s' "${C_RED}"
    elif (( pct >= 75 )); then printf '%s' "${C_YELLOW}"
    else printf '%s' "${C_GREEN}"
    fi
}

# Read a value from a cache file, default if missing/empty.
cache_read() {
    local name="$1" default="${2:-}"
    local path="${SMART_MOTD_CACHE_DIR}/${name}"
    if [[ -s "$path" ]]; then
        cat "$path"
    else
        printf '%s' "$default"
    fi
}

# Cache age in seconds (returns "never" if file doesn't exist).
cache_age() {
    local path="${SMART_MOTD_CACHE_DIR}/$1"
    if [[ ! -e "$path" ]]; then
        echo "never"
        return
    fi
    local now mtime
    now=$(date +%s)
    mtime=$(stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null || echo "$now")
    echo $(( now - mtime ))
}
