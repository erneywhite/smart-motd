#!/usr/bin/env bash
# Welcome section: short intro + custom KV lines (URLs, admin, etc.)
section_welcome() {
    [[ "${WELCOME_TITLE:-}" ]] && \
        printf " %sWelcome to:%s %s\n" "${C_BOLD}" "${C_RESET}" "${WELCOME_TITLE}"

    local entry label value
    for entry in "${WELCOME_LINES[@]:-}"; do
        [[ -z "$entry" ]] && continue
        label="${entry%%|*}"
        value="${entry#*|}"
        printf " %-6s: %s\n" "$label" "$value"
    done
}
