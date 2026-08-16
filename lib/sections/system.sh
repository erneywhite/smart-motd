#!/usr/bin/env bash
# System status: hostname, uptime, load, memory, disk(s), sessions.

_human_uptime() {
    # Read from /proc/uptime (seconds), format as "X days, Y hours, Z minutes".
    local secs
    secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null) || { uptime -p 2>/dev/null | sed 's/^up //'; return; }
    local days=$(( secs / 86400 ))
    local hours=$(( (secs % 86400) / 3600 ))
    local mins=$(( (secs % 3600) / 60 ))
    local out=""
    (( days > 0 )) && out+="$days day$( ((days!=1)) && echo s ), "
    (( hours > 0 )) && out+="$hours hour$( ((hours!=1)) && echo s ), "
    out+="$mins minute$( ((mins!=1)) && echo s )"
    printf '%s' "$out"
}

_load_line() {
    if [[ -r /proc/loadavg ]]; then
        awk '{printf "%s, %s, %s", $1, $2, $3}' /proc/loadavg
    else
        uptime | sed 's/.*load average[s]*: //'
    fi
}

_mem_line() {
    if [[ -r /proc/meminfo ]]; then
        awk '
            /^MemTotal:/   { total = $2 }
            /^MemAvailable:/ { avail = $2 }
            END {
                used_mb = int((total - avail) / 1024)
                total_mb = int(total / 1024)
                pct = (total > 0) ? int((total - avail) * 100 / total) : 0
                printf "%d / %d MB|%d", used_mb, total_mb, pct
            }
        ' /proc/meminfo
    else
        printf '?|0'
    fi
}

# ---------- disks ----------
#
# Canonical row format passed around below: device|fstype|size|used|pct|mountpoint
#
# SMART_MOTD_DISK_ROWS holds the final render list as: label|used|size|pct

SMART_MOTD_DISK_ROWS=()
SMART_MOTD_DISK_SKIPPED=0
_disks_ready=""
_disks_seen_mp=" "
_disks_seen_dev=" "

# Mountpoints that are never worth a line in a login banner. /boot is
# deliberately NOT here — a full /boot breaks kernel upgrades, so it's worth
# seeing. /boot/efi and the Raspberry Pi firmware partition are pure noise.
_DISK_DEFAULT_EXCLUDE=(
    '/boot/efi' '/boot/firmware'
    '/var/lib/docker/*' '/var/lib/containers/*' '/var/snap/*' '/snap/*'
)

# One df sweep over every local, real filesystem.
#
# -l (local only) is not cosmetic: df blocks indefinitely on a stale NFS/CIFS
# mount, and this runs on every SSH login. timeout is the second line of
# defence. Network mounts can still be listed explicitly in SYSTEM_DISK_PATHS.
#
# Pseudo filesystems are filtered by TYPE rather than by mountpoint glob —
# that catches every snap (squashfs) and container layer (overlay) without
# having to keep a path list in sync with whatever the distro does next.
_disks_df() {
    local df_args=(
        -hPTl
        -x tmpfs -x devtmpfs -x squashfs -x overlay -x aufs -x efivarfs
        -x ramfs -x autofs -x nsfs -x fusectl -x configfs -x debugfs
        -x tracefs -x mqueue -x hugetlbfs -x devpts -x proc -x sysfs
        -x cgroup -x cgroup2 -x pstore -x bpf -x binfmt_misc -x securityfs
        -x fuse.snapfuse -x fuse.gvfsd-fuse -x fuse.portal
    )
    if have timeout; then
        timeout 3 df "${df_args[@]}" 2>/dev/null
    else
        df "${df_args[@]}" 2>/dev/null
    fi | awk 'NR > 1 {
        pct = $6; gsub("%", "", pct)
        mp = $7
        for (i = 8; i <= NF; i++) mp = mp " " $i
        print $1 "|" $2 "|" $3 "|" $4 "|" pct "|" mp
    }'
}

# Single-path lookup, used for explicitly configured mountpoints and as the
# fallback for / in containers (where the root fs is an overlay and therefore
# filtered out of the sweep above).
_disks_row_for() {
    df -hP "$1" 2>/dev/null | awk 'NR == 2 {
        pct = $5; gsub("%", "", pct)
        mp = $6
        for (i = 7; i <= NF; i++) mp = mp " " $i
        print $1 "|-|" $2 "|" $3 "|" pct "|" mp
    }'
}

_disks_excluded() {
    local mp="$1" pat
    for pat in "${_DISK_DEFAULT_EXCLUDE[@]}" "${SYSTEM_DISK_EXCLUDE[@]:-}"; do
        [[ -n "$pat" ]] || continue
        # Unquoted $pat on the right of case = glob match, so '/snap/*' works.
        # shellcheck disable=SC2254
        case "$mp" in
            $pat) return 0 ;;
        esac
    done
    return 1
}

# Pick a short, human label for a mountpoint.
#   /                              -> /
#   /mnt/backup                    -> /mnt/backup
#   /srv/dev-disk-by-uuid-<uuid>   -> sdb1     (OpenMediaVault et al.)
#   very/long/mountpoint/path      -> sdc1
_disk_label() {
    local dev="$1" mp="$2" name
    if [[ "$mp" == "/" ]]; then
        printf '/'
        return
    fi
    name="$mp"
    if [[ "${mp##*/}" == dev-disk-by-* ]] || (( ${#mp} > 12 )); then
        name="${dev##*/}"
    fi
    (( ${#name} > 12 )) && name="${name:0:12}"
    printf '%s' "$name"
}

_disks_push() {
    local dev="$1" mp="$2" size="$3" used="$4" pct="$5" label="$6"
    [[ "$_disks_seen_mp" == *" $mp "* ]] && return
    # Dedup by device so a disk mounted twice (bind mounts, btrfs subvolumes)
    # only produces one line.
    [[ -n "$dev" && "$dev" != "-" && "$_disks_seen_dev" == *" $dev "* ]] && return
    _disks_seen_mp+="$mp "
    [[ -n "$dev" && "$dev" != "-" ]] && _disks_seen_dev+="$dev "
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    SMART_MOTD_DISK_ROWS+=("${label}|${used}|${size}|${pct}")
}

# Build the disk list once per run. Idempotent: motd-generate calls this
# before rendering any section (so the label column width is settled for the
# whole banner), and section_system calls it again as a safety net for callers
# that dispatch sections directly (e.g. motd-benchmark).
disks_prepare() {
    [[ -n "$_disks_ready" ]] && return
    _disks_ready=1
    SMART_MOTD_DISK_ROWS=()
    SMART_MOTD_DISK_SKIPPED=0
    _disks_seen_mp=" "
    _disks_seen_dev=" "

    local auto="${SYSTEM_DISK_AUTO:-true}"
    local -a rows=()
    local line dev fstype size used pct mp p

    if [[ "$auto" == "true" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && rows+=("$line")
        done < <(_disks_df)

        # Root goes first, and is guaranteed present even when the sweep
        # filtered it out (containers: / is an overlay).
        # `rows` may be empty (df unavailable or everything filtered), so
        # expand with :- for bash < 4.4 under `set -u` and skip the empty
        # element that produces.
        local root_done=0
        for line in "${rows[@]:-}"; do
            [[ -n "$line" ]] || continue
            IFS='|' read -r dev fstype size used pct mp <<<"$line"
            [[ "$mp" == "/" ]] || continue
            _disks_push "$dev" "/" "$size" "$used" "$pct" "/"
            root_done=1
            break
        done
        if (( root_done == 0 )); then
            line=$(_disks_row_for /)
            if [[ -n "$line" ]]; then
                IFS='|' read -r dev fstype size used pct mp <<<"$line"
                _disks_push "$dev" "/" "$size" "$used" "$pct" "/"
            fi
        fi

        local max="${SYSTEM_DISK_MAX:-10}"
        [[ "$max" =~ ^[0-9]+$ ]] || max=10
        for line in "${rows[@]:-}"; do
            [[ -n "$line" ]] || continue
            IFS='|' read -r dev fstype size used pct mp <<<"$line"
            [[ "$mp" == "/" ]] && continue
            _disks_excluded "$mp" && continue
            [[ "$_disks_seen_dev" == *" $dev "* ]] && continue
            if (( ${#SMART_MOTD_DISK_ROWS[@]} >= max )); then
                SMART_MOTD_DISK_SKIPPED=$(( SMART_MOTD_DISK_SKIPPED + 1 ))
                continue
            fi
            _disks_push "$dev" "$mp" "$size" "$used" "$pct" "$(_disk_label "$dev" "$mp")"
        done
    fi

    # Explicitly configured paths. With SYSTEM_DISK_AUTO=false this is the
    # whole list (pre-v1.13 behaviour); with auto on it's the escape hatch for
    # anything the sweep can't see, e.g. an NFS share. Labeled by the path the
    # operator actually typed.
    for p in "${SYSTEM_DISK_PATHS[@]:-}"; do
        [[ -n "$p" ]] || continue
        [[ "$_disks_seen_mp" == *" $p "* ]] && continue
        line=$(_disks_row_for "$p")
        [[ -n "$line" ]] || continue
        IFS='|' read -r dev fstype size used pct mp <<<"$line"
        _disks_push "$dev" "$p" "$size" "$used" "$pct" "$p"
    done

    # Raise the shared label column if a disk label needs the room, so the
    # whole banner stays aligned rather than just this section.
    local w="${SMART_MOTD_KV_WIDTH:-10}" row lbl
    for row in "${SMART_MOTD_DISK_ROWS[@]:-}"; do
        [[ -n "$row" ]] || continue
        lbl="Disk ${row%%|*}"
        (( ${#lbl} > w )) && w=${#lbl}
    done
    (( w > 17 )) && w=17
    SMART_MOTD_KV_WIDTH=$w
}

_os_pretty_name() {
    if [[ -r /etc/os-release ]]; then
        # Source in a subshell so we don't leak ID/PRETTY_NAME/etc into the
        # caller's environment.
        ( . /etc/os-release; printf '%s' "${PRETTY_NAME:-${NAME:-}${VERSION_ID:+ ${VERSION_ID}}}" )
    fi
}

section_system() {
    section_heading "System status"
    # `hostname` (kernel name) over `hostname -f` (DNS-resolved FQDN, often
    # garbage on cloud / NAT'd boxes — see e.g. "server-xxxx.localdomain"
    # auto-generated by some providers' DHCP).
    kv "Hostname" "$(hostname 2>/dev/null || hostname -f 2>/dev/null || echo unknown)"
    local os
    os=$(_os_pretty_name)
    [[ -n "$os" ]] && kv "OS" "$os"
    kv "Uptime"   "$(_human_uptime)"
    kv "Load"     "$(_load_line)"

    local mem_raw mem_text mem_pct mem_color
    mem_raw=$(_mem_line)
    mem_text="${mem_raw%|*}"
    mem_pct="${mem_raw##*|}"
    mem_color=$(pct_color "$mem_pct")
    kv "Memory" "$mem_text" "$mem_color"

    disks_prepare
    local row label used size pct
    for row in "${SMART_MOTD_DISK_ROWS[@]:-}"; do
        [[ -n "$row" ]] || continue
        IFS='|' read -r label used size pct <<<"$row"
        kv "Disk $label" "$used / $size (${pct}% used)" "$(pct_color "$pct")"
    done
    if (( SMART_MOTD_DISK_SKIPPED > 0 )); then
        kv "Disk" "+${SMART_MOTD_DISK_SKIPPED} more (raise SYSTEM_DISK_MAX)" "${C_DIM}"
    fi

    local sessions
    sessions=$(who 2>/dev/null | wc -l | tr -d ' ')
    kv "Sessions" "${sessions:-0} active login(s)"

    section_rule
}
