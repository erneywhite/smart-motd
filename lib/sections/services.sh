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
        # Suppress known-noise units. motd-news.service is a built-in
        # default: our installer chmod -x's the scripts in
        # /etc/update-motd.d/, so motd-news.service fails the next time it
        # tries to exec /etc/update-motd.d/50-motd-news. That failure is a
        # side effect of smart-motd doing its job, not a real problem, so
        # it shouldn't show up here. Operators can suppress more units
        # (glob patterns allowed) via SERVICES_FAILED_IGNORE in config.conf.
        local ignore=( 'motd-news.service' "${SERVICES_FAILED_IGNORE[@]:-}" )
        local unit ign skip
        while IFS= read -r unit; do
            [[ -n "$unit" ]] || continue
            skip=0
            for ign in "${ignore[@]}"; do
                [[ -z "$ign" ]] && continue
                # Unquoted $ign on the right of case = glob match, so entries
                # like 'systemd-fsck@*.service' work as well as exact names.
                # shellcheck disable=SC2254
                case "$unit" in
                    $ign) skip=1; break ;;
                esac
            done
            (( skip )) && continue
            failed_units+=("$unit")
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
