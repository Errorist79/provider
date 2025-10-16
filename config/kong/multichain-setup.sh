#!/bin/bash

# ============================================================================
# Kong Multichain Setup Script
# ============================================================================
# Configures Kong with routes for multiple blockchain networks
# URL Pattern: /{API_KEY}/{chain-slug}

set -e

ADMIN="${KONG_ADMIN_URL:-http://localhost:8001}"
PROXY="${KONG_PROXY_URL:-http://localhost:8000}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Kong Multichain Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check Kong health
echo -e "${YELLOW}Checking Kong status...${NC}"
if ! curl -s -f "${ADMIN}/" > /dev/null; then
    echo -e "${RED}ERROR: Kong Admin API is not accessible at ${ADMIN}${NC}"
    echo "Make sure Kong is running: docker-compose up -d kong"
    exit 1
fi
echo -e "${GREEN}✓ Kong is running${NC}"
echo ""

# Function to create upstream and targets
create_upstream() {
    local chain_slug=$1
    local upstream_name="${chain_slug}-rpc"

    echo -e "${BLUE}Creating upstream: ${upstream_name}${NC}"

    # Create upstream
    curl -s -X POST "${ADMIN}/upstreams" \
        -H 'Content-Type: application/json' \
        -d "{
            \"name\": \"${upstream_name}\",
            \"algorithm\": \"round-robin\",
            \"slots\": 10000,
            \"healthchecks\": {
                \"passive\": {
                    \"healthy\": {
                        \"successes\": 5
                    },
                    \"unhealthy\": {
                        \"http_failures\": 3,
                        \"timeouts\": 3
                    }
                },
                \"active\": {
                    \"healthy\": {
                        \"interval\": 30,
                        \"successes\": 2
                    },
                    \"unhealthy\": {
                        \"interval\": 30,
                        \"http_failures\": 3
                    }
                }
            }
        }" | jq -r '.name // "exists"'
}

# Function to add target to upstream
add_target() {
    local upstream_name=$1
    local target_url=$2
    local weight=${3:-100}

    echo -e "  Adding target: ${target_url}"
    curl -s -X POST "${ADMIN}/upstreams/${upstream_name}/targets" \
        -H 'Content-Type: application/json' \
        -d "{
            \"target\": \"${target_url}\",
            \"weight\": ${weight}
        }" | jq -r '.target // "exists"'
}

# Function to create service
create_service() {
    local chain_slug=$1
    local upstream_name="${chain_slug}-rpc"
    local service_name="${chain_slug}-svc"

    echo -e "${BLUE}Creating service: ${service_name}${NC}"

    curl -s -X POST "${ADMIN}/services" \
        -H 'Content-Type: application/json' \
        -d "{
            \"name\": \"${service_name}\",
            \"host\": \"${upstream_name}\",
            \"port\": 8545,
            \"protocol\": \"http\",
            \"connect_timeout\": 60000,
            \"write_timeout\": 60000,
            \"read_timeout\": 60000,
            \"retries\": 5,
            \"tags\": [\"rpc\", \"${chain_slug}\"]
        }" | jq -r '.name // "exists"'
}

# Function to create route
create_route() {
    local chain_slug=$1
    local service_name="${chain_slug}-svc"
    local route_name="${chain_slug}-route"

    echo -e "${BLUE}Creating route: ${route_name}${NC}"

    # Get service ID
    SERVICE_ID=$(curl -s "${ADMIN}/services/${service_name}" | jq -r '.id')

    if [ -z "$SERVICE_ID" ] || [ "$SERVICE_ID" == "null" ]; then
        echo -e "${RED}ERROR: Service ${service_name} not found${NC}"
        return 1
    fi

    # Create route with pattern: /{api_key}/{chain-slug}
    curl -s -X POST "${ADMIN}/routes" \
        -H 'Content-Type: application/json' \
        -d "{
            \"name\": \"${route_name}\",
            \"service\": {\"id\": \"${SERVICE_ID}\"},
            \"paths\": [\"~/[^/]+/${chain_slug}$\"],
            \"strip_path\": false,
            \"methods\": [\"POST\", \"GET\", \"OPTIONS\"],
            \"tags\": [\"rpc\", \"${chain_slug}\"]
        }" | jq -r '.name // "exists"'

    # Get route ID for plugin configuration
    ROUTE_ID=$(curl -s "${ADMIN}/routes/${route_name}" | jq -r '.id')

    # Add pre-function plugin to extract API key and set upstream path
    echo -e "  Adding pre-function plugin..."
    read -r -d '' LUA_CODE << 'EOF' || true
local uri = kong.request.get_path()
local m = ngx.re.match(uri, [[^/([^/]+)/[^/]+$]], "jo")
if m and m[1] then
  local apikey = m[1]
  kong.log.debug("Extracted API key prefix: ", string.sub(apikey, 1, 8))
  ngx.req.set_header("apikey", apikey)
  kong.service.request.set_path("/")
  -- Remove API key from logs (security)
  kong.log.set_serialize_value("request.headers.apikey", "[REDACTED]")
else
  return kong.response.exit(400, {message = "Invalid path format. Use: /<API_KEY>/<CHAIN_SLUG>"})
end
EOF

    curl -s -X POST "${ADMIN}/routes/${ROUTE_ID}/plugins" \
        -H 'Content-Type: application/json' \
        -d "{
            \"name\": \"pre-function\",
            \"config\": {
                \"access\": [\"${LUA_CODE}\"]
            }
        }" | jq -r '.name // "exists"'

    # Add key-auth plugin
    echo -e "  Adding key-auth plugin..."
    curl -s -X POST "${ADMIN}/routes/${ROUTE_ID}/plugins" \
        -H 'Content-Type: application/json' \
        -d '{
            "name": "key-auth",
            "config": {
                "key_names": ["apikey"],
                "run_on_preflight": false,
                "hide_credentials": true
            }
        }' | jq -r '.name // "exists"'

    # Add rate limiting plugin (basic, will be enhanced with plan-based limits later)
    echo -e "  Adding rate-limiting plugin..."
    curl -s -X POST "${ADMIN}/routes/${ROUTE_ID}/plugins" \
        -H 'Content-Type: application/json' \
        -d '{
            "name": "rate-limiting",
            "config": {
                "minute": 1000,
                "hour": 50000,
                "policy": "local",
                "fault_tolerant": true,
                "hide_client_headers": false
            }
        }' | jq -r '.name // "exists"'

    # Add CORS plugin
    echo -e "  Adding CORS plugin..."
    curl -s -X POST "${ADMIN}/routes/${ROUTE_ID}/plugins" \
        -H 'Content-Type: application/json' \
        -d '{
            "name": "cors",
            "config": {
                "origins": ["*"],
                "methods": ["GET", "POST", "OPTIONS"],
                "headers": ["Content-Type", "Authorization", "apikey"],
                "exposed_headers": ["X-RateLimit-Limit-Minute", "X-RateLimit-Remaining-Minute"],
                "credentials": true,
                "max_age": 3600
            }
        }' | jq -r '.name // "exists"'

    echo -e "${GREEN}✓ Route ${route_name} configured${NC}"
    echo ""
}

# ============================================================================
# Main Setup
# ============================================================================

echo -e "${YELLOW}Setting up popular EVM chains...${NC}"
echo ""

# Ethereum Mainnet
create_upstream "eth-mainnet"
add_target "eth-mainnet-rpc" "eth-node-1.internal:8545"
add_target "eth-mainnet-rpc" "eth-node-2.internal:8545"
create_service "eth-mainnet"
create_route "eth-mainnet"

# Ethereum Sepolia (testnet)
create_upstream "eth-sepolia"
add_target "eth-sepolia-rpc" "sepolia-node-1.internal:8545"
create_service "eth-sepolia"
create_route "eth-sepolia"

# Arbitrum One
create_upstream "arb-mainnet"
add_target "arb-mainnet-rpc" "arb-node-1.internal:8545"
create_service "arb-mainnet"
create_route "arb-mainnet"

# Polygon
create_upstream "polygon-mainnet"
add_target "polygon-mainnet-rpc" "polygon-node-1.internal:8545"
create_service "polygon-mainnet"
create_route "polygon-mainnet"

# Base
create_upstream "base-mainnet"
add_target "base-mainnet-rpc" "base-node-1.internal:8545"
create_service "base-mainnet"
create_route "base-mainnet"

# Optimism
create_upstream "op-mainnet"
add_target "op-mainnet-rpc" "op-node-1.internal:8545"
create_service "op-mainnet"
create_route "op-mainnet"

# Add global Prometheus plugin if not exists
echo -e "${BLUE}Adding Prometheus plugin...${NC}"
curl -s -X POST "${ADMIN}/plugins" \
    -H 'Content-Type: application/json' \
    -d '{
        "name": "prometheus",
        "config": {
            "per_consumer": true,
            "status_code_metrics": true,
            "latency_metrics": true,
            "bandwidth_metrics": true,
            "upstream_health_metrics": true
        }
    }' | jq -r '.name // "exists"'

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Available endpoints:"
echo -e "  - ${PROXY}/YOUR_API_KEY/eth-mainnet"
echo -e "  - ${PROXY}/YOUR_API_KEY/eth-sepolia"
echo -e "  - ${PROXY}/YOUR_API_KEY/arb-mainnet"
echo -e "  - ${PROXY}/YOUR_API_KEY/polygon-mainnet"
echo -e "  - ${PROXY}/YOUR_API_KEY/base-mainnet"
echo -e "  - ${PROXY}/YOUR_API_KEY/op-mainnet"
echo ""
echo -e "Next steps:"
echo -e "  1. Create a test consumer and API key"
echo -e "  2. Test with: curl -X POST ${PROXY}/YOUR_KEY/eth-mainnet \\"
echo -e "       -H 'Content-Type: application/json' \\"
echo -e "       -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
echo ""
