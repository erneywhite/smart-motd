#!/usr/bin/env bash
# Warning section: legal notice / authorized-access banner.
section_warning() {
    local first=true line
    for line in "${WARNING_LINES[@]:-}"; do
        [[ -z "$line" ]] && continue
        if $first; then
            printf " %sWarning:%s %s\n" "${C_BOLD}${C_YELLOW}" "${C_RESET}" "$line"
            first=false
        else
            printf " %s\n" "$line"
        fi
    done
    section_thick_rule
}
