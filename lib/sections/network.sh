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

# Format bytes/sec as a short human-readable string (auto KB/MB/GB).
_human_rate() {
    awk -v b="$1" 'BEGIN {
        if (b < 1024)               printf "%d B/s", b
        else if (b < 1048576)       printf "%.1f KB/s", b/1024
        else if (b < 1073741824)    printf "%.1f MB/s", b/1048576
        else                        printf "%.1f GB/s", b/1073741824
    }'
}

# Look up the rx/tx rate for an interface in the cached network_rates file.
# Returns "rx_bps|tx_bps" or empty if not present.
_iface_rate() {
    local iface="$1"
    local data line
    data=$(cache_read "network_rates" "")
    [[ -z "$data" ]] && return
    line=$(grep -m1 "^${iface}|" <<<"$data" 2>/dev/null)
    [[ -z "$line" ]] && return
    local _i rx tx _e
    IFS='|' read -r _i rx tx _e <<<"$line"
    printf '%s|%s' "${rx:-0}" "${tx:-0}"
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
        local show_rates="${NETWORK_SHOW_RATES:-true}"
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

            # Append rx/tx rate from cache when enabled and available.
            # ↓ = incoming (download), ↑ = outgoing (upload). Both columns
            # are right-padded to a fixed width so values line up across
            # interfaces regardless of IP length or rate magnitude.
            local value="$ip"
            if [[ "$show_rates" == "true" ]]; then
                local rate
                rate=$(_iface_rate "$iface")
                if [[ -n "$rate" ]]; then
                    local rx_bps tx_bps rx_h tx_h ip_pad rx_pad
                    IFS='|' read -r rx_bps tx_bps <<<"$rate"
                    rx_h=$(_human_rate "$rx_bps")
                    tx_h=$(_human_rate "$tx_bps")
                    # Max IPv4 = "255.255.255.255" (15 chars); pad to 16.
                    ip_pad=$(printf '%-16s' "$ip")
                    # Longest reasonable rate = "999.9 MB/s" (10); pad to 10.
                    rx_pad=$(printf '%-10s' "$rx_h")
                    value="${ip_pad}  ${C_DIM}↓${C_RESET} ${rx_pad}  ${C_DIM}↑${C_RESET} ${tx_h}"
                fi
            fi
            kv "$label" "$value"
            shown=1
        done < <(_iface_ips)
    fi

    if (( shown == 0 )) && [[ -z "$public_ip" || "$public_ip" == "unavailable" ]]; then
        kv "Network" "(nothing to show)"
    fi

    section_rule
}
