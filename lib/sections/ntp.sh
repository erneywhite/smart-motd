#!/usr/bin/env bash
# NTP / time sync status. Best-effort across systemd-timesyncd, chrony,
# and traditional ntpd. Skipped silently when no time-sync service is running.

_ntp_from_timedatectl() {
    have timedatectl || return 1
    local td
    td=$(timedatectl show 2>/dev/null) || return 1

    # Only proceed if NTP is enabled in some way.
    [[ "$td" == *"NTP=yes"* ]] || return 1

    local synced="no"
    [[ "$td" == *"NTPSynchronized=yes"* ]] && synced="yes"

    # Server name + offset from systemd-timesyncd's show-timesync (when present)
    local server="" offset_us="" offset=""
    if timedatectl show-timesync >/dev/null 2>&1; then
        local ts
        ts=$(timedatectl show-timesync 2>/dev/null)
        server=$(awk -F= '/^ServerName=/ {print $2; exit}' <<<"$ts")
        offset_us=$(awk -F= '/^.*Offset=/ {print $2; exit}' <<<"$ts")
    fi
    if [[ -n "$offset_us" ]]; then
        offset=$(awk "BEGIN {v=${offset_us}/1000; s=(v<0)?\"-\":\"+\"; if(v<0)v=-v; printf \"%s%.1f ms\", s, v}")
    fi

    printf '%s|%s|%s' "$synced" "$server" "$offset"
}

_ntp_from_chrony() {
    have chronyc || return 1
    local chr
    chr=$(chronyc tracking 2>/dev/null) || return 1
    local synced="yes" server offset
    [[ "$chr" == *"Leap status     : Not synchronised"* ]] && synced="no"
    server=$(awk -F': *' '/Reference ID/ {print $2; exit}' <<<"$chr" | awk '{print $2}' | tr -d '()')
    offset=$(awk -F': *' '/Last offset/ {print $2; exit}' <<<"$chr")
    printf '%s|%s|%s' "$synced" "${server:-?}" "${offset:-?}"
}

_ntp_from_ntpq() {
    have ntpq || return 1
    local nt
    nt=$(ntpq -p 2>/dev/null) || return 1
    local server synced="no"
    server=$(awk '/^\*/ {print substr($1,2); exit}' <<<"$nt")
    [[ -n "$server" ]] && synced="yes"
    printf '%s|%s|' "$synced" "${server:-?}"
}

section_ntp() {
    [[ "${NTP_ENABLED:-auto}" == "false" ]] && return

    local raw
    raw=$(_ntp_from_timedatectl) \
        || raw=$(_ntp_from_chrony) \
        || raw=$(_ntp_from_ntpq) \
        || return

    IFS='|' read -r synced server offset <<<"$raw"

    section_heading "Time sync"
    [[ -n "$server" && "$server" != "?" ]] && kv "Server" "$server"
    [[ -n "$offset" && "$offset" != "?" ]] && kv "Offset" "$offset"
    if [[ "$synced" == "yes" ]]; then
        kv "Status" "synchronised" "${C_GREEN}"
    else
        kv "Status" "NOT synchronised" "${C_RED}"
    fi
    section_rule
}
