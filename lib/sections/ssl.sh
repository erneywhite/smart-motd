#!/usr/bin/env bash
# SSL: render the cached domain|days|status lines.

section_ssl() {
    local data
    data=$(cache_read "ssl" "")
    [[ -z "$data" ]] && return

    section_heading "SSL certificates"
    local line domain days status color text
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        IFS='|' read -r domain days status <<<"$line"
        case "$status" in
            ok)      color="${C_GREEN}";  text="${days}d left" ;;
            warn)    color="${C_YELLOW}"; text="${days}d left (expiring soon)" ;;
            expired) color="${C_RED}";    text="EXPIRED ${days#-}d ago" ;;
            *)       color="${C_GREY}";   text="check failed" ;;
        esac
        # Truncate domain to keep alignment
        local short="$domain"
        (( ${#short} > 24 )) && short="${short:0:23}…"
        printf "   %s%-24s%s %s\n" "${C_BOLD}" "$short" "${C_RESET}" "${color}${text}${C_RESET}"
    done <<<"$data"
    section_rule
}
