#!/usr/bin/env bash
# Kubernetes: brief node + namespace summary if kubectl reaches a cluster.

section_kubernetes() {
    [[ "${KUBERNETES_ENABLED:-auto}" == "false" ]] && return
    have kubectl || return

    # Quick reachability check; bail silently if no cluster.
    local ctx
    ctx=$(kubectl config current-context 2>/dev/null) || return
    [[ -z "$ctx" ]] && return

    local nodes_ready nodes_total ns_count
    if ! kubectl get --raw=/healthz >/dev/null 2>&1; then
        return
    fi

    nodes_total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    nodes_ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {c++} END {print c+0}')
    ns_count=$(kubectl get ns --no-headers 2>/dev/null | wc -l | tr -d ' ')

    section_heading "Kubernetes"
    kv "Context" "$ctx"
    local color
    if [[ "$nodes_ready" == "$nodes_total" ]] && [[ "$nodes_total" -gt 0 ]]; then color="${C_GREEN}"
    else color="${C_YELLOW}"
    fi
    kv "Nodes" "${nodes_ready} ready / ${nodes_total} total" "$color"
    kv "Namespaces" "$ns_count"
    section_rule
}
