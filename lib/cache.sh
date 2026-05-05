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

# ---- security: failed SSH attempts (24h) + fail2ban ----
# journalctl --since 24h with thousands of matches can take 1-2s on busy hosts;
# fail2ban-client status is dbus-ish and similarly slow.
cache_update_security() {
    local failed=0 jails="" banned_total=0

    if have journalctl; then
        failed=$(journalctl _COMM=sshd --since "24 hours ago" --no-pager 2>/dev/null \
            | grep -cEi 'failed password|invalid user' || true)
    else
        local f
        for f in /var/log/auth.log /var/log/secure; do
            [[ -r "$f" ]] || continue
            failed=$(grep -cEi 'failed password|invalid user' "$f" 2>/dev/null || echo 0)
            break
        done
    fi
    failed="${failed:-0}"

    if have fail2ban-client; then
        jails=$(fail2ban-client status 2>/dev/null | awk -F': *' '/Jail list/ {print $2}' \
            | tr ',' '\n' | sed 's/^ *//;s/ *$//' | tr '\n' ' ' | sed 's/ *$//')
        local jail count
        for jail in $jails; do
            count=$(fail2ban-client status "$jail" 2>/dev/null | awk -F': *' '/Currently banned/ {print $2}' | tr -d ' \t')
            count="${count:-0}"
            banned_total=$(( banned_total + count ))
        done
    fi

    {
        printf 'FAILED_SSH=%s\n' "${failed:-0}"
        printf 'FAIL2BAN_JAILS=%s\n' "$(qstr "$jails")"
        printf 'FAIL2BAN_BANNED=%s\n' "${banned_total:-0}"
    } | _cache_kv_write security
}

# ---- docker (and podman): containers list ----
cache_update_docker() {
    have docker || { _cache_kv_write docker <<<""; return; }
    docker info >/dev/null 2>&1 || { _cache_kv_write docker <<<""; return; }

    local total running rows filter="${DOCKER_FILTER:-}"
    total=$(docker ps -a --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
    running=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
    if [[ -n "$filter" ]]; then
        rows=$(docker ps --format '{{.Names}}|{{.Status}}' 2>/dev/null | grep -E "$filter" || true)
    else
        rows=$(docker ps --format '{{.Names}}|{{.Status}}' 2>/dev/null)
    fi

    {
        printf 'TOTAL=%s\n' "${total:-0}"
        printf 'RUNNING=%s\n' "${running:-0}"
        printf 'CONTAINERS=%s\n' "$(qstr "$rows")"
    } | _cache_kv_write docker
}

cache_update_podman() {
    have podman || { _cache_kv_write podman <<<""; return; }
    # If docker is the same binary as podman, skip to avoid duplicate output.
    if have docker; then
        local same
        same=$(readlink -f "$(command -v docker)" 2>/dev/null || true)
        if [[ "$same" == *podman* ]]; then
            _cache_kv_write podman <<<""
            return
        fi
    fi

    local total running rows
    total=$(podman ps -a --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
    running=$(podman ps --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
    rows=$(podman ps --format '{{.Names}}|{{.Status}}' 2>/dev/null)

    {
        printf 'TOTAL=%s\n' "${total:-0}"
        printf 'RUNNING=%s\n' "${running:-0}"
        printf 'CONTAINERS=%s\n' "$(qstr "$rows")"
    } | _cache_kv_write podman
}

# ---- kubernetes: cluster summary ----
cache_update_kubernetes() {
    have kubectl || { _cache_kv_write kubernetes <<<""; return; }
    local ctx ready total ns
    ctx=$(kubectl config current-context 2>/dev/null) || { _cache_kv_write kubernetes <<<""; return; }
    [[ -z "$ctx" ]] && { _cache_kv_write kubernetes <<<""; return; }
    if ! kubectl get --raw=/healthz >/dev/null 2>&1; then
        _cache_kv_write kubernetes <<<""
        return
    fi
    total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {c++} END {print c+0}')
    ns=$(kubectl get ns --no-headers 2>/dev/null | wc -l | tr -d ' ')

    {
        printf 'CONTEXT=%s\n' "$(qstr "$ctx")"
        printf 'NODES_READY=%s\n' "${ready:-0}"
        printf 'NODES_TOTAL=%s\n' "${total:-0}"
        printf 'NS_COUNT=%s\n' "${ns:-0}"
    } | _cache_kv_write kubernetes
}

# Internal: write KV-style cache file (sourceable by section).
# Reads stdin → cache file. Atomic via temp+rename.
_cache_kv_write() {
    local name="$1"
    local tmp="${SMART_MOTD_CACHE_DIR}/.${name}.kv.tmp"
    cat >"$tmp"
    mv -f "$tmp" "${SMART_MOTD_CACHE_DIR}/${name}.kv"
}

# Quote for safe inclusion in a sourceable bash file.
qstr() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

# cache_kv_load is defined in common.sh and re-used here.

# ---- driver ----
cache_update_all() {
    detect_distro
    cache_update_packages
    cache_update_public_ip
    cache_update_ssl
    cache_update_weather
    cache_update_directories
    cache_update_smart
    cache_update_security
    cache_update_docker
    cache_update_podman
    cache_update_kubernetes
}
