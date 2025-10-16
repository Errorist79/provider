#!/bin/bash

# ============================================================================
# Database Query Helper Script
# ============================================================================
# Easy access to PostgreSQL and ClickHouse for common queries

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default to app database
DB_TYPE="${1:-postgres}"

show_usage() {
    echo "Usage: $0 [postgres|clickhouse] [query]"
    echo ""
    echo "Examples:"
    echo "  $0 postgres"
    echo "  $0 postgres 'SELECT * FROM organizations;'"
    echo "  $0 clickhouse"
    echo "  $0 clickhouse 'SELECT chain_slug, count() FROM telemetry.requests_raw GROUP BY chain_slug;'"
    exit 1
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
fi

case "$DB_TYPE" in
    postgres|pg)
        if [ -z "$2" ]; then
            echo -e "${BLUE}=== PostgreSQL Interactive Console ===${NC}"
            docker-compose exec app-database psql -U rpcuser -d rpc_gateway
        else
            echo -e "${GREEN}Executing PostgreSQL query...${NC}"
            docker-compose exec -T app-database psql -U rpcuser -d rpc_gateway -c "$2"
        fi
        ;;
    clickhouse|ch)
        if [ -z "$2" ]; then
            echo -e "${BLUE}=== ClickHouse Interactive Console ===${NC}"
            docker-compose exec clickhouse clickhouse-client --database telemetry
        else
            echo -e "${GREEN}Executing ClickHouse query...${NC}"
            docker-compose exec -T clickhouse clickhouse-client --database telemetry --query "$2"
        fi
        ;;
    *)
        echo -e "${YELLOW}Unknown database type: $DB_TYPE${NC}"
        show_usage
        ;;
esac
