#!/usr/bin/env bash
# Footer: a single bottom notice (e.g. "*** System restart required ***" Ubuntu-style).

section_footer() {
    if [[ -f /var/run/reboot-required ]]; then
        printf "\n%s*** System restart required ***%s\n" "${C_BOLD}${C_RED}" "${C_RESET}"
    fi
    if [[ -n "${FOOTER_TEXT:-}" ]]; then
        printf "%s%s%s\n" "${C_DIM}" "$FOOTER_TEXT" "${C_RESET}"
    fi
}
