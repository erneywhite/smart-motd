#!/usr/bin/env bash
# Weather: render cached one-liner from wttr.in.

section_weather() {
    [[ "${WEATHER_ENABLED:-false}" == "true" ]] || return
    local data
    data=$(cache_read "weather" "")
    [[ -z "$data" || "$data" == "unavailable" ]] && return

    section_heading "Weather"
    printf "   %s\n" "$data"
    section_rule
}
