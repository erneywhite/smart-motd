#!/usr/bin/env bash
# Docker: read cached container list (populated by motd-cache-update).

section_docker() {
    [[ "${DOCKER_ENABLED:-auto}" == "false" ]] && return

    local TOTAL=0 RUNNING=0 CONTAINERS=""
    cache_kv_load docker || return
    [[ "$TOTAL" -eq 0 ]] && [[ -z "$CONTAINERS" ]] && return

    section_heading "Docker containers"

    local color
    if [[ "$RUNNING" == "$TOTAL" ]] && [[ "$TOTAL" -gt 0 ]]; then color="${C_GREEN}"
    elif [[ "$RUNNING" == "0" ]]; then color="${C_GREY}"
    else color="${C_YELLOW}"
    fi
    kv "Containers" "${RUNNING} running / ${TOTAL} total" "$color"

    local row name status short
    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        name="${row%%|*}"
        status="${row#*|}"
        case "$status" in
            # Order matters: 'unhealthy' contains 'healthy' as a substring,
            # so the unhealthy case must be checked FIRST or every unhealthy
            # container would render green.
            *unhealthy*) color="${C_RED}" ;;
            *healthy*)   color="${C_GREEN}" ;;
            Up*)         color="${C_GREEN}" ;;
            *)           color="${C_YELLOW}" ;;
        esac
        short="$name"
        (( ${#short} > 28 )) && short="${short:0:27}…"
        printf "   %s%-28s%s %s%s%s\n" "${C_BOLD}" "$short" "${C_RESET}" "$color" "$status" "${C_RESET}"
    done <<<"$CONTAINERS"
    section_rule
}
