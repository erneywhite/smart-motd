#!/usr/bin/env bash
# Storage arrays — Linux mdadm + ZFS pools.
# mdadm parsed live from /proc/mdstat (fast).
# ZFS comes from cache (zpool status can be slow during scrub).

section_raid() {
    [[ "${RAID_ENABLED:-auto}" == "false" ]] && return

    local has_md=false has_zfs=false zpool_data
    if [[ -r /proc/mdstat ]] && grep -q '^md' /proc/mdstat 2>/dev/null; then
        has_md=true
    fi
    zpool_data=$(cache_read "zpool" "")
    [[ -n "$zpool_data" ]] && has_zfs=true

    $has_md || $has_zfs || return

    section_heading "Storage arrays"

    if $has_md; then
        local md_status md_color md_count
        md_count=$(grep -c '^md' /proc/mdstat 2>/dev/null)
        if grep -qE '_[U_]*\]' /proc/mdstat 2>/dev/null; then
            md_status="DEGRADED"; md_color="${C_RED}"
        elif grep -qE 'recovery|resync|check|reshape' /proc/mdstat 2>/dev/null; then
            md_status="rebuilding"; md_color="${C_YELLOW}"
        else
            md_status="OK"; md_color="${C_GREEN}"
        fi
        kv "mdadm" "${md_count} array(s) — ${md_status}" "$md_color"
    fi

    if $has_zfs; then
        local pool state cap line color label
        while IFS='|' read -r pool state cap; do
            [[ -z "$pool" ]] && continue
            case "$state" in
                ONLINE)   color="${C_GREEN}" ;;
                DEGRADED) color="${C_RED}" ;;
                FAULTED|UNAVAIL|REMOVED) color="${C_RED}" ;;
                *)        color="${C_YELLOW}" ;;
            esac
            label="zpool ${pool}"
            (( ${#label} > 10 )) && label="${label:0:10}"
            kv "$label" "${state}, ${cap} used" "$color"
        done <<<"$zpool_data"
    fi
    section_rule
}
