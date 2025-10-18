#!/bin/bash
# Create a customer API key with metadata

set -e
source "$(dirname "$0")/common.sh"

# Load environment
if [ -f .env ]; then
    export $(grep -v '^#' .env | grep -E "UNKEY_ROOT_KEY|UNKEY_API_ID" | xargs)
fi

ROOT_KEY="${UNKEY_ROOT_KEY:-unkey_root}"
API_ID="${UNKEY_API_ID:-api_local_root_keys}"

# Get parameters
ORG_ID="${1}"
PLAN="${2:-pro}"
KEY_NAME="${3:-Customer Key}"

if [ -z "$ORG_ID" ]; then
    error "Usage: $0 <organization_id> [plan] [key_name]

Example:
  $0 org_customer_123 pro \"Production API Key\"

Plans: free, basic, pro, enterprise"
fi

info "Creating customer API key..."
echo "  Organization: $ORG_ID"
echo "  Plan: $PLAN"
echo "  Name: $KEY_NAME"
echo ""

RESPONSE=$(curl -sf -X POST "$UNKEY_API/v2/keys.createKey" \
    -H "Authorization: Bearer $ROOT_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"apiId\": \"$API_ID\",
        \"name\": \"$KEY_NAME\",
        \"prefix\": \"sk_prod\",
        \"meta\": {
            \"organizationId\": \"$ORG_ID\",
            \"plan\": \"$PLAN\"
        }
    }" 2>&1)

if [ $? -ne 0 ]; then
    error "Failed to create key: $RESPONSE"
fi

KEY=$(echo "$RESPONSE" | jq -r '.key // empty')
KEY_ID=$(echo "$RESPONSE" | jq -r '.keyId // empty')

if [ -z "$KEY" ]; then
    error "Key creation failed: $(echo "$RESPONSE" | jq -r '.error // "Unknown error"')"
fi

echo ""
success "API Key created successfully!"
echo ""
echo -e "${GREEN}API Key:${NC} $KEY"
echo -e "${BLUE}Key ID:${NC} $KEY_ID"
echo ""
warn "Save this key securely - it won't be shown again!"
echo ""
info "Test with:"
echo "  curl -X POST http://localhost:8000/$KEY/eth-mainnet \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
