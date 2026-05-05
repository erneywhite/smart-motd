#!/usr/bin/env bash
# smart-motd: cache update routines.
# These produce the cached snippets that the on-login generator just cats.
# Each cache file holds the *fully formatted* line(s) for that value, so that
# the on-login path stays cheap.

# shellcheck source=common.sh
. "${SMART_MOTD_PREFIX:-/usr/local/lib/smart-motd}/lib/common.sh"

mkdir -p "$SMART_MOTD_CACHE_DIR"

# Force colors when running from cache updater (output goes to file, not tty).
SMART_MOTD_FORCE_COLOR=1
_color_init

# ---------- cache writers ----------

cache_write() {
    local name="$1" content="$2"
    local tmp="${SMART_MOTD_CACHE_DIR}/.${name}.tmp"
    printf '%s' "$content" >"$tmp"
    mv -f "$tmp" "${SMART_MOTD_CACHE_DIR}/${name}"
}

# ---- updates available (apt/dnf/yum/zypper/pacman/apk) ----
cache_update_packages() {
    local count=0 security=0
    case "$DISTRO_FAMILY" in
        debian)
            if have apt-get; then
                # /var/lib/apt/lists must be fresh-ish; we don't run apt-get update here
                # to avoid hammering mirrors. Operators run that separately (or unattended-upgrades).
                if have apt; then
                    local out
                    out=$(LC_ALL=C apt list --upgradable 2>/dev/null | tail -n +2)
                    count=$(printf '%s\n' "$out" | grep -c .)
                    security=$(printf '%s\n' "$out" | grep -c -i 'security')
                fi
            fi
            ;;
        rhel)
            if have dnf; then
                count=$(LC_ALL=C dnf -q check-update 2>/dev/null | grep -cE '^\S+\s+\S+\s+\S+$' || true)
                security=$(LC_ALL=C dnf -q updateinfo list security 2>/dev/null | grep -cE '^\S+\s+\S+\s+\S+$' || true)
            elif have yum; then
                count=$(LC_ALL=C yum -q check-update 2>/dev/null | grep -cE '^\S+\s+\S+\s+\S+$' || true)
                security=$(LC_ALL=C yum -q --security check-update 2>/dev/null | grep -cE '^\S+\s+\S+\s+\S+$' || true)
            fi
            ;;
        suse)
            if have zypper; then
                count=$(LC_ALL=C zypper --quiet list-updates 2>/dev/null | grep -cE '^v |^  ' || true)
            fi
            ;;
        arch)
            if have checkupdates; then
                count=$(checkupdates 2>/dev/null | wc -l)
            elif have pacman; then
                count=$(pacman -Qu 2>/dev/null | wc -l)
            fi
            ;;
        alpine)
            if have apk; then
                count=$(apk version -l '<' 2>/dev/null | tail -n +2 | wc -l)
            fi
            ;;
    esac

    cache_write "packages_count" "$count"
    cache_write "packages_security" "$security"
}

# ---- public IP ----
cache_update_public_ip() {
    local ip=""
    if have curl; then
        ip=$(curl -fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)
        [[ -z "$ip" ]] && ip=$(curl -fsS --max-time 4 https://ifconfig.me 2>/dev/null || true)
    elif have wget; then
        ip=$(wget -qO- --timeout=4 https://api.ipify.org 2>/dev/null || true)
    fi
    cache_write "public_ip" "${ip:-unavailable}"
}

# ---- ssl certs ----
# Output one line per cert: "domain|days_left|status"
# status: ok | warn | expired | error
cache_update_ssl() {
    : "${SSL_WARN_DAYS:=14}"
    local lines=""

    _check_pem() {
        local pem="$1" label="$2"
        local exp_str days_left now exp_epoch
        exp_str=$(openssl x509 -enddate -noout -in "$pem" 2>/dev/null | sed 's/notAfter=//')
        if [[ -z "$exp_str" ]]; then
            printf '%s|?|error\n' "$label"
            return
        fi
        # GNU date and BSD date both eat openssl's format ("Jan  1 12:00:00 2030 GMT") in slightly different ways.
        if exp_epoch=$(date -d "$exp_str" +%s 2>/dev/null); then :;
        elif exp_epoch=$(date -j -f "%b %e %T %Y %Z" "$exp_str" +%s 2>/dev/null); then :;
        else
            printf '%s|?|error\n' "$label"
            return
        fi
        now=$(date +%s)
        days_left=$(( (exp_epoch - now) / 86400 ))
        local st="ok"
        (( days_left < 0 )) && st="expired"
        (( days_left >= 0 && days_left <= SSL_WARN_DAYS )) && st="warn"
        printf '%s|%d|%s\n' "$label" "$days_left" "$st"
    }

    _check_remote() {
        local target="$1" host port
        if [[ "$target" == *:* ]]; then
            host="${target%:*}"; port="${target##*:}"
        else
            host="$target"; port=443
        fi
        local exp_str days_left now exp_epoch
        exp_str=$(echo | timeout 5 openssl s_client -servername "$host" -connect "$host:$port" 2>/dev/null \
            | openssl x509 -enddate -noout 2>/dev/null | sed 's/notAfter=//')
        if [[ -z "$exp_str" ]]; then
            printf '%s|?|error\n' "$target"
            return
        fi
        if exp_epoch=$(date -d "$exp_str" +%s 2>/dev/null); then :;
        elif exp_epoch=$(date -j -f "%b %e %T %Y %Z" "$exp_str" +%s 2>/dev/null); then :;
        else
            printf '%s|?|error\n' "$target"
            return
        fi
        now=$(date +%s)
        days_left=$(( (exp_epoch - now) / 86400 ))
        local st="ok"
        (( days_left < 0 )) && st="expired"
        (( days_left >= 0 && days_left <= SSL_WARN_DAYS )) && st="warn"
        printf '%s|%d|%s\n' "$target" "$days_left" "$st"
    }

    if ! have openssl; then
        cache_write "ssl" ""
        return
    fi

    if [[ "${SSL_AUTODISCOVER_LETSENCRYPT:-true}" == "true" && -d /etc/letsencrypt/live ]]; then
        local d
        for d in /etc/letsencrypt/live/*/; do
            [[ -d "$d" ]] || continue
            local name pem
            name=$(basename "$d")
            [[ "$name" == "README" ]] && continue
            pem="${d}cert.pem"
            [[ -r "$pem" ]] || continue
            lines+="$(_check_pem "$pem" "$name")"$'\n'
        done
    fi

    local item
    for item in "${SSL_DOMAINS[@]:-}"; do
        [[ -z "$item" ]] && continue
        if [[ -f "$item" ]]; then
            lines+="$(_check_pem "$item" "$(basename "$(dirname "$item")")")"$'\n'
        else
            lines+="$(_check_remote "$item")"$'\n'
        fi
    done

    cache_write "ssl" "$lines"
}

# ---- weather ----
cache_update_weather() {
    [[ "${WEATHER_ENABLED:-false}" == "true" ]] || { cache_write "weather" ""; return; }
    have curl || { cache_write "weather" ""; return; }
    local city="${WEATHER_CITY:-}"
    local out
    # Format: "City: 21°C, Sunny"  (wttr.in supports a custom format)
    out=$(curl -fsS --max-time 5 "https://wttr.in/${city}?format=%l:+%c+%t,+%C" 2>/dev/null || true)
    cache_write "weather" "${out:-unavailable}"
}

# ---- directory sizes ----
# Output one line per configured dir: "label|path|human_size"
cache_update_directories() {
    [[ "${DIRECTORIES_ENABLED:-false}" == "true" ]] || { cache_write "directories" ""; return; }
    local lines="" entry
    for entry in "${DIRECTORIES_LIST[@]:-}"; do
        [[ -z "$entry" ]] && continue
        local label="${entry%%|*}" path="${entry##*|}"
        local size="missing"
        if [[ -e "$path" ]]; then
            size=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
            [[ -z "$size" ]] && size="?"
        fi
        lines+="${label}|${path}|${size}"$'\n'
    done
    cache_write "directories" "$lines"
}

# ---- SMART summary ----
# Output one line per disk: "device|model|temp|health"
cache_update_smart() {
    have smartctl || { cache_write "smart" ""; return; }

    local disks=()
    if [[ "${SMART_ENABLED:-auto}" == "auto" ]] || [[ ${#SMART_DISKS[@]} -eq 0 ]]; then
        # auto-detect via smartctl
        local d
        while IFS= read -r d; do
            [[ -n "$d" ]] && disks+=("$d")
        done < <(smartctl --scan 2>/dev/null | awk '{print $1}' | head -20)
    else
        disks=("${SMART_DISKS[@]}")
    fi

    local lines="" dev
    for dev in "${disks[@]}"; do
        local info temp health model
        info=$(smartctl -i -A -H "$dev" 2>/dev/null) || continue
        model=$(printf '%s\n' "$info" | awk -F': *' '/Device Model|Model Number/ {print $2; exit}')
        [[ -z "$model" ]] && model="$(basename "$dev")"
        health=$(printf '%s\n' "$info" | awk -F': *' '/SMART overall-health|SMART Health Status/ {print $2; exit}')
        [[ -z "$health" ]] && health="?"
        temp=$(printf '%s\n' "$info" | awk '/Temperature_Celsius|Current Drive Temperature|Temperature:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/ && $i+0 > 0 && $i+0 < 120) { print $i; exit }}')
        [[ -z "$temp" ]] && temp="?"
        lines+="${dev}|${model}|${temp}|${health}"$'\n'
    done

    cache_write "smart" "$lines"
}

# ---- driver ----
cache_update_all() {
    detect_distro
    cache_update_packages
    cache_update_public_ip
    cache_update_ssl
    cache_update_weather
    cache_update_directories
    cache_update_smart
}
