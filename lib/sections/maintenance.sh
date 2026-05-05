#!/usr/bin/env bash
# Maintenance: reboot-required notice, plus generic flag files.

section_maintenance() {
    local notes=()

    if [[ -f /var/run/reboot-required ]]; then
        local pkgs=""
        [[ -r /var/run/reboot-required.pkgs ]] && \
            pkgs=" ($(wc -l </var/run/reboot-required.pkgs | tr -d ' ') pkg(s))"
        notes+=("REBOOT|required - kernel/core libs upgraded${pkgs}")
    elif have needs-restarting; then
        if ! needs-restarting -r >/dev/null 2>&1; then
            notes+=("REBOOT|required (needs-restarting -r)")
        fi
    elif [[ -f /var/run/reboot-required.systemd ]]; then
        notes+=("REBOOT|required")
    fi

    # Auto-discover snap refresh-hold or other flag files? Keep this minimal for v1.
    if [[ ${#notes[@]} -eq 0 ]]; then
        return
    fi

    section_heading "Maintenance"
    local entry label value
    for entry in "${notes[@]}"; do
        label="${entry%%|*}"
        value="${entry#*|}"
        kv "$label" "$value" "${C_RED}"
    done
    section_rule
}
