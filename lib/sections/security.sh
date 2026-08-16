#!/usr/bin/env bash
# Security: failed SSH attempts (24h) + fail2ban summary. Reads from cache.

section_security() {
    local FAILED_SSH=0 FAIL2BAN_JAILS="" FAIL2BAN_BANNED=0
    local FAIL2BAN_PRESENT=0 FAIL2BAN_RUNNING=0
    cache_kv_load security || true

    # Skip the section entirely if nothing to report. An installed fail2ban is
    # always worth a line — including (especially) when it isn't actually
    # protecting anything.
    if [[ "$FAILED_SSH" == "0" ]] && [[ "$FAIL2BAN_PRESENT" != "1" ]]; then
        return
    fi

    section_heading "Security"

    local color
    if [[ "$FAILED_SSH" -gt 50 ]]; then color="${C_RED}"
    elif [[ "$FAILED_SSH" -gt 10 ]]; then color="${C_YELLOW}"
    else color="${C_GREEN}"
    fi
    kv "SSH fails" "${FAILED_SSH} in last 24h" "$color"

    # FAIL2BAN_JAILS is whitespace when fail2ban is running with no jails
    # configured, so count the entries rather than testing the string.
    local jail_count=0
    # shellcheck disable=SC2086
    [[ -n "$FAIL2BAN_JAILS" ]] && jail_count=$(printf '%s\n' $FAIL2BAN_JAILS | grep -c . || true)
    if [[ "$FAIL2BAN_PRESENT" == "1" ]]; then
        if [[ "$FAIL2BAN_RUNNING" != "1" ]]; then
            # Package is installed but the daemon isn't answering. Ambiguous —
            # could be forgotten after a reboot, could be deliberately replaced
            # by something else (a hosting panel's own brute-force protection).
            # Worth a notice either way, but not an alarm.
            kv "fail2ban" "installed but not running" "${C_YELLOW}"
        elif (( jail_count == 0 )); then
            # Running and protecting nothing. This used to render green as
            # "0 banned across 0 jail(s)", i.e. the banner claimed everything
            # was fine on a host where brute-force attempts were unmitigated.
            kv "fail2ban" "running but NO jails configured" "${C_RED}"
        elif [[ "$FAIL2BAN_BANNED" -gt 0 ]]; then
            kv "fail2ban" "${FAIL2BAN_BANNED} banned across ${jail_count} jail(s)" "${C_YELLOW}"
        else
            kv "fail2ban" "${FAIL2BAN_BANNED} banned across ${jail_count} jail(s)" "${C_GREEN}"
        fi
    fi
    section_rule
}
