#!/bin/bash
# Common functions for all scripts

ADMIN="${KONG_ADMIN_URL:-http://localhost:8001}"
PROXY="${KONG_PROXY_URL:-http://localhost:8000}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

check_service() {
    local service=$1
    local url=$2
    if curl -sf "$url" >/dev/null 2>&1; then
        success "$service is running"
        return 0
    else
        error "$service is not accessible at $url"
        return 1
    fi
}

check_kong_health() {
    info "Checking Kong status..."
    check_service "Kong" "$ADMIN/"
}

add_route_plugins() {
    local route_id=$1

    # 1. Pre-function: Unkey verification
    local UNKEY_LUA=$(cat "$(dirname "$0")/../config/kong-unkey-prefunction.lua" | sed 's/"/\\"/g' | tr '\n' ' ')

    # 2. Pre-function: Rate limit logic
    local RATELIMIT_LUA=$(cat "$(dirname "$0")/../config/kong-rate-limit-prefunction.lua" | sed 's/"/\\"/g' | tr '\n' ' ')

    # Add pre-function with both scripts
    curl -sf -X POST "$ADMIN/routes/$route_id/plugins" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"pre-function\",\"config\":{\"access\":[\"$UNKEY_LUA\",\"$RATELIMIT_LUA\"]}}" | jq -r '.name // "exists"'

    # Rate limiting plugin - will use limits set by pre-function
    # Using local policy for simplicity (can switch to redis for distributed)
    curl -sf -X POST "$ADMIN/routes/$route_id/plugins" \
        -d 'name=rate-limiting' \
        -d 'config.minute=10000' \
        -d 'config.policy=local' \
        -d 'config.limit_by=consumer' \
        -d 'config.fault_tolerant=true' | jq -r '.name // "exists"'

    # CORS
    curl -sf -X POST "$ADMIN/routes/$route_id/plugins" \
        -d 'name=cors' \
        -d 'config.origins[]=*' \
        -d 'config.methods[]=GET' \
        -d 'config.methods[]=POST' \
        -d 'config.methods[]=OPTIONS' | jq -r '.name // "exists"'
}
