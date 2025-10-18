#!/bin/bash
# Monitor rate limit usage in real-time

set -e
source "$(dirname "$0")/common.sh"

info "Rate Limit Monitor (real-time)"
echo ""

# Check if Prometheus is available
if ! curl -sf "http://localhost:9090/-/healthy" >/dev/null 2>&1; then
    error "Prometheus is not running"
fi

# Function to query Prometheus
prom_query() {
    local query=$1
    curl -s "http://localhost:9090/api/v1/query?query=${query}" | jq -r '.data.result[]'
}

# Monitor loop
while true; do
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   Rate Limit Monitor${NC}"
    echo -e "${BLUE}   $(date)${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # Total requests
    echo -e "${GREEN}Total Requests (last 1 min):${NC}"
    prom_query "sum(rate(kong_http_requests_total[1m])) by (code)" | \
        jq -r '.metric.code + ": " + (.value[1] | tonumber | floor | tostring)' 2>/dev/null || echo "No data"
    echo ""

    # Rate limit rejections
    echo -e "${YELLOW}Rate Limit Rejections (429):${NC}"
    prom_query "sum(rate(kong_http_requests_total{code=\"429\"}[1m])) by (consumer)" | \
        jq -r '.metric.consumer + ": " + (.value[1] | tonumber | floor | tostring) + " req/s"' 2>/dev/null || echo "None"
    echo ""

    # Top consumers
    echo -e "${GREEN}Top Consumers (req/min):${NC}"
    prom_query "topk(5, sum(rate(kong_http_requests_total[1m])) by (consumer))" | \
        jq -r '.metric.consumer + ": " + (.value[1] | tonumber * 60 | floor | tostring)' 2>/dev/null || echo "No data"
    echo ""

    # Expensive methods
    echo -e "${YELLOW}Expensive Methods (CU > 10):${NC}"
    prom_query "sum(rate(kong_http_requests_total{rpc_method=~\".*trace.*|.*debug.*|eth_getLogs\"}[1m])) by (rpc_method)" | \
        jq -r '.metric.rpc_method + ": " + (.value[1] | tonumber | floor | tostring) + " req/s"' 2>/dev/null || echo "None"
    echo ""

    echo -e "${BLUE}========================================${NC}"
    echo -e "Press Ctrl+C to exit"

    sleep 5
done
