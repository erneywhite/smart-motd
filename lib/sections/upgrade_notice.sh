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
    [[ -z "$local_v" ]] && return

    # Sanity check: only show the notice when the cached "newer" version
    # is strictly greater than the locally-installed one. Catches the
    # transient case right after `smart-motd upgrade` where the cache
    # still holds the just-installed version as "available" until the
    # next 5-minute cache tick refreshes it.
    [[ "$newer" == "$local_v" ]] && return
    local older
    older=$(printf '%s\n%s\n' "$local_v" "$newer" | sort -V | head -1)
    # If "older" isn't the local version, the local install is actually
    # ahead of (or equal to) the cached "newer" — skip the notice.
    [[ "$older" != "$local_v" ]] && return

    printf '\n %s↑ smart-motd v%s available%s %s(you have v%s)%s — run %ssudo smart-motd upgrade%s\n' \
        "${C_BOLD}${C_BRIGHT_YELLOW}" "$newer" "${C_RESET}" \
        "${C_DIM}" "$local_v" "${C_RESET}" \
        "${C_BRIGHT_CYAN}" "${C_RESET}"
}
