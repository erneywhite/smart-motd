#!/usr/bin/env bash
# Temperature: read CPU temp from /sys/class/thermal or via 'sensors'.

_temp_from_sysfs() {
    local zone t label highest=0 highest_label=""
    for zone in /sys/class/thermal/thermal_zone*/; do
        [[ -r "${zone}temp" ]] || continue
        t=$(cat "${zone}temp" 2>/dev/null)
        [[ -z "$t" || "$t" -lt 1000 ]] && continue
        t=$(( t / 1000 ))
        label=$(cat "${zone}type" 2>/dev/null || echo "zone")
        if (( t > highest )); then
            highest=$t
            highest_label="$label"
        fi
    done
    [[ "$highest" -gt 0 ]] && printf '%d|%s' "$highest" "$highest_label"
}

_temp_from_sensors() {
    have sensors || return 1
    # Pick the first "Package id 0" or "Tctl" or similar high-level reading.
    sensors 2>/dev/null | awk '
        /^(Package id 0|Tctl|Tdie|CPU Temperature):/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^\+?[0-9]+(\.[0-9]+)?°C/) {
                    val = $i
                    sub(/^\+/, "", val)
                    sub(/°C.*/, "", val)
                    printf "%d|%s\n", int(val), $1
                    exit
                }
            }
        }
    '
}

section_temperature() {
    local data="" temp label
    data=$(_temp_from_sensors) || true
    [[ -z "$data" ]] && data=$(_temp_from_sysfs)
    [[ -z "$data" ]] && return

    temp="${data%|*}"
    label="${data##*|}"

    section_heading "Temperature"
    local color
    if (( temp >= 85 )); then color="${C_RED}"
    elif (( temp >= 70 )); then color="${C_YELLOW}"
    else color="${C_GREEN}"
    fi
    kv "CPU" "${temp}°C ${C_DIM}(${label})${C_RESET}" "$color"
    section_rule
}
