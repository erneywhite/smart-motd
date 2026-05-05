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
        # Bright (high-intensity) variants
        C_BRIGHT_RED=$'\033[91m'
        C_BRIGHT_GREEN=$'\033[92m'
        C_BRIGHT_YELLOW=$'\033[93m'
        C_BRIGHT_BLUE=$'\033[94m'
        C_BRIGHT_MAGENTA=$'\033[95m'
        C_BRIGHT_CYAN=$'\033[96m'
        C_BRIGHT_WHITE=$'\033[97m'
    else
        C_RESET=""; C_BOLD=""; C_DIM=""
        C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
        C_MAGENTA=""; C_CYAN=""; C_WHITE=""; C_GREY=""
        C_BRIGHT_RED=""; C_BRIGHT_GREEN=""; C_BRIGHT_YELLOW=""
        C_BRIGHT_BLUE=""; C_BRIGHT_MAGENTA=""; C_BRIGHT_CYAN=""; C_BRIGHT_WHITE=""
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

# ---------- theme presets ----------
# THEME applies to the rule characters and section heading style.
# Set THEME=custom to override the individual THEME_* variables manually.

apply_theme() {
    # Theme presets — `:=` so per-variable user overrides in config win.
    # If you want a clean re-apply, `unset THEME_BANNER_CHAR THEME_DIVIDER_CHAR
    # THEME_KV_SEPARATOR THEME_HEADING_STYLE` first (the setup wizard does this).
    local name="${THEME:-classic}"
    case "$name" in
        classic)
            : "${THEME_BANNER_CHAR:==}"
            : "${THEME_DIVIDER_CHAR:=-}"
            : "${THEME_KV_SEPARATOR:=:}"
            : "${THEME_HEADING_STYLE:=centered}"
            ;;
        slim)
            : "${THEME_BANNER_CHAR:=─}"
            : "${THEME_DIVIDER_CHAR:=─}"
            : "${THEME_KV_SEPARATOR:=:}"
            : "${THEME_HEADING_STYLE:=centered}"
            ;;
        heavy)
            : "${THEME_BANNER_CHAR:=━}"
            : "${THEME_DIVIDER_CHAR:=━}"
            : "${THEME_KV_SEPARATOR:=▸}"
            : "${THEME_HEADING_STYLE:=bracketed}"
            ;;
        double)
            : "${THEME_BANNER_CHAR:=═}"
            : "${THEME_DIVIDER_CHAR:=═}"
            : "${THEME_KV_SEPARATOR:=:}"
            : "${THEME_HEADING_STYLE:=centered}"
            ;;
        dotted)
            : "${THEME_BANNER_CHAR:=┄}"
            : "${THEME_DIVIDER_CHAR:=┄}"
            : "${THEME_KV_SEPARATOR:=▸}"
            : "${THEME_HEADING_STYLE:=left}"
            ;;
        ascii)
            : "${THEME_BANNER_CHAR:=#}"
            : "${THEME_DIVIDER_CHAR:=-}"
            : "${THEME_KV_SEPARATOR:=:}"
            : "${THEME_HEADING_STYLE:=left}"
            ;;
        arrows)
            : "${THEME_BANNER_CHAR:=▶}"
            : "${THEME_DIVIDER_CHAR:=▸}"
            : "${THEME_KV_SEPARATOR:=→}"
            : "${THEME_HEADING_STYLE:=arrows}"
            ;;
        stars)
            : "${THEME_BANNER_CHAR:=★}"
            : "${THEME_DIVIDER_CHAR:=·}"
            : "${THEME_KV_SEPARATOR:=·}"
            : "${THEME_HEADING_STYLE:=stars}"
            ;;
        wave)
            : "${THEME_BANNER_CHAR:=~}"
            : "${THEME_DIVIDER_CHAR:=~}"
            : "${THEME_KV_SEPARATOR:=~}"
            : "${THEME_HEADING_STYLE:=wave}"
            ;;
        block)
            : "${THEME_BANNER_CHAR:=█}"
            : "${THEME_DIVIDER_CHAR:=▄}"
            : "${THEME_KV_SEPARATOR:=│}"
            : "${THEME_HEADING_STYLE:=bracketed}"
            ;;
        pipes)
            : "${THEME_BANNER_CHAR:=═}"
            : "${THEME_DIVIDER_CHAR:=─}"
            : "${THEME_KV_SEPARATOR:=│}"
            : "${THEME_HEADING_STYLE:=bracketed}"
            ;;
        retro)
            : "${THEME_BANNER_CHAR:==}"
            : "${THEME_DIVIDER_CHAR:==}"
            : "${THEME_KV_SEPARATOR:==}"
            : "${THEME_HEADING_STYLE:=left}"
            ;;
        compact)
            : "${THEME_BANNER_CHAR:=─}"
            : "${THEME_DIVIDER_CHAR:= }"
            : "${THEME_KV_SEPARATOR:=:}"
            : "${THEME_HEADING_STYLE:=left}"
            ;;
        chevrons)
            : "${THEME_BANNER_CHAR:=»}"
            : "${THEME_DIVIDER_CHAR:=»}"
            : "${THEME_KV_SEPARATOR:=»}"
            : "${THEME_HEADING_STYLE:=chevrons}"
            ;;
        bullets)
            : "${THEME_BANNER_CHAR:=•}"
            : "${THEME_DIVIDER_CHAR:=•}"
            : "${THEME_KV_SEPARATOR:=•}"
            : "${THEME_HEADING_STYLE:=bullets}"
            ;;
        cross)
            : "${THEME_BANNER_CHAR:=╳}"
            : "${THEME_DIVIDER_CHAR:=╳}"
            : "${THEME_KV_SEPARATOR:=╳}"
            : "${THEME_HEADING_STYLE:=bracketed}"
            ;;
        plus)
            : "${THEME_BANNER_CHAR:=+}"
            : "${THEME_DIVIDER_CHAR:=+}"
            : "${THEME_KV_SEPARATOR:=+}"
            : "${THEME_HEADING_STYLE:=left}"
            ;;
        cosmic)
            : "${THEME_BANNER_CHAR:=·}"
            : "${THEME_DIVIDER_CHAR:=·}"
            : "${THEME_KV_SEPARATOR:=◇}"
            : "${THEME_HEADING_STYLE:=stars}"
            ;;
        sharp)
            : "${THEME_BANNER_CHAR:=◢}"
            : "${THEME_DIVIDER_CHAR:=◣}"
            : "${THEME_KV_SEPARATOR:=◆}"
            : "${THEME_HEADING_STYLE:=bracketed}"
            ;;
        zen)
            : "${THEME_BANNER_CHAR:=─}"
            : "${THEME_DIVIDER_CHAR:= }"
            : "${THEME_KV_SEPARATOR:=─}"
            : "${THEME_HEADING_STYLE:=zen}"
            ;;
        custom|*)
            : "${THEME_BANNER_CHAR:==}"
            : "${THEME_DIVIDER_CHAR:=-}"
            : "${THEME_KV_SEPARATOR:=:}"
            : "${THEME_HEADING_STYLE:=centered}"
            ;;
    esac
    : "${THEME_BANNER_WIDTH:=64}"
    : "${THEME_DIVIDER_WIDTH:=55}"
    : "${THEME_HEADING_COLOR:=cyan}"
}

# COLOR_THEME swaps the accent palette used by section headings & status colors.
apply_color_theme() {
    local name="${COLOR_THEME:-default}"
    case "$name" in
        default)  THEME_ACCENT="$C_CYAN" ;;
        ocean)    THEME_ACCENT="$C_BLUE" ;;
        forest)   THEME_ACCENT="$C_GREEN" ;;
        sunset)   THEME_ACCENT="$C_MAGENTA" ;;
        amber)    THEME_ACCENT="$C_YELLOW" ;;
        mono)     THEME_ACCENT="$C_BOLD" ;;
        matrix)   THEME_ACCENT="$C_BRIGHT_GREEN" ;;
        neon)     THEME_ACCENT="$C_BRIGHT_MAGENTA" ;;
        coral)    THEME_ACCENT="$C_BRIGHT_RED" ;;
        mint)     THEME_ACCENT="$C_BRIGHT_CYAN" ;;
        sky)      THEME_ACCENT="$C_BRIGHT_BLUE" ;;
        gold)     THEME_ACCENT="$C_BRIGHT_YELLOW" ;;
        snow)     THEME_ACCENT="$C_BRIGHT_WHITE" ;;
        *)        THEME_ACCENT="$C_CYAN" ;;
    esac
}

apply_theme
apply_color_theme

# ---------- formatting helpers ----------

# Print a section heading with rule lines, respecting the active theme.
# Usage: section_heading "Title"
section_heading() {
    local title="$1"
    local total="${THEME_DIVIDER_WIDTH:-55}"
    local ch="${THEME_DIVIDER_CHAR:--}"
    local style="${THEME_HEADING_STYLE:-centered}"
    local accent="${THEME_ACCENT:-${C_CYAN}}"

    case "$style" in
        left)
            # ─── Title ─────
            local prefix
            prefix=$(_repeat_char "$ch" 3)
            local rest=$(( total - ${#title} - 5 ))
            (( rest < 1 )) && rest=1
            local tail
            tail=$(_repeat_char "$ch" "$rest")
            printf "%s%s %s%s%s %s%s\n" \
                "${C_GREY}" "$prefix" \
                "${C_BOLD}${accent}" "$title" "${C_RESET}${C_GREY}" \
                "$tail" "${C_RESET}"
            ;;
        arrows)
            # ▸▸▸ Title ▸▸▸▸▸▸…
            local prefix tail
            prefix=$(_repeat_char "$ch" 3)
            local rest=$(( total - ${#title} - 8 ))
            (( rest < 1 )) && rest=1
            tail=$(_repeat_char "$ch" "$rest")
            printf "%s%s %s%s%s %s%s\n" \
                "${C_GREY}" "$prefix" \
                "${C_BOLD}${accent}" "$title" "${C_RESET}${C_GREY}" \
                "$tail" "${C_RESET}"
            ;;
        stars)
            # ★ ★ ★  Title  ★ ★ ★
            local pad=$(( (total - ${#title} - 14) / 2 ))
            (( pad < 1 )) && pad=1
            local stars
            stars=""
            local i
            for ((i = 0; i < pad / 2; i++)); do
                stars+="★ "
            done
            printf "%s%s%s%s  %s  %s%s\n" \
                "${C_YELLOW}" "$stars" "${C_RESET}" \
                "${C_BOLD}${accent}" "$title" \
                "${C_YELLOW}" "$stars${C_RESET}"
            ;;
        wave)
            # ～～～ Title ～～～
            local prefix tail
            local pad=$(( (total - ${#title} - 4) / 2 ))
            (( pad < 1 )) && pad=1
            prefix=$(_repeat_char '～' "$pad")
            tail=$(_repeat_char '～' "$pad")
            printf "%s%s %s%s%s %s%s\n" \
                "${C_CYAN}" "$prefix" \
                "${C_BOLD}${accent}" "$title" "${C_RESET}${C_CYAN}" \
                "$tail" "${C_RESET}"
            ;;
        chevrons)
            # »»» Title «««
            local pad=$(( (total - ${#title} - 8) / 2 ))
            (( pad < 1 )) && pad=1
            local prefix tail
            prefix=$(_repeat_char '»' "$pad")
            tail=$(_repeat_char '«' "$pad")
            printf "%s%s %s%s%s %s%s\n" \
                "${C_CYAN}" "$prefix" \
                "${C_BOLD}${accent}" "$title" "${C_RESET}${C_CYAN}" \
                "$tail" "${C_RESET}"
            ;;
        bullets)
            # • • • Title • • •
            local pad=$(( (total - ${#title} - 8) / 4 ))
            (( pad < 1 )) && pad=1
            local prefix=""
            local i
            for ((i = 0; i < pad; i++)); do prefix+="• "; done
            printf "%s%s%s %s%s%s %s%s%s\n" \
                "${C_MAGENTA}" "$prefix" "${C_RESET}" \
                "${C_BOLD}${accent}" "$title" "${C_RESET}" \
                "${C_MAGENTA}" "$prefix" "${C_RESET}"
            ;;
        zen)
            # Just the title, indented and underlined.
            printf "  %s%s%s\n" "${C_BOLD}${accent}" "$title" "${C_RESET}"
            ;;
        bracketed)
            # ━━━━━[ Title ]━━━━━
            local title_padded="[ ${title} ]"
            local pad=$(( (total - ${#title_padded}) / 2 ))
            (( pad < 1 )) && pad=1
            local left right
            left=$(_repeat_char "$ch" "$pad")
            right=$(_repeat_char "$ch" $((total - pad - ${#title_padded})))
            printf "%s%s%s%s%s%s%s\n" \
                "${C_GREY}" "$left" \
                "${C_BOLD}${accent}" "$title_padded" "${C_RESET}${C_GREY}" \
                "$right" "${C_RESET}"
            ;;
        *)  # centered (default)
            local title_padded=" ${title} "
            local pad=$(( (total - ${#title_padded}) / 2 ))
            (( pad < 1 )) && pad=1
            local left right
            left=$(_repeat_char "$ch" "$pad")
            right=$(_repeat_char "$ch" $((total - pad - ${#title_padded})))
            printf "%s%s%s%s%s%s%s\n" \
                "${C_GREY}" "$left" \
                "${C_BOLD}${accent}" "$title_padded" "${C_RESET}${C_GREY}" \
                "$right" "${C_RESET}"
            ;;
    esac
}

# Plain rule line, themed.
section_rule() {
    local total="${THEME_DIVIDER_WIDTH:-55}"
    local ch="${THEME_DIVIDER_CHAR:--}"
    printf "%s%s%s\n" "${C_GREY}" "$(_repeat_char "$ch" "$total")" "${C_RESET}"
}

# Heavy rule used after the header banner.
section_thick_rule() {
    local total="${THEME_BANNER_WIDTH:-64}"
    local ch="${THEME_BANNER_CHAR:==}"
    printf "%s%s%s\n" "${C_GREY}" "$(_repeat_char "$ch" "$total")" "${C_RESET}"
}

# Print a labeled line: "  Label    : value"
kv() {
    local label="$1" value="$2" color="${3:-}"
    local sep="${THEME_KV_SEPARATOR:-:}"
    printf " %-10s %s %s%s%s\n" "$label" "$sep" "$color" "$value" "${C_RESET:-}"
}

# Internal: repeat a single character N times. Handles multi-byte UTF-8 chars
# (─, ═, ━, ┄) by avoiding `tr` (which counts bytes, not characters).
_repeat_char() {
    local ch="$1" n="$2" out="" i
    for ((i = 0; i < n; i++)); do
        out+="$ch"
    done
    printf '%s' "$out"
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

# Source a KV-style cache file (e.g. /var/cache/smart-motd/security.kv).
# Returns 1 if the file is missing or empty.
cache_kv_load() {
    local name="$1"
    local path="${SMART_MOTD_CACHE_DIR}/${name}.kv"
    [[ -s "$path" ]] || return 1
    # shellcheck disable=SC1090
    . "$path"
}
