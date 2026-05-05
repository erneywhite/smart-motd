#!/usr/bin/env bash
# Directories: render cached label|path|size lines for monitored paths.

section_directories() {
    local data
    data=$(cache_read "directories" "")
    [[ -z "$data" ]] && return

    section_heading "Monitored directories"
    local line label path size short
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        IFS='|' read -r label path size <<<"$line"
        short="$label"
        (( ${#short} > 22 )) && short="${short:0:21}…"
        local color="${C_RESET}"
        [[ "$size" == "missing" ]] && color="${C_RED}"
        printf "   %-22s %s%s%s  %s%s%s\n" \
            "$short" \
            "$color" "$size" "${C_RESET}" \
            "${C_DIM}" "$path" "${C_RESET}"
    done <<<"$data"
    section_rule
}
