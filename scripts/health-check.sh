#!/bin/bash
# Health check for all services

set -e
source "$(dirname "$0")/common.sh"

echo -e "${BLUE}Checking RPC Gateway Health...${NC}"
echo ""

# Check services
check_service "Kong Admin" "$ADMIN/" || true
check_service "Kong Proxy" "$PROXY/" || true
check_service "Unkey" "http://localhost:3001/api/v1/liveness" || true
check_service "Prometheus" "http://localhost:9090/-/healthy" || true
check_service "Grafana" "http://localhost:3000/api/health" || true
check_service "ClickHouse" "http://localhost:8123/ping" || true

# Check databases
if docker-compose exec -T app-database pg_isready -U rpcuser >/dev/null 2>&1; then
    success "PostgreSQL is ready"
else
    warn "PostgreSQL is not ready"
fi

if docker-compose exec -T redis redis-cli ping >/dev/null 2>&1; then
    success "Redis is ready"
else
    warn "Redis is not ready"
fi

echo ""
info "Run './scripts/stats.sh' to see usage statistics"
