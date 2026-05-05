#!/usr/bin/env bash
# Last logins: show the N most recent successful logins via `last`.

section_lastlogin() {
    have last || return
    local n="${LASTLOGIN_COUNT:-3}"
    # `last` includes "still logged in" and "reboot" entries; filter out reboot.
    local rows
    rows=$(last -F -n $((n + 5)) 2>/dev/null \
        | awk 'NF >= 5 && $1 != "reboot" && $1 != "wtmp" {print}' \
        | head -n "$n")
    [[ -z "$rows" ]] && return

    section_heading "Recent logins"
    local row user from when
    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        # Extract user, from-host, and the date portion.
        user=$(awk '{print $1}' <<<"$row")
        from=$(awk '{print $3}' <<<"$row")
        when=$(awk '{for(i=4;i<=NF-2;i++) printf "%s ", $i; print ""}' <<<"$row" | sed 's/  *$//')
        local from_short="$from"
        (( ${#from_short} > 18 )) && from_short="${from_short:0:17}…"
        printf "   %s%-12s%s %s%-18s%s %s%s%s\n" \
            "${C_BOLD}" "$user" "${C_RESET}" \
            "" "$from_short" "" \
            "${C_DIM}" "$when" "${C_RESET}"
    done <<<"$rows"
    section_rule
}
