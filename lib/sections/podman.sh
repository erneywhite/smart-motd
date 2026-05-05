#!/usr/bin/env bash
# Podman: same shape as docker section.

section_podman() {
    if [[ "${PODMAN_ENABLED:-auto}" == "false" ]]; then return; fi
    have podman || return
    # Avoid duplicating output when podman emulates docker on the same host.
    if [[ "${DOCKER_ENABLED:-auto}" != "false" ]] && _can_query_docker 2>/dev/null; then
        local same
        same=$(readlink -f "$(command -v docker)" 2>/dev/null || true)
        [[ "$same" == *podman* ]] && return
    fi

    local total running
    total=$(podman ps -a --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
    running=$(podman ps --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')

    [[ "$total" -eq 0 ]] && return

    section_heading "Podman containers"
    local color
    if [[ "$running" == "$total" ]]; then color="${C_GREEN}"
    elif [[ "$running" == "0" ]]; then color="${C_GREY}"
    else color="${C_YELLOW}"
    fi
    kv "Containers" "${running} running / ${total} total" "$color"

    local row name status short
    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        name="${row%%|*}"
        status="${row#*|}"
        case "$status" in
            Up*)  color="${C_GREEN}" ;;
            *)    color="${C_YELLOW}" ;;
        esac
        short="$name"
        (( ${#short} > 28 )) && short="${short:0:27}…"
        printf "   %s%-28s%s %s%s%s\n" "${C_BOLD}" "$short" "${C_RESET}" "$color" "$status" "${C_RESET}"
    done < <(podman ps --format '{{.Names}}|{{.Status}}' 2>/dev/null)
    section_rule
}
