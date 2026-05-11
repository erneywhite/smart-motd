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
# wttr.in's %l format echoes "Latitude,Longitude" when no city is specified
# (it geolocates by IP but doesn't reverse it to a name). When the user
# leaves WEATHER_CITY blank, do an explicit IP-geolocation lookup first
# and pass the city name to wttr.in so we get a proper "Berlin: ☀ +21°C"
# line instead of "53.001100,28.006500: ☀ +21°C".
cache_update_weather() {
    [[ "${WEATHER_ENABLED:-false}" == "true" ]] || { cache_write "weather" ""; return; }
    have curl || { cache_write "weather" ""; return; }

    local city="${WEATHER_CITY:-}"
    if [[ -z "$city" ]]; then
        # Try a few free IP→city services in order. Each is short and
        # doesn't require an API key.
        city=$(curl -fsS --max-time 4 https://ipapi.co/city/ 2>/dev/null || true)
        if [[ -z "$city" || "$city" == *"error"* ]]; then
            city=$(curl -fsS --max-time 4 https://ifconfig.co/city 2>/dev/null || true)
        fi
        if [[ -z "$city" ]]; then
            # ipinfo.io is rate-limited but worth one shot
            city=$(curl -fsS --max-time 4 https://ipinfo.io/city 2>/dev/null || true)
        fi
        # Strip any whitespace / control chars
        city="${city//[$'\r\n\t']/}"
        city="${city## }"; city="${city%% }"
    fi

    local out
    if [[ -n "$city" ]]; then
        out=$(curl -fsS --max-time 5 "https://wttr.in/${city// /+}?format=%l:+%c+%t,+%C" 2>/dev/null || true)
    else
        # Last-resort fallback: ask wttr without a location and strip the
        # coordinates prefix wttr returns by default.
        out=$(curl -fsS --max-time 5 "https://wttr.in/?format=%c+%t,+%C" 2>/dev/null || true)
    fi
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

# ---- 24-hour rolling history of load average + memory % ----
# Each cache run appends a single line ('<epoch> <value>') to the sample
# files. Anything older than 24h is pruned in-place. Average over the
# resulting samples gives the daily mean used by the Telegram recap.

_history_append() {
    local file="$1" value="$2" now cutoff tmp
    now=$(date +%s)
    cutoff=$((now - 86400))
    tmp="${file}.tmp"
    # Append + filter in one pass: read existing lines >= cutoff, then
    # the new sample, into a temp file. mv -f makes the swap atomic.
    {
        [[ -r "$file" ]] && awk -v c="$cutoff" '$1 >= c' "$file"
        printf '%d %s\n' "$now" "$value"
    } > "$tmp" && mv -f "$tmp" "$file"
}

cache_update_load_history() {
    [[ -r /proc/loadavg ]] || return
    local load1
    load1=$(awk '{print $1}' /proc/loadavg)
    [[ -z "$load1" ]] && return
    _history_append "$SMART_MOTD_CACHE_DIR/load_samples" "$load1"
}

cache_update_mem_history() {
    [[ -r /proc/meminfo ]] || return
    local pct
    pct=$(awk '
        /^MemTotal:/      { total = $2 }
        /^MemAvailable:/  { avail = $2 }
        END {
            if (total > 0) printf "%d", (total - avail) * 100 / total
            else            printf "0"
        }
    ' /proc/meminfo)
    [[ -z "$pct" ]] && return
    _history_append "$SMART_MOTD_CACHE_DIR/mem_samples" "$pct"
}

# ---- upgrade-available check ----
# Hits GitHub releases/latest to find the newest published version, compares
# against the locally-installed VERSION file, and stores the new version
# string in the cache when an upgrade is available (otherwise empty).
# Network failures preserve the previous cache value (no false "up-to-date"
# claim from a transient curl error).
cache_update_version_check() {
    have curl || { cache_write "upgrade_available" ""; return; }
    local local_v latest_v older
    local_v=$(cat "${SMART_MOTD_PREFIX:-/usr/local/lib/smart-motd}/VERSION" 2>/dev/null | tr -d ' \r\n')
    [[ -z "$local_v" ]] && return

    latest_v=$(curl -fsS --max-time 4 \
        "https://api.github.com/repos/erneywhite/smart-motd/releases/latest" 2>/dev/null \
        | grep '"tag_name"' \
        | head -1 \
        | sed -E 's/.*"v?([^"]+)".*/\1/')
    # Network / parse failure → keep whatever we had, don't clobber to empty.
    [[ -z "$latest_v" ]] && return

    if [[ "$latest_v" == "$local_v" ]]; then
        cache_write "upgrade_available" ""
        return
    fi
    # Use natural-version sort to make sure latest is actually newer
    # (don't show "upgrade available" if the local install is somehow
    # ahead — e.g. someone running off main between releases).
    older=$(printf '%s\n%s\n' "$local_v" "$latest_v" | sort -V | head -1)
    if [[ "$older" == "$local_v" ]]; then
        cache_write "upgrade_available" "$latest_v"
    else
        cache_write "upgrade_available" ""
    fi
}

# ---- network rx/tx rates ----
# Read /sys/class/net/<iface>/statistics/{rx,tx}_bytes counters now,
# diff against the snapshot from the previous cache run, and store
# bytes/sec rates per interface. The window equals the time between
# two cache updates — by default that's the 5-minute systemd timer,
# i.e. a 5-minute moving average. On the first run no previous
# snapshot exists yet, so the rates file stays empty for one tick.
cache_update_network_rates() {
    local snapshot="${SMART_MOTD_CACHE_DIR}/network_rates_snapshot"
    local now current=""
    now=$(date +%s)

    local iface_dir iface rx tx
    for iface_dir in /sys/class/net/*/; do
        [[ -d "$iface_dir" ]] || continue
        iface=$(basename "$iface_dir")
        [[ "$iface" == "lo" ]] && continue
        [[ -r "$iface_dir/statistics/rx_bytes" ]] || continue
        rx=$(<"$iface_dir/statistics/rx_bytes")
        tx=$(<"$iface_dir/statistics/tx_bytes")
        current+="${iface}|${rx}|${tx}"$'\n'
    done

    local rates=""
    if [[ -r "$snapshot" ]]; then
        local prev_time elapsed prev_line prev_iface prev_rx prev_tx
        prev_time=$(head -1 "$snapshot")
        elapsed=$((now - prev_time))
        if (( elapsed > 0 )); then
            local line c_iface c_rx c_tx rx_rate tx_rate
            while IFS='|' read -r c_iface c_rx c_tx; do
                [[ -z "$c_iface" ]] && continue
                # find matching iface in previous snapshot
                prev_line=$(grep -m1 "^${c_iface}|" "$snapshot" 2>/dev/null) || prev_line=""
                [[ -z "$prev_line" ]] && continue
                IFS='|' read -r prev_iface prev_rx prev_tx <<<"$prev_line"
                rx_rate=$(( (c_rx - prev_rx) / elapsed ))
                tx_rate=$(( (c_tx - prev_tx) / elapsed ))
                # clamp negatives (counter reset on interface bounce)
                (( rx_rate < 0 )) && rx_rate=0
                (( tx_rate < 0 )) && tx_rate=0
                rates+="${c_iface}|${rx_rate}|${tx_rate}|${elapsed}"$'\n'
            done <<<"$current"
        fi
    fi

    # Save the new snapshot (timestamp on first line, then iface|rx|tx rows)
    {
        printf '%d\n' "$now"
        printf '%s' "$current"
    } > "$snapshot"

    cache_write "network_rates" "$rates"
}

# ---- VPN tunnels (WireGuard + OpenVPN) ----
# WireGuard requires root for `wg show`, which is why we cache (this job
# runs as root via systemd; the on-login generator may not be).
# OpenVPN: just the active systemd unit count is cheap, but we cache it
# alongside for consistency.
# Output (one line per tunnel):
#   wg|<iface>|<active_peers>|<total_peers>
#   openvpn|<unit-name-stripped>|<active|inactive>|
cache_update_vpn() {
    local out="" iface unit
    if have wg; then
        local now active total ts pubkey
        now=$(date +%s)
        while IFS= read -r iface; do
            [[ -z "$iface" ]] && continue
            active=0; total=0
            while IFS=$'\t' read -r pubkey ts; do
                [[ -z "$pubkey" ]] && continue
                total=$((total + 1))
                # Active = handshake within last 3 minutes (default keepalive timing)
                if [[ "$ts" =~ ^[0-9]+$ ]] && (( ts > 0 )) && (( now - ts < 180 )); then
                    active=$((active + 1))
                fi
            done < <(wg show "$iface" latest-handshakes 2>/dev/null)
            out+="wg|${iface}|${active}|${total}"$'\n'
        done < <(wg show interfaces 2>/dev/null | tr ' ' '\n')
    fi
    if have systemctl; then
        local pattern state name
        while IFS= read -r unit; do
            [[ -z "$unit" ]] && continue
            state=$(systemctl is-active "$unit" 2>/dev/null || echo unknown)
            # Strip ".service" and "openvpn-server@" / "openvpn@" / "openvpn-client@" prefix
            name="${unit%.service}"
            name="${name#openvpn-server@}"
            name="${name#openvpn-client@}"
            name="${name#openvpn@}"
            out+="openvpn|${name}|${state}|"$'\n'
        done < <(systemctl list-units --all --no-legend --plain --type=service 2>/dev/null \
                   | awk '{print $1}' \
                   | grep -E '^openvpn(-server|-client)?@?[^.]*\.service$')
    fi
    cache_write "vpn" "$out"
}

# ---- ZFS pools ----
# Output (one line per pool): pool|state|capacity
cache_update_zpool() {
    have zpool || { cache_write "zpool" ""; return; }
    local out="" pool state cap
    while IFS= read -r pool; do
        [[ -z "$pool" ]] && continue
        state=$(zpool list -H -o health "$pool" 2>/dev/null)
        cap=$(zpool list -H -o capacity "$pool" 2>/dev/null)
        out+="${pool}|${state:-?}|${cap:-?}"$'\n'
    done < <(zpool list -H -o name 2>/dev/null)
    cache_write "zpool" "$out"
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
    cache_update_security
    cache_update_docker
    cache_update_podman
    cache_update_kubernetes
    cache_update_vpn
    cache_update_zpool
    cache_update_network_rates
    cache_update_version_check
    cache_update_load_history
    cache_update_mem_history
}
