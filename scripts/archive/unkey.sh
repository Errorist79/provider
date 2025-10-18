#!/bin/bash
# Unkey initialization and configuration

set -e
source "$(dirname "$0")/common.sh"

UNKEY_API="${UNKEY_BASE_URL:-http://localhost:3001}"
ROOT_KEY="${UNKEY_ROOT_KEY:-unkey_root}"

info "Initializing Unkey..."

# Wait for Unkey to be ready
info "Waiting for Unkey to start..."
for i in {1..30}; do
    if curl -sf "$UNKEY_API/v2/liveness" >/dev/null 2>&1; then
        success "Unkey is ready"
        break
    fi
    [ $i -eq 30 ] && error "Unkey failed to start"
    sleep 2
done

# Create workspace
info "Creating workspace..."
WORKSPACE_RESPONSE=$(curl -sf -X POST "$UNKEY_API/v2/workspaces" \
    -H "Authorization: Bearer $ROOT_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "rpc_gateway",
        "slug": "rpc-gateway"
    }' 2>/dev/null || echo '{}')

WORKSPACE_ID=$(echo "$WORKSPACE_RESPONSE" | jq -r '.id // empty')

if [ -z "$WORKSPACE_ID" ]; then
    warn "Workspace might already exist, fetching existing workspace..."
    # Try to get existing workspace
    WORKSPACE_ID=$(curl -sf "$UNKEY_API/v2/workspaces" \
        -H "Authorization: Bearer $ROOT_KEY" | jq -r '.workspaces[0].id // empty')
fi

[ -z "$WORKSPACE_ID" ] && error "Failed to create or fetch workspace"
success "Workspace ID: $WORKSPACE_ID"

# Create API for RPC keys
info "Creating API for RPC keys..."
API_RESPONSE=$(curl -sf -X POST "$UNKEY_API/v2/apis" \
    -H "Authorization: Bearer $ROOT_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"rpc_keys\",
        \"workspaceId\": \"$WORKSPACE_ID\"
    }" 2>/dev/null || echo '{}')

API_ID=$(echo "$API_RESPONSE" | jq -r '.id // empty')

if [ -z "$API_ID" ]; then
    warn "API might already exist, fetching existing API..."
    API_ID=$(curl -sf "$UNKEY_API/v2/apis?workspaceId=$WORKSPACE_ID" \
        -H "Authorization: Bearer $ROOT_KEY" | jq -r '.apis[0].id // empty')
fi

[ -z "$API_ID" ] && error "Failed to create or fetch API"
success "API ID: $API_ID"

# Save configuration to .env
info "Updating .env file..."
if [ -f .env ]; then
    # Update existing .env
    sed -i.bak "s/^UNKEY_WORKSPACE_ID=.*/UNKEY_WORKSPACE_ID=$WORKSPACE_ID/" .env
    sed -i.bak "s/^UNKEY_API_ID=.*/UNKEY_API_ID=$API_ID/" .env
    rm -f .env.bak
else
    # Create new .env from example
    cp .env.example .env
    sed -i.bak "s/^UNKEY_WORKSPACE_ID=.*/UNKEY_WORKSPACE_ID=$WORKSPACE_ID/" .env
    sed -i.bak "s/^UNKEY_API_ID=.*/UNKEY_API_ID=$API_ID/" .env
    rm -f .env.bak
fi

success "Unkey configuration saved to .env"

# Create a test API key
info "Creating test API key..."
TEST_KEY_RESPONSE=$(curl -sf -X POST "$UNKEY_API/v2/keys" \
    -H "Authorization: Bearer $ROOT_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"apiId\": \"$API_ID\",
        \"prefix\": \"sk_test\",
        \"name\": \"Test Key\",
        \"ownerId\": \"test-org-001\",
        \"meta\": {
            \"organizationId\": \"a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11\",
            \"plan\": \"pro\",
            \"allowedChains\": [\"*\"]
        },
        \"ratelimit\": {
            \"type\": \"fast\",
            \"limit\": 10000,
            \"refillRate\": 100,
            \"refillInterval\": 60000
        }
    }") || warn "Failed to create test key"

TEST_KEY=$(echo "$TEST_KEY_RESPONSE" | jq -r '.key // empty')

if [ -n "$TEST_KEY" ]; then
    success "Test API Key created: $TEST_KEY"
    echo ""
    info "Test with:"
    echo "  curl -X POST http://localhost:8000/${TEST_KEY}/eth-mainnet \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
else
    warn "Could not create test key automatically"
fi

echo ""
success "Unkey setup complete!"
info "Workspace ID: $WORKSPACE_ID"
info "API ID: $API_ID"
info "Unkey Dashboard: $UNKEY_API"
