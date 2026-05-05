#!/usr/bin/env bash
# Security: fail2ban summary + recent failed SSH attempts.

_failed_ssh_24h() {
    # Best-effort: try journalctl, then /var/log/auth.log, then /var/log/secure.
    if have journalctl; then
        journalctl _COMM=sshd --since "24 hours ago" --no-pager 2>/dev/null \
            | grep -cEi 'failed password|invalid user' || true
        return
    fi
    local f
    for f in /var/log/auth.log /var/log/secure; do
        [[ -r "$f" ]] || continue
        # Filter by today + yesterday isn't trivial cross-distro; approximate with full file.
        grep -cEi 'failed password|invalid user' "$f" 2>/dev/null || true
        return
    done
    echo 0
}

_fail2ban_summary() {
    have fail2ban-client || return 1
    fail2ban-client status 2>/dev/null | awk -F': *' '/Jail list/ {print $2}' | tr ',' '\n' | sed 's/^ *//;s/ *$//'
}

section_security() {
    local failed banned_total=0 jails
    failed=$(_failed_ssh_24h | tr -d ' \n')
    failed="${failed:-0}"

    if jails=$(_fail2ban_summary); then
        local jail count
        while IFS= read -r jail; do
            [[ -z "$jail" ]] && continue
            count=$(fail2ban-client status "$jail" 2>/dev/null | awk -F': *' '/Currently banned/ {print $2}' | tr -d ' \t')
            count="${count:-0}"
            banned_total=$(( banned_total + count ))
        done <<<"$jails"
    fi

    # Skip the section entirely if nothing to show
    if [[ "$failed" == "0" ]] && [[ -z "$jails" ]]; then
        return
    fi

    section_heading "Security"
    local color
    if [[ "$failed" -gt 50 ]]; then color="${C_RED}"
    elif [[ "$failed" -gt 10 ]]; then color="${C_YELLOW}"
    else color="${C_GREEN}"
    fi
    kv "SSH fails" "${failed} in last 24h" "$color"

    if [[ -n "$jails" ]]; then
        if [[ "$banned_total" -gt 0 ]]; then color="${C_YELLOW}"; else color="${C_GREEN}"; fi
        local jail_count
        jail_count=$(printf '%s\n' "$jails" | grep -c .)
        kv "fail2ban" "${banned_total} banned across ${jail_count} jail(s)" "$color"
    fi
    section_rule
}
