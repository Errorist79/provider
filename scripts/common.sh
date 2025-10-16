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

    # Pre-function plugin
    read -r -d '' LUA_CODE << 'EOF' || true
local uri = kong.request.get_path()
local m = ngx.re.match(uri, [[^/([^/]+)/[^/]+$]], "jo")
if m and m[1] then
  ngx.req.set_header("apikey", m[1])
  kong.service.request.set_path("/")
  kong.log.set_serialize_value("request.headers.apikey", "[REDACTED]")
else
  return kong.response.exit(400, {message = "Invalid path"})
end
EOF

    curl -sf -X POST "$ADMIN/routes/$route_id/plugins" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"pre-function\",\"config\":{\"access\":[\"$LUA_CODE\"]}}" | jq -r '.name // "exists"'

    # Key-auth
    curl -sf -X POST "$ADMIN/routes/$route_id/plugins" \
        -d 'name=key-auth' \
        -d 'config.key_names[]=apikey' | jq -r '.name // "exists"'

    # Rate limiting
    curl -sf -X POST "$ADMIN/routes/$route_id/plugins" \
        -d 'name=rate-limiting' \
        -d 'config.minute=1000' | jq -r '.name // "exists"'

    # CORS
    curl -sf -X POST "$ADMIN/routes/$route_id/plugins" \
        -d 'name=cors' | jq -r '.name // "exists"'
}
