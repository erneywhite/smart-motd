#!/usr/bin/env bash
# SMART: render cached disk health summary.

section_smart() {
    local data
    data=$(cache_read "smart" "")
    [[ -z "$data" ]] && return

    section_heading "Disk SMART"
    local line dev model temp health color short_dev
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        IFS='|' read -r dev model temp health <<<"$line"
        case "$health" in
            PASSED|OK) color="${C_GREEN}" ;;
            FAILED|*WARN*) color="${C_RED}" ;;
            *) color="${C_YELLOW}" ;;
        esac
        short_dev="${dev#/dev/}"
        local short_model="$model"
        (( ${#short_model} > 22 )) && short_model="${short_model:0:21}…"
        printf "   %s%-7s%s %s%-22s%s %s°C  %s%s%s\n" \
            "${C_BOLD}" "$short_dev" "${C_RESET}" \
            "${C_DIM}" "$short_model" "${C_RESET}" \
            "$temp" \
            "$color" "$health" "${C_RESET}"
    done <<<"$data"
    section_rule
}
