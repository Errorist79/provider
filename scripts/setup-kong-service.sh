#!/bin/bash
# Create Kong service and route for RPC endpoint

set -e
source "$(dirname "$0")/common.sh"

CHAIN_SLUG="${1}"
UPSTREAM_URL="${2}"

if [ -z "$CHAIN_SLUG" ] || [ -z "$UPSTREAM_URL" ]; then
    error "Usage: $0 <chain_slug> <upstream_url>

Example:
  $0 eth-mainnet http://eth-node:8545
  $0 polygon-mainnet http://polygon-node:8545"
fi

check_kong_health

info "Creating service and route for: $CHAIN_SLUG"
echo "  Upstream: $UPSTREAM_URL"
echo ""

# Create service
info "Creating Kong service..."
SERVICE_RESPONSE=$(curl -sf -X POST "$ADMIN/services" \
    -d "name=${CHAIN_SLUG}" \
    -d "url=${UPSTREAM_URL}" 2>&1)

if [ $? -ne 0 ]; then
    warn "Service might already exist"
else
    success "Service created: $CHAIN_SLUG"
fi

# Create route with pattern: /<API_KEY>/<CHAIN_SLUG>
info "Creating Kong route..."
ROUTE_RESPONSE=$(curl -sf -X POST "$ADMIN/routes" \
    -H 'Content-Type: application/json' \
    -d "{
        \"name\": \"${CHAIN_SLUG}-route\",
        \"service\": {\"name\": \"${CHAIN_SLUG}\"},
        \"paths\": [\"~/${CHAIN_SLUG}\$\"],
        \"methods\": [\"POST\", \"GET\", \"OPTIONS\"],
        \"strip_path\": false
    }" 2>&1)

if [ $? -ne 0 ]; then
    warn "Route might already exist"
else
    success "Route created: ${CHAIN_SLUG}-route"
fi

echo ""
success "Setup complete for: $CHAIN_SLUG"
echo ""
info "Endpoint: $PROXY/<API_KEY>/$CHAIN_SLUG"
echo ""
info "Note: Ensure unkey-auth and rate-limiting plugins are enabled globally"
