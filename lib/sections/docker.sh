#!/usr/bin/env bash
# Docker: list running / total containers, one short status line each.

_can_query_docker() {
    have docker || return 1
    docker info >/dev/null 2>&1
}

section_docker() {
    if [[ "${DOCKER_ENABLED:-auto}" == "false" ]]; then
        return
    fi
    _can_query_docker || return

    local total running
    total=$(docker ps -a --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
    running=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')

    section_heading "Docker containers"
    local color
    if [[ "$running" == "$total" ]] && [[ "$total" -gt 0 ]]; then color="${C_GREEN}"
    elif [[ "$running" == "0" ]]; then color="${C_GREY}"
    else color="${C_YELLOW}"
    fi
    kv "Containers" "${running} running / ${total} total" "$color"

    local filter="${DOCKER_FILTER:-}"
    local fmt='{{.Names}}|{{.Status}}'
    local rows
    if [[ -n "$filter" ]]; then
        rows=$(docker ps --format "$fmt" 2>/dev/null | grep -E "$filter" || true)
    else
        rows=$(docker ps --format "$fmt" 2>/dev/null)
    fi

    local row name status short
    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        name="${row%%|*}"
        status="${row#*|}"
        case "$status" in
            *healthy*)   color="${C_GREEN}" ;;
            *unhealthy*) color="${C_RED}" ;;
            Up*)         color="${C_GREEN}" ;;
            *)           color="${C_YELLOW}" ;;
        esac
        short="$name"
        (( ${#short} > 28 )) && short="${short:0:27}…"
        printf "   %s%-28s%s %s%s%s\n" "${C_BOLD}" "$short" "${C_RESET}" "$color" "$status" "${C_RESET}"
    done <<<"$rows"
    section_rule
}
