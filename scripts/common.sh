#!/bin/bash
# Common functions for all scripts

ADMIN="${KONG_ADMIN_URL:-http://localhost:8001}"
PROXY="${KONG_PROXY_URL:-http://localhost:8000}"
UNKEY_API="${UNKEY_BASE_URL:-http://localhost:3001}"
AUTH_BRIDGE="${AUTH_BRIDGE_URL:-http://localhost:8081}"

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
        warn "$service is not accessible at $url"
        return 1
    fi
}

check_kong_health() {
    info "Checking Kong status..."
    check_service "Kong Admin API" "$ADMIN/status"
}

check_unkey_health() {
    info "Checking Unkey status..."
    check_service "Unkey API" "$UNKEY_API/v2/liveness"
}

check_auth_bridge_health() {
    info "Checking Auth Bridge status..."
    check_service "Auth Bridge" "$AUTH_BRIDGE/health"
}
