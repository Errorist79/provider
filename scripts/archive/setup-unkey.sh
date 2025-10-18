#!/bin/bash
# Unkey initialization and configuration

set -e
source "$(dirname "$0")/common.sh"

UNKEY_API="${UNKEY_BASE_URL:-http://localhost:3001}"
# Load MySQL credentials from .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | grep -E "UNKEY_MYSQL|UNKEY_ROOT_KEY" | xargs)
fi

MYSQL_HOST="${UNKEY_MYSQL_HOST:-unkey-mysql}"
MYSQL_USER="${UNKEY_MYSQL_USER:-mysqluser}"
MYSQL_PASS="${UNKEY_MYSQL_PASSWORD:-mysqlpass}"
MYSQL_DB="${UNKEY_MYSQL_DB:-unkey}"
ROOT_KEY="${UNKEY_ROOT_KEY:-unkey_root}"

info "Initializing Unkey..."

# Wait for MySQL to be ready
info "Waiting for MySQL to start..."
for i in {1..30}; do
    if docker exec unkey-mysql mysqladmin ping -h localhost -u"$MYSQL_USER" -p"$MYSQL_PASS" >/dev/null 2>&1; then
        success "MySQL is ready"
        break
    fi
    [ $i -eq 30 ] && error "MySQL failed to start"
    sleep 2
done

# Wait for Unkey API to be ready
info "Waiting for Unkey API to start..."
for i in {1..30}; do
    if curl -sf "$UNKEY_API/v2/liveness" >/dev/null 2>&1; then
        success "Unkey API is ready"
        break
    fi
    [ $i -eq 30 ] && error "Unkey API failed to start"
    sleep 2
done

# Check if API already exists in database
info "Checking for existing API configuration..."
EXISTING_API=$(docker exec unkey-mysql mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" "$MYSQL_DB" \
    -sN -e "SELECT id FROM apis LIMIT 1;" 2>/dev/null || echo "")

if [ -n "$EXISTING_API" ]; then
    success "Found existing API: $EXISTING_API"
    API_ID="$EXISTING_API"
else
    warn "No API found in database. Unkey self-hosted requires manual setup."
    warn "Please refer to Unkey documentation for self-hosted deployment:"
    warn "  https://github.com/unkeyed/unkey/tree/main/deployment"
    echo ""
    info "Alternative: Use Kong's built-in key-auth plugin instead of Unkey"
    exit 1
fi

# Save configuration to .env
info "Updating .env file..."
if [ -f .env ]; then
    # Update existing .env
    sed -i.bak "s/^UNKEY_API_ID=.*/UNKEY_API_ID=$API_ID/" .env
    rm -f .env.bak
else
    # Create new .env from example
    cp .env.example .env
    sed -i.bak "s/^UNKEY_API_ID=.*/UNKEY_API_ID=$API_ID/" .env
    rm -f .env.bak
fi

success "Unkey configuration saved to .env"

# Create a test API key
info "Creating test API key..."
TEST_KEY_RESPONSE=$(curl -sf -X POST "$UNKEY_API/v2/keys.createKey" \
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
info "API ID: $API_ID"
info "Unkey API: $UNKEY_API"
echo ""
info "Note: To create API keys, you'll need to set up a root key first."
info "Refer to Unkey documentation for authentication setup:"
info "  https://www.unkey.com/docs"
