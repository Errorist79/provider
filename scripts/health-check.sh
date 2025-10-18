#!/bin/bash
# Health check for all services

set -e
source "$(dirname "$0")/common.sh"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   RPC Gateway Health Check${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Core services
check_service "Kong Admin API" "$ADMIN/status" || true
check_service "Kong Proxy" "$PROXY/" || true
check_service "Unkey API" "$UNKEY_API/v2/liveness" || true
check_service "Auth Bridge" "$AUTH_BRIDGE/health" || true

echo ""
info "Observability Stack:"
check_service "ClickHouse" "http://localhost:8123/ping" || true
check_service "SigNoz UI" "http://localhost:3301/" || true
check_service "OTel Collector" "http://localhost:13133/" || true
check_service "Prometheus" "http://localhost:9090/-/healthy" || true
check_service "Grafana" "http://localhost:3000/api/health" || true

echo ""
info "Databases:"
if docker exec kong-db pg_isready -U kong >/dev/null 2>&1; then
    success "Kong PostgreSQL is ready"
else
    warn "Kong PostgreSQL is not ready"
fi

if docker exec unkey-mysql mysqladmin ping -h localhost -umysqluser -pmysqlpass >/dev/null 2>&1; then
    success "Unkey MySQL is ready"
else
    warn "Unkey MySQL is not ready"
fi

if docker exec redis redis-cli ping >/dev/null 2>&1; then
    success "Redis is ready"
else
    warn "Redis is not ready"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
success "Health check complete"
