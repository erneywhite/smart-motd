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
    section_heading "Network"

    local public_ip
    public_ip=$(cache_read "public_ip" "")
    if [[ "${NETWORK_SHOW_PUBLIC_IP:-true}" == "true" && -n "$public_ip" && "$public_ip" != "unavailable" ]]; then
        kv "Public" "$public_ip" "${C_CYAN}"
    fi

    # filter out loopback by default; allow user override
    local iface_filter=("${NETWORK_INTERFACES[@]:-}")
    local entry iface ip shown=0
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
        # truncate label
        local label="$iface"
        (( ${#label} > 10 )) && label="${label:0:10}"
        kv "$label" "$ip"
        shown=1
    done < <(_iface_ips)

    if (( shown == 0 )) && [[ -z "$public_ip" || "$public_ip" == "unavailable" ]]; then
        kv "Network" "(no interfaces detected)"
    fi

    section_rule
}
