#!/bin/bash

# Reporting API Test Script
# Tests all endpoints to verify the API is working correctly

set -e

API_URL="${API_URL:-http://localhost:4000}"
ORG_ID="${ORG_ID:-a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11}"
KEY_PREFIX="${KEY_PREFIX:-sk_prod_acme}"

echo "🧪 Testing Reporting API at $API_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

test_endpoint() {
    local name=$1
    local endpoint=$2
    local expected_status=${3:-200}

    echo -n "Testing $name... "

    status=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL$endpoint")

    if [ "$status" == "$expected_status" ]; then
        echo -e "${GREEN}✓ OK${NC} (HTTP $status)"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC} (Expected HTTP $expected_status, got $status)"
        return 1
    fi
}

test_endpoint_json() {
    local name=$1
    local endpoint=$2

    echo -n "Testing $name... "

    response=$(curl -s "$API_URL$endpoint")
    status=$?

    if [ $status -eq 0 ] && echo "$response" | jq . >/dev/null 2>&1; then
        echo -e "${GREEN}✓ OK${NC}"
        echo "$response" | jq -C '.' | head -20
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "Response: $response"
        return 1
    fi
}

echo ""
echo "📊 Health Checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_endpoint "Liveness probe" "/health/live" 200
test_endpoint "Readiness probe" "/health/ready" 200
test_endpoint_json "Health check" "/health"

echo ""
echo "📈 Metrics"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_endpoint "Prometheus metrics" "/metrics" 200

echo ""
echo "📊 Usage Endpoints"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Current month
start_date=$(date -u +"%Y-%m-01")
end_date=$(date -u +"%Y-%m-%d")

echo "Using date range: $start_date to $end_date"
echo ""

test_endpoint_json "Organization summary" "/api/v1/usage/organization/$ORG_ID/summary?start_date=$start_date&end_date=$end_date"

echo ""
test_endpoint_json "Organization summary (with breakdown)" "/api/v1/usage/organization/$ORG_ID/summary?start_date=$start_date&end_date=$end_date&include_breakdown=true"

echo ""
test_endpoint_json "Daily usage" "/api/v1/usage/organization/$ORG_ID/daily?start_date=$start_date&end_date=$end_date"

echo ""
test_endpoint_json "Usage by chain" "/api/v1/usage/organization/$ORG_ID/by-chain?start_date=$start_date&end_date=$end_date"

# Last 24 hours for hourly data
hourly_start=$(date -u -d "24 hours ago" +"%Y-%m-%d" 2>/dev/null || date -u -v-24H +"%Y-%m-%d")
hourly_end=$(date -u +"%Y-%m-%d")

echo ""
test_endpoint_json "Hourly usage" "/api/v1/usage/organization/$ORG_ID/hourly?start_date=$hourly_start&end_date=$hourly_end"

echo ""
test_endpoint_json "API key usage" "/api/v1/usage/key/$KEY_PREFIX?start_date=$start_date&end_date=$end_date"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ All tests completed!${NC}"
echo ""
echo "💡 Tip: Install jq for better JSON formatting"
echo "   brew install jq  # macOS"
echo "   apt install jq   # Ubuntu/Debian"
