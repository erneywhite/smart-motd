#!/usr/bin/env bash
# Compact one-liner shown when a newer smart-motd release is available
# on GitHub. Reads the result of cache_update_version_check from the
# cache file — empty file (or no file at all) = nothing rendered, so
# this section is invisible until an upgrade is actually published.

section_upgrade_notice() {
    local newer
    newer=$(cache_read "upgrade_available" "")
    [[ -z "$newer" ]] && return

    local local_v
    local_v=$(cat "${SMART_MOTD_PREFIX:-/usr/local/lib/smart-motd}/VERSION" 2>/dev/null | tr -d ' \r\n')

    printf '\n %s↑ smart-motd v%s available%s %s(you have v%s)%s — run %ssudo smart-motd upgrade%s\n' \
        "${C_BOLD}${C_BRIGHT_YELLOW}" "$newer" "${C_RESET}" \
        "${C_DIM}" "${local_v:-?}" "${C_RESET}" \
        "${C_BRIGHT_CYAN}" "${C_RESET}"
}
