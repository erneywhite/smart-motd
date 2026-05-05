#!/usr/bin/env bash
# VPN: WireGuard interfaces + OpenVPN daemons. Reads from cache.

section_vpn() {
    [[ "${VPN_ENABLED:-auto}" == "false" ]] && return

    local data
    data=$(cache_read "vpn" "")
    [[ -z "$data" ]] && return

    section_heading "VPN"
    local line kind name a b color status
    while IFS='|' read -r kind name a b; do
        [[ -z "$kind" ]] && continue
        case "$kind" in
            wg)
                # a=active_peers  b=total_peers
                if [[ "$b" -eq 0 ]]; then
                    color="${C_GREY}"; status="(no peers)"
                elif [[ "$a" -eq "$b" ]]; then
                    color="${C_GREEN}"; status="${a} / ${b} peer(s) handshaking"
                elif [[ "$a" -gt 0 ]]; then
                    color="${C_YELLOW}"; status="${a} / ${b} peer(s) handshaking"
                else
                    color="${C_GREY}"; status="${b} peer(s), none recent"
                fi
                kv "wg ${name}" "$status" "$color"
                ;;
            openvpn)
                # a=daemon-state (active/inactive)
                case "$a" in
                    active) color="${C_GREEN}" ;;
                    *)      color="${C_YELLOW}" ;;
                esac
                kv "ovpn ${name}" "$a" "$color"
                ;;
        esac
    done <<<"$data"
    section_rule
}
