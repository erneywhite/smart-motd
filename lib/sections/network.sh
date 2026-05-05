#!/usr/bin/env bash
# Network: interfaces with IPs, plus public IP from cache.

_iface_ips() {
    if have ip; then
        # Format:  iface  inet ip/cidr
        ip -o -4 addr show 2>/dev/null | awk '{
            split($4, a, "/"); print $2 "|" a[1]
        }'
    elif have ifconfig; then
        ifconfig 2>/dev/null | awk '
            /^[a-zA-Z0-9]/ { iface = $1; sub(":","",iface) }
            /inet / { print iface "|" $2 }
        '
    fi
}

section_network() {
    local show_public="${NETWORK_SHOW_PUBLIC_IP:-true}"
    local show_iface="${NETWORK_SHOW_INTERFACES:-true}"

    # If both off, nothing to render — skip the whole section heading too.
    [[ "$show_public" != "true" && "$show_iface" != "true" ]] && return

    section_heading "Network"

    local public_ip
    public_ip=$(cache_read "public_ip" "")
    if [[ "$show_public" == "true" && -n "$public_ip" && "$public_ip" != "unavailable" ]]; then
        kv "Public" "$public_ip" "${C_CYAN}"
    fi

    local shown=0
    if [[ "$show_iface" == "true" ]]; then
        # Filter: empty array = show every interface (except loopback).
        # Populated array = show only those interfaces.
        # IMPORTANT: don't use `("${NETWORK_INTERFACES[@]:-}")` — for an empty
        # source array that expands to a single empty-string element, not
        # an empty array, and the filter loop then matches nothing and
        # silently hides every interface.
        local iface_filter=()
        if [[ ${#NETWORK_INTERFACES[@]} -gt 0 ]]; then
            iface_filter=("${NETWORK_INTERFACES[@]}")
        fi
        local entry iface ip
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            iface="${entry%%|*}"
            ip="${entry##*|}"
            [[ "$iface" == "lo" ]] && continue
            if [[ ${#iface_filter[@]} -gt 0 ]]; then
                local match=0 want
                for want in "${iface_filter[@]}"; do
                    [[ "$want" == "$iface" ]] && match=1
                done
                (( match )) || continue
            fi
            local label="$iface"
            (( ${#label} > 10 )) && label="${label:0:10}"
            kv "$label" "$ip"
            shown=1
        done < <(_iface_ips)
    fi

    if (( shown == 0 )) && [[ -z "$public_ip" || "$public_ip" == "unavailable" ]]; then
        kv "Network" "(nothing to show)"
    fi

    section_rule
}
