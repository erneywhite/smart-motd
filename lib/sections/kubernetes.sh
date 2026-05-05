#!/usr/bin/env bash
# Kubernetes: read cached cluster summary.

section_kubernetes() {
    [[ "${KUBERNETES_ENABLED:-auto}" == "false" ]] && return

    local CONTEXT="" NODES_READY=0 NODES_TOTAL=0 NS_COUNT=0
    cache_kv_load kubernetes || return
    [[ -z "$CONTEXT" ]] && return

    section_heading "Kubernetes"
    kv "Context" "$CONTEXT"
    local color
    if [[ "$NODES_READY" == "$NODES_TOTAL" ]] && [[ "$NODES_TOTAL" -gt 0 ]]; then color="${C_GREEN}"
    else color="${C_YELLOW}"
    fi
    kv "Nodes" "${NODES_READY} ready / ${NODES_TOTAL} total" "$color"
    kv "Namespaces" "$NS_COUNT"
    section_rule
}
