#!/bin/bash
# Kong multichain setup - consolidates all Kong configuration

set -e
source "$(dirname "$0")/common.sh"

info "Starting Kong multichain setup..."

check_kong_health

# List of chains to configure
CHAINS=(
    "eth-mainnet:eth-node-1.internal:8545"
    "eth-sepolia:sepolia-node-1.internal:8545"
    "arb-mainnet:arb-node-1.internal:8545"
    "polygon-mainnet:polygon-node-1.internal:8545"
    "base-mainnet:base-node-1.internal:8545"
    "op-mainnet:op-node-1.internal:8545"
)

for chain_config in "${CHAINS[@]}"; do
    IFS=':' read -r chain_slug node1 node2 <<< "$chain_config"

    info "Configuring chain: $chain_slug"

    # Create upstream
    curl -sf -X POST "$ADMIN/upstreams" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"${chain_slug}-rpc\",\"algorithm\":\"round-robin\"}" | jq -r '.name // "exists"'

    # Add target
    curl -sf -X POST "$ADMIN/upstreams/${chain_slug}-rpc/targets" \
        -d "target=${node1}" | jq -r '.target // "exists"'

    # Create service
    curl -sf -X POST "$ADMIN/services" \
        -d "name=${chain_slug}-svc" \
        -d "host=${chain_slug}-rpc" \
        -d "port=8545" | jq -r '.name // "exists"'

    # Create route
    SERVICE_ID=$(curl -s "$ADMIN/services/${chain_slug}-svc" | jq -r '.id')
    curl -sf -X POST "$ADMIN/routes" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"${chain_slug}-route\",\"service\":{\"id\":\"${SERVICE_ID}\"},\"paths\":[\"~/[^/]+/${chain_slug}$\"],\"methods\":[\"POST\",\"GET\",\"OPTIONS\"]}" | jq -r '.name // "exists"'

    # Get route ID
    ROUTE_ID=$(curl -s "$ADMIN/routes/${chain_slug}-route" | jq -r '.id')

    # Add plugins (pre-function, key-auth, rate-limiting, cors)
    add_route_plugins "$ROUTE_ID"
done

# Add global Prometheus plugin
curl -sf -X POST "$ADMIN/plugins" \
    -H 'Content-Type: application/json' \
    -d '{"name":"prometheus","config":{"per_consumer":true,"status_code_metrics":true}}' | jq -r '.name // "exists"'

success "Kong multichain setup complete!"
info "Available endpoints:"
for chain_config in "${CHAINS[@]}"; do
    IFS=':' read -r chain_slug _ <<< "$chain_config"
    echo "  - $PROXY/YOUR_API_KEY/$chain_slug"
done
