# RPC Gateway - Quick Start Guide

This guide will help you get the RPC Gateway up and running on your local machine.

## Prerequisites

- Docker Engine 20.10+ and Docker Compose v2.0+
- At least 4GB of available RAM
- Ports available: 8000-8002, 8100, 8123, 9000, 5432, 6379, 9090, 3000

## Quick Start

### 1. Clone and Setup Environment

```bash
# Navigate to the gateway directory
cd gateway

# Copy the example environment file
cp .env.example .env

# Edit .env and update passwords and secrets
# IMPORTANT: Change all default passwords in production!
nano .env
```

### 2. Start All Services

```bash
# Start all services in detached mode
docker-compose up -d

# View logs
docker-compose logs -f

# Check service health
docker-compose ps
```

### 3. Verify Services

```bash
# Kong Admin API
curl http://localhost:8001/

# Kong Proxy (should return no route)
curl http://localhost:8000/

# Kong Manager UI
open http://localhost:8002

# Prometheus
open http://localhost:9090

# Grafana (admin/admin)
open http://localhost:3000

# PostgreSQL (application database)
docker-compose exec app-database psql -U rpcuser -d rpc_gateway

# ClickHouse
curl http://localhost:8123/
```

## Service Endpoints

| Service | Port(s) | Description |
|---------|---------|-------------|
| Kong Proxy | 8000, 8443 | Main gateway endpoint |
| Kong Admin API | 8001, 8444 | Kong configuration API |
| Kong Manager | 8002 | Web UI for Kong management |
| Kong Status | 8100 | Metrics and health endpoint |
| PostgreSQL (App) | 5432 | Application database |
| Redis | 6379 | Cache for Unkey verification |
| ClickHouse | 8123, 9000 | Telemetry and analytics |
| Prometheus | 9090 | Metrics collection |
| Grafana | 3000 | Metrics visualization |

## Initial Configuration

### Configure Kong for Ethereum RPC

```bash
# Set environment variables
export ADMIN=http://localhost:8001
export PROXY=http://localhost:8000

# 1. Create upstream for RPC nodes
curl -X POST $ADMIN/upstreams \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "eth-mainnet-rpc",
    "algorithm": "round-robin",
    "healthchecks": {
      "passive": {
        "unhealthy": {
          "http_failures": 3,
          "timeouts": 3
        }
      }
    }
  }'

# 2. Add RPC node targets (update with your node IPs)
curl -X POST $ADMIN/upstreams/eth-mainnet-rpc/targets \
  -H 'Content-Type: application/json' \
  -d '{"target": "YOUR_NODE_1:8545", "weight": 100}'

curl -X POST $ADMIN/upstreams/eth-mainnet-rpc/targets \
  -H 'Content-Type: application/json' \
  -d '{"target": "YOUR_NODE_2:8545", "weight": 100}'

# 3. Create service
curl -X POST $ADMIN/services \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "eth-mainnet-svc",
    "host": "eth-mainnet-rpc",
    "protocol": "http",
    "port": 8545,
    "connect_timeout": 60000,
    "write_timeout": 60000,
    "read_timeout": 60000
  }'

# 4. Create route with API key in path pattern
curl -X POST $ADMIN/services/eth-mainnet-svc/routes \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "eth-mainnet-route",
    "paths": ["~/[^/]+/eth"],
    "strip_path": false,
    "methods": ["POST", "OPTIONS"]
  }'

# 5. Get route ID for plugin configuration
ROUTE_ID=$(curl -s $ADMIN/routes | jq -r '.data[] | select(.name=="eth-mainnet-route") | .id')

# 6. Add pre-function plugin to extract API key from path
read -r -d '' LUA_CODE << 'EOF'
local uri = kong.request.get_path()
local m = ngx.re.match(uri, [[^/([^/]+)/eth]], "jo")
if m and m[1] then
  local apikey = m[1]
  kong.log.debug("Extracted API key prefix: ", string.sub(apikey, 1, 8))
  ngx.req.set_header("apikey", apikey)
  kong.service.request.set_path("/")
else
  return kong.response.exit(400, {message = "Invalid path format. Use: /<API_KEY>/eth"})
end
EOF

curl -X POST $ADMIN/routes/$ROUTE_ID/plugins \
  -H 'Content-Type: application/json' \
  -d "{
    \"name\": \"pre-function\",
    \"config\": {
      \"access\": [\"$LUA_CODE\"]
    }
  }"

# 7. Add key-auth plugin
curl -X POST $ADMIN/routes/$ROUTE_ID/plugins \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "key-auth",
    "config": {
      "key_names": ["apikey"],
      "run_on_preflight": false,
      "hide_credentials": true
    }
  }'

# 8. Add rate limiting plugin (basic)
curl -X POST $ADMIN/routes/$ROUTE_ID/plugins \
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
  }'

# 9. Add CORS plugin
curl -X POST $ADMIN/routes/$ROUTE_ID/plugins \
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
  }'

# 10. Add Prometheus plugin for metrics
curl -X POST $ADMIN/plugins \
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
  }'
```

### Create a Test Consumer and API Key

```bash
# Create a consumer
curl -X POST $ADMIN/consumers \
  -H 'Content-Type: application/json' \
  -d '{
    "username": "test-user",
    "custom_id": "test-org-001"
  }'

# Create API key for the consumer
curl -X POST $ADMIN/consumers/test-user/key-auth \
  -H 'Content-Type: application/json' \
  -d '{
    "key": "sk_test_1234567890abcdef"
  }'

# Test the setup
curl -X POST $PROXY/sk_test_1234567890abcdef/eth \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_blockNumber",
    "params": [],
    "id": 1
  }'
```

## Database Access

### PostgreSQL (Application DB)

```bash
# Connect to database
docker-compose exec app-database psql -U rpcuser -d rpc_gateway

# Common queries
\dt  # List tables
SELECT * FROM organizations;
SELECT * FROM plans;
SELECT * FROM subscriptions;
```

### ClickHouse (Analytics)

```bash
# Connect to ClickHouse
docker-compose exec clickhouse clickhouse-client

# Common queries
USE telemetry;
SHOW TABLES;
SELECT count() FROM requests_raw WHERE timestamp >= now() - INTERVAL 1 HOUR;
SELECT organization_id, sum(request_count) FROM usage_hourly GROUP BY organization_id;
```

## Monitoring

### Prometheus Queries

Visit http://localhost:9090 and try these queries:

- Request rate: `rate(kong_http_requests_total[5m])`
- Error rate: `rate(kong_http_requests_total{code=~"5.."}[5m])`
- Latency: `kong_latency_bucket`
- Upstream health: `kong_upstream_target_health`

### Grafana Dashboards

1. Visit http://localhost:3000 (admin/admin)
2. Add Prometheus data source: http://prometheus:9090
3. Add ClickHouse data source: http://clickhouse:8123
4. Import Kong dashboard or create custom dashboards

## Troubleshooting

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f kong
docker-compose logs -f app-database
docker-compose logs -f clickhouse
```

### Restart Services

```bash
# Restart all
docker-compose restart

# Restart specific service
docker-compose restart kong
```

### Reset Everything

```bash
# Stop and remove all containers, networks, volumes
docker-compose down -v

# Start fresh
docker-compose up -d
```

### Common Issues

**Port already in use:**
- Check what's using the port: `lsof -i :8000`
- Update port mappings in `.env` file

**Database connection failed:**
- Wait for health checks: `docker-compose ps`
- Check logs: `docker-compose logs kong-database`

**Kong migrations failed:**
- Ensure database is healthy first
- Manually run migrations: `docker-compose up kong-migrations`

## Next Steps

Now that your infrastructure is running, proceed to:

1. **Phase 2**: Set up database schemas and seed data
2. **Phase 3**: Integrate Unkey for API key management
3. **Phase 4**: Configure plan-based rate limiting
4. **Phase 5**: Set up SigNoz for full observability

See [Architecture Documentation](docs/README.md) for the full system design.

## Stopping Services

```bash
# Stop all services (preserves data)
docker-compose stop

# Stop and remove containers (preserves volumes)
docker-compose down

# Remove everything including volumes (DESTRUCTIVE)
docker-compose down -v
```

## Production Considerations

Before deploying to production:

1. Change all default passwords in `.env`
2. Enable HTTPS/TLS with proper certificates
3. Set up proper backup strategy for PostgreSQL and ClickHouse
4. Configure resource limits in docker-compose.yml
5. Set up log rotation
6. Enable Kong's Admin API authentication
7. Review and harden network security
8. Set up monitoring alerts
9. Configure automatic backups
10. Review data retention policies
