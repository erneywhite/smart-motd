#!/usr/bin/env bash
# Header section: prints the big banner at the top.
section_header() {
    local text="${HEADER_TEXT:-Welcome}"
    local spaced="${HEADER_SPACED:-true}"
    local rendered

    if [[ "$spaced" == "true" ]]; then
        rendered=$(spaced_text "$text")
    else
        rendered="$text"
    fi

    printf "%s%s%s\n" "${C_BOLD}${C_CYAN}" "$rendered" "${C_RESET}"
    section_thick_rule
}
