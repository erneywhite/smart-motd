#!/usr/bin/env bash
# Security: failed SSH attempts (24h) + fail2ban summary. Reads from cache.

section_security() {
    local FAILED_SSH=0 FAIL2BAN_JAILS="" FAIL2BAN_BANNED=0
    cache_kv_load security || true

    # Skip the section entirely if nothing to report.
    if [[ "$FAILED_SSH" == "0" ]] && [[ -z "$FAIL2BAN_JAILS" ]]; then
        return
    fi

    section_heading "Security"

    local color
    if [[ "$FAILED_SSH" -gt 50 ]]; then color="${C_RED}"
    elif [[ "$FAILED_SSH" -gt 10 ]]; then color="${C_YELLOW}"
    else color="${C_GREEN}"
    fi
    kv "SSH fails" "${FAILED_SSH} in last 24h" "$color"

    if [[ -n "$FAIL2BAN_JAILS" ]]; then
        local jail_count
        jail_count=$(printf '%s\n' $FAIL2BAN_JAILS | grep -c .)
        if [[ "$FAIL2BAN_BANNED" -gt 0 ]]; then color="${C_YELLOW}"; else color="${C_GREEN}"; fi
        kv "fail2ban" "${FAIL2BAN_BANNED} banned across ${jail_count} jail(s)" "$color"
    fi
    section_rule
}
