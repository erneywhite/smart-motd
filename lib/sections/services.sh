#!/usr/bin/env bash
# Services: status of configured systemd units, plus optionally any unit
# in the 'failed' state (SERVICES_SHOW_FAILED=true).

section_services() {
    have systemctl || return
    local explicit=${#SERVICES_LIST[@]}
    local show_failed="${SERVICES_SHOW_FAILED:-false}"

    if (( explicit == 0 )) && [[ "$show_failed" != "true" ]]; then
        return
    fi

    local failed_units=()
    if [[ "$show_failed" == "true" ]]; then
        local unit
        while IFS= read -r unit; do
            [[ -n "$unit" ]] && failed_units+=("$unit")
        done < <(systemctl list-units --state=failed --no-legend --plain --no-pager 2>/dev/null \
                 | awk '{print $1}')
    fi

    if (( explicit == 0 )) && (( ${#failed_units[@]} == 0 )); then
        return
    fi

    section_heading "Services"

    local svc state color label seen=" "
    for svc in "${SERVICES_LIST[@]}"; do
        [[ -z "$svc" ]] && continue
        seen+="$svc "
        state=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
        case "$state" in
            active)        color="${C_GREEN}"; label="active" ;;
            inactive|dead) color="${C_GREY}";  label="inactive" ;;
            failed)        color="${C_RED}";   label="failed" ;;
            activating|reloading) color="${C_YELLOW}"; label="$state" ;;
            unknown)       color="${C_GREY}";  label="not found" ;;
            *)             color="${C_YELLOW}"; label="$state" ;;
        esac
        printf "   %s%-12s%s %s\n" "$color" "$label" "${C_RESET}" "$svc"
    done

    for svc in "${failed_units[@]}"; do
        [[ -z "$svc" ]] && continue
        [[ "$seen" == *" $svc "* ]] && continue
        printf "   %s%-12s%s %s\n" "${C_RED}" "failed" "${C_RESET}" "$svc"
    done

    section_rule
}
