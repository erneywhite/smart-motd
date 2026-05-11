#!/usr/bin/env bash
# Updates available: read from cache (populated by motd-cache-update).

section_updates() {
    local count security age reboot
    count=$(cache_read "packages_count" "")
    security=$(cache_read "packages_security" "")
    reboot=$(cache_read "packages_reboot_required" "no")
    age=$(cache_age "packages_count")

    # Don't show the section if cache is empty AND we have no count yet
    [[ -z "$count" ]] && return

    section_heading "Package updates"

    if [[ "$age" == "never" ]]; then
        kv "Updates" "cache not populated yet"
        section_rule
        return
    fi

    local color
    if [[ "$count" -eq 0 ]]; then
        color="${C_GREEN}"
        kv "Updates" "0 (system up to date)" "$color"
    else
        if [[ "${security:-0}" -gt 0 ]]; then
            color="${C_RED}"
            kv "Updates" "$count available, ${security} security" "$color"
        else
            color="${C_YELLOW}"
            kv "Updates" "$count available" "$color"
        fi
    fi

    if [[ "$reboot" == "yes" ]]; then
        kv "Reboot" "required (kernel/library update applied)" "${C_RED}"
    fi

    # Hint: how stale the data is
    local age_min=$(( age / 60 ))
    if (( age_min > 60 )); then
        kv "Checked" "${C_DIM}$((age_min/60))h $((age_min%60))m ago${C_RESET}"
    else
        kv "Checked" "${C_DIM}${age_min}m ago${C_RESET}"
    fi
    section_rule
}
