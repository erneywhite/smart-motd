#!/usr/bin/env bash
# System status: hostname, uptime, load, memory, disk(s), sessions.

_human_uptime() {
    # Read from /proc/uptime (seconds), format as "X days, Y hours, Z minutes".
    local secs
    secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null) || { uptime -p 2>/dev/null | sed 's/^up //'; return; }
    local days=$(( secs / 86400 ))
    local hours=$(( (secs % 86400) / 3600 ))
    local mins=$(( (secs % 3600) / 60 ))
    local out=""
    (( days > 0 )) && out+="$days day$( ((days!=1)) && echo s ), "
    (( hours > 0 )) && out+="$hours hour$( ((hours!=1)) && echo s ), "
    out+="$mins minute$( ((mins!=1)) && echo s )"
    printf '%s' "$out"
}

_load_line() {
    if [[ -r /proc/loadavg ]]; then
        awk '{printf "%s, %s, %s", $1, $2, $3}' /proc/loadavg
    else
        uptime | sed 's/.*load average[s]*: //'
    fi
}

_mem_line() {
    if [[ -r /proc/meminfo ]]; then
        awk '
            /^MemTotal:/   { total = $2 }
            /^MemAvailable:/ { avail = $2 }
            END {
                used_mb = int((total - avail) / 1024)
                total_mb = int(total / 1024)
                pct = (total > 0) ? int((total - avail) * 100 / total) : 0
                printf "%d / %d MB|%d", used_mb, total_mb, pct
            }
        ' /proc/meminfo
    else
        printf '?|0'
    fi
}

_disk_line() {
    local mp="$1"
    df -hP "$mp" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); printf "%s / %s (%s%% used)|%s", $3, $2, $5, $5}'
}

_os_pretty_name() {
    if [[ -r /etc/os-release ]]; then
        # Source in a subshell so we don't leak ID/PRETTY_NAME/etc into the
        # caller's environment.
        ( . /etc/os-release; printf '%s' "${PRETTY_NAME:-${NAME:-}${VERSION_ID:+ ${VERSION_ID}}}" )
    fi
}

section_system() {
    section_heading "System status"
    kv "Hostname" "$(hostname -f 2>/dev/null || hostname)"
    local os
    os=$(_os_pretty_name)
    [[ -n "$os" ]] && kv "OS" "$os"
    kv "Uptime"   "$(_human_uptime)"
    kv "Load"     "$(_load_line)"

    local mem_raw mem_text mem_pct mem_color
    mem_raw=$(_mem_line)
    mem_text="${mem_raw%|*}"
    mem_pct="${mem_raw##*|}"
    mem_color=$(pct_color "$mem_pct")
    kv "Memory" "$mem_text" "$mem_color"

    local mp disk_raw disk_text disk_pct disk_color label
    for mp in "${SYSTEM_DISK_PATHS[@]:-/}"; do
        disk_raw=$(_disk_line "$mp")
        if [[ -z "$disk_raw" ]]; then
            continue
        fi
        disk_text="${disk_raw%|*}"
        disk_pct="${disk_raw##*|}"
        disk_color=$(pct_color "$disk_pct")
        label="Disk $mp"
        # truncate long mountpoint labels
        (( ${#label} > 10 )) && label="${label:0:10}"
        kv "$label" "$disk_text" "$disk_color"
    done

    local sessions
    sessions=$(who 2>/dev/null | wc -l | tr -d ' ')
    kv "Sessions" "${sessions:-0} active login(s)"

    section_rule
}
