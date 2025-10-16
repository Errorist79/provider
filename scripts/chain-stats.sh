#!/bin/bash

# ============================================================================
# Chain Statistics Script
# ============================================================================
# Quick overview of chain usage and health

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Chain Statistics Dashboard${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if services are running
if ! docker-compose ps | grep -q "clickhouse.*Up"; then
    echo -e "${RED}ERROR: ClickHouse is not running!${NC}"
    echo "Start services with: docker-compose up -d"
    exit 1
fi

# Active chains from PostgreSQL
echo -e "${GREEN}Active Chains:${NC}"
docker-compose exec -T app-database psql -U rpcuser -d rpc_gateway -c "
SELECT
    name,
    slug,
    chain_type,
    chain_id,
    is_testnet
FROM chains
WHERE is_active = true
ORDER BY is_testnet, name;
" 2>/dev/null

echo ""

# Chain endpoints status
echo -e "${GREEN}Chain Endpoints:${NC}"
docker-compose exec -T app-database psql -U rpcuser -d rpc_gateway -c "
SELECT
    c.slug as chain,
    COUNT(e.id) as total_endpoints,
    COUNT(e.id) FILTER (WHERE e.is_healthy = true) as healthy,
    COUNT(e.id) FILTER (WHERE e.is_archive = true) as archive_nodes
FROM chains c
LEFT JOIN rpc_endpoints e ON c.id = e.chain_id AND e.is_active = true
WHERE c.is_active = true
GROUP BY c.slug
ORDER BY c.slug;
" 2>/dev/null

echo ""

# Check if there's any request data in ClickHouse
HAS_DATA=$(docker-compose exec -T clickhouse clickhouse-client --query "SELECT count() FROM telemetry.requests_raw;" 2>/dev/null || echo "0")

if [ "$HAS_DATA" -gt "0" ]; then
    echo -e "${GREEN}Request Volume (Last 24h):${NC}"
    docker-compose exec -T clickhouse clickhouse-client --query "
    SELECT
        chain_slug,
        count() as requests,
        countIf(is_error = 1) as errors,
        round(countIf(is_error = 1) / count() * 100, 2) as error_rate_pct,
        round(avg(latency_ms), 2) as avg_latency_ms
    FROM telemetry.requests_raw
    WHERE timestamp >= now() - INTERVAL 24 HOUR
    GROUP BY chain_slug
    ORDER BY requests DESC
    FORMAT PrettyCompact;
    " 2>/dev/null

    echo ""

    echo -e "${GREEN}Top RPC Methods (Last 24h):${NC}"
    docker-compose exec -T clickhouse clickhouse-client --query "
    SELECT
        chain_slug,
        rpc_method,
        count() as requests,
        round(avg(compute_units), 2) as avg_cu
    FROM telemetry.requests_raw
    WHERE timestamp >= now() - INTERVAL 24 HOUR
    GROUP BY chain_slug, rpc_method
    ORDER BY requests DESC
    LIMIT 10
    FORMAT PrettyCompact;
    " 2>/dev/null
else
    echo -e "${YELLOW}No request data yet. Start sending requests to see stats!${NC}"
    echo ""
    echo -e "Test with:"
    echo -e "  curl -X POST http://localhost:8000/YOUR_API_KEY/eth-mainnet \\"
    echo -e "    -H 'Content-Type: application/json' \\"
    echo -e "    -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
