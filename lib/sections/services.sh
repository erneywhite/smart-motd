#!/usr/bin/env bash
# Services: status of configured systemd units.

section_services() {
    [[ ${#SERVICES_LIST[@]:-0} -gt 0 ]] || return
    have systemctl || return

    section_heading "Services"
    local svc state color label
    for svc in "${SERVICES_LIST[@]}"; do
        [[ -z "$svc" ]] && continue
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
    section_rule
}
