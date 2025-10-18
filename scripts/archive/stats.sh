#!/bin/bash
# Unified stats dashboard - combines chain stats, DB queries, and health checks

set -e
source "$(dirname "$0")/common.sh"

show_chains() {
    info "Active Chains:"
    docker-compose exec -T app-database psql -U rpcuser -d rpc_gateway -c "
        SELECT slug, chain_type, chain_id, is_testnet
        FROM chains WHERE is_active = true
        ORDER BY is_testnet, name;" 2>/dev/null || warn "Database not accessible"
}

show_usage() {
    HAS_DATA=$(docker-compose exec -T clickhouse clickhouse-client --query "SELECT count() FROM telemetry.requests_raw;" 2>/dev/null || echo "0")

    if [ "$HAS_DATA" -gt "0" ]; then
        info "Request Volume (Last 24h):"
        docker-compose exec -T clickhouse clickhouse-client --query "
            SELECT chain_slug, count() as requests,
                   round(avg(latency_ms), 2) as avg_latency_ms
            FROM telemetry.requests_raw
            WHERE timestamp >= now() - INTERVAL 24 HOUR
            GROUP BY chain_slug ORDER BY requests DESC
            FORMAT PrettyCompact;" 2>/dev/null
    else
        warn "No request data yet"
    fi
}

show_health() {
    info "Service Health:"
    docker-compose ps 2>/dev/null | grep -E "kong|postgres|clickhouse|redis" || warn "Services not running"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   RPC Gateway Statistics${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

show_health
echo ""
show_chains
echo ""
show_usage

echo ""
echo -e "${BLUE}========================================${NC}"
