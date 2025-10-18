#!/bin/bash
# Verify an API key through Auth Bridge

set -e
source "$(dirname "$0")/common.sh"

API_KEY="${1}"

if [ -z "$API_KEY" ]; then
    error "Usage: $0 <api_key>

Example:
  $0 sk_prod_xxxxxx"
fi

info "Verifying API key through Auth Bridge..."
echo ""

RESPONSE=$(curl -sf -X POST "$AUTH_BRIDGE/api/v1/verify" \
    -H "Content-Type: application/json" \
    -d "{\"api_key\": \"$API_KEY\"}" 2>&1)

if [ $? -ne 0 ]; then
    error "Verification failed: $RESPONSE"
fi

VALID=$(echo "$RESPONSE" | jq -r '.valid // false')

if [ "$VALID" = "true" ]; then
    success "API Key is VALID"
    echo ""
    echo -e "${BLUE}Organization ID:${NC} $(echo "$RESPONSE" | jq -r '.organization_id // "N/A"')"
    echo -e "${BLUE}Plan:${NC} $(echo "$RESPONSE" | jq -r '.plan // "N/A"')"
    echo -e "${BLUE}Key ID:${NC} $(echo "$RESPONSE" | jq -r '.key_id // "N/A"')"
    echo -e "${BLUE}Key Name:${NC} $(echo "$RESPONSE" | jq -r '.key_name // "N/A"')"

    META=$(echo "$RESPONSE" | jq -r '.meta // empty')
    if [ -n "$META" ]; then
        echo ""
        echo -e "${BLUE}Metadata:${NC}"
        echo "$META" | jq '.'
    fi
else
    error "API Key is INVALID"
fi
