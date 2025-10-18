# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a production-ready, multi-tenant RPC provider gateway built on Kong Gateway OSS with Unkey for API key management. The system routes blockchain RPC requests across multiple chains (Ethereum, Arbitrum, Optimism, etc.) with plan-based rate limiting, usage tracking, and comprehensive observability.

**Critical Architecture Principle**: Unkey is the sole source of truth for API key secrets. Kong handles routing and rate limiting. Auth Bridge is the stateless adapter between them. All components communicate via Docker internal networking (never localhost URLs in service-to-service calls).

## Development Commands

### Environment Setup

```bash
# Start all services (Kong, Unkey, databases, observability stack)
docker-compose up -d

# Stop all services
docker-compose down

# Clean restart (removes volumes - USE WITH CAUTION)
docker-compose down -v && docker-compose up -d

# Build custom Kong image with unkey-auth plugin
docker-compose build kong

# Rebuild specific service
docker-compose up -d --build auth-bridge
```

### Database Operations

```bash
# Kong PostgreSQL - check services/routes
docker exec -it kong-db psql -U kong -d kong -c "SELECT name, protocol FROM services;"

# Unkey MySQL - verify schema (28 tables required)
docker exec -it unkey-mysql mysql -uroot -pmysqlrootpass -e "USE unkey; SHOW TABLES;"

# ClickHouse - query traces (use v3 tables)
docker exec -it clickhouse clickhouse-client --query "
SELECT serviceName, name, count() as cnt
FROM signoz_traces.distributed_signoz_index_v3
WHERE timestamp > now() - INTERVAL 1 HOUR
GROUP BY serviceName, name
ORDER BY cnt DESC LIMIT 20;"

# ClickHouse - query usage data
docker exec -it clickhouse clickhouse-client --query "
SELECT chain_id, count() as requests, avg(latency_ms) as avg_latency
FROM telemetry.requests_raw
WHERE timestamp > now() - INTERVAL 1 HOUR
GROUP BY chain_id;"
```

### Unkey Operations

```bash
# Initialize Unkey workspace and root key
./scripts/setup-unkey.sh

# Create customer API key with organization metadata
curl -X POST http://localhost:3001/v2/keys.createKey \
  -H 'Authorization: Bearer unkey_root' \
  -H 'Content-Type: application/json' \
  -d '{
    "apiId": "api_local_root_keys",
    "name": "Customer-Org-123",
    "prefix": "sk_prod",
    "meta": {
      "organizationId": "org_customer_123",
      "plan": "pro"
    }
  }'

# Verify key via Auth Bridge
curl -X POST http://localhost:8081/api/v1/verify \
  -H 'Content-Type: application/json' \
  -d '{"api_key": "sk_prod_xxxxx"}'
```

### Kong Configuration

```bash
# Configure Kong for all chains
./scripts/setup-kong.sh

# List Kong services
curl -s http://localhost:8001/services | jq '.data[] | {name, url}'

# List Kong plugins
curl -s http://localhost:8001/plugins | jq '.data[] | {name, enabled}'

# Enable unkey-auth plugin globally
curl -X POST http://localhost:8001/plugins \
  --data name=unkey-auth \
  --data config.auth_bridge_url=http://auth-bridge:8081/api/v1/verify \
  --data config.timeout=5000 \
  --data config.keepalive=60000 \
  --data config.hide_credentials=true
```

### Testing

```bash
# End-to-end RPC test (valid key)
# Format: /<API_KEY>/<CHAIN_SLUG>
curl -X POST http://localhost:8000/sk_prod_xxxxx/eth-mainnet \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Test invalid key (should return 401)
curl -X POST http://localhost:8000/invalid_key/eth-mainnet \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Health check all services
./scripts/health-check.sh

# View usage statistics
./scripts/stats.sh

# Monitor rate limits in real-time
./scripts/monitor-rate-limits.sh
```

### Go Services (Auth Bridge, Reporting API)

```bash
# Auth Bridge - local development
cd services/auth-bridge
go run cmd/server/main.go

# Auth Bridge - run tests
cd services/auth-bridge
go test ./...

# Reporting API - local development
cd services/reporting-api
go run cmd/server/main.go

# Reporting API - run tests
cd services/reporting-api
go test ./...

# Update Go dependencies
go get -u ./...
go mod tidy
```

## Architecture Deep Dive

### Request Flow

```
Client Request: POST /<API_KEY>/<CHAIN_SLUG>
    ↓
Kong Gateway :8000
    ↓
[1] unkey-auth plugin (PRIORITY=1000)
    • Extract API key from URL path via regex: ^/([^/]+)/[^/]+$
    • HTTP POST to Auth Bridge: http://auth-bridge:8081/api/v1/verify
    • Auth Bridge → Unkey API: http://unkey:7070/v2/keys.verifyKey
    • Auth Bridge → Redis cache (60s TTL)
    • Set Kong Consumer: kong.client.authenticate(nil, {id: organizationId})
    • Set request headers:
      - X-Organization-Id
      - X-Plan (free/basic/pro/enterprise)
      - X-Key-Id
      - X-Key-Metadata (JSON with allowedChains, etc.)
    • Rewrite path: kong.service.request.set_path("/")
    • Hide credentials from logs if configured
    ↓
[2] rate-limiting plugin (PRIORITY=900)
    • Check consumer-based limits (per plan)
    • Policy: local (single-node) or cluster (Redis-backed)
    ↓
[3] Route to upstream RPC node
    • Kong service per chain (eth-mainnet, arb-mainnet, etc.)
    • Load balancing across multiple upstream nodes
    • Health checks and circuit breaking
    ↓
[4] OpenTelemetry tracing
    • Spans: kong, kong.router, kong.access.plugin.unkey-auth, kong.balancer
    • Export to otel-collector:4317
    • Storage: ClickHouse signoz_traces.distributed_signoz_index_v3
```

### Service Dependencies

**Critical**: All services use Docker internal network names, NOT localhost:
- Kong → Auth Bridge: `http://auth-bridge:8081`
- Auth Bridge → Unkey: `http://unkey:7070`
- Auth Bridge → Redis: `redis:6379`
- Kong → PostgreSQL: `kong-db:5432`
- Unkey → MySQL: `unkey-mysql:3306`
- OTel Collector → ClickHouse: `clickhouse:9000`

**External access** (from host):
- Kong Proxy: `http://localhost:8000`
- Kong Admin: `http://localhost:8001`
- Unkey API: `http://localhost:3001`
- SigNoz UI: `http://localhost:3301`
- ClickHouse: `http://localhost:8123`

### Kong Custom Plugin: unkey-auth

**Location**: `services/kong-plugins/unkey-auth/`

**Files**:
- `handler.lua` - Plugin execution logic (access phase)
- `schema.lua` - Configuration schema definition

**Key Functions**:
- `extract_api_key_from_path(path)` - Regex-based API key extraction
- `verify_with_auth_bridge(conf, api_key)` - HTTP POST to Auth Bridge with connection pooling
- `set_consumer(verification)` - Kong consumer authentication
- `set_metadata_headers(verification)` - Propagate org/plan metadata downstream

**Deployment**: Custom Kong image built via `services/kong/Dockerfile`:
```dockerfile
FROM kong:3.6
COPY services/kong-plugins/unkey-auth /usr/local/share/lua/5.1/kong/plugins/unkey-auth
```

**Enable**: Set `KONG_PLUGINS=bundled,unkey-auth` in docker-compose.yml

### Auth Bridge Service

**Purpose**: Stateless Go microservice that:
1. Accepts API key verification requests from Kong
2. Calls Unkey API (with Redis caching)
3. Returns enriched metadata (organizationId, plan, keyId, keyName, meta)

**Tech Stack**:
- Framework: Gin (Go web framework)
- Unkey SDK: `github.com/unkeyed/sdks/api/go/v2`
- Cache: `github.com/redis/go-redis/v9`
- Config: Viper

**API Endpoint**:
```
POST /api/v1/verify
Content-Type: application/json
Body: {"api_key": "sk_prod_xxxxx"}

Response (200 OK):
{
  "valid": true,
  "organization_id": "org_customer_123",
  "plan": "pro",
  "key_id": "key_abc123",
  "key_name": "Customer-Org-123",
  "meta": {
    "organizationId": "org_customer_123",
    "plan": "pro",
    "allowedChains": ["eth-mainnet", "arb-mainnet"]
  }
}

Response (401 Unauthorized):
{"valid": false, "error": "invalid key"}
```

### Database Schemas

**Unkey MySQL** (`database/mysql/init/02-main-schema.sql`):
- MUST use complete schema (28 tables) from `examples/unkey/go/pkg/db/schema.sql`
- Critical tables: `apis`, `keys`, `workspaces`, `identities`, `keys_roles`, `roles`, `roles_permissions`
- Missing RBAC tables will cause Unkey API failures

**Kong PostgreSQL**:
- Managed by Kong migrations (automatic)
- Stores: services, routes, plugins, consumers, certificates

**ClickHouse** (`database/clickhouse/init/01_schema.sql`):
- Database: `telemetry`
- Tables:
  - `requests_raw` (14-day retention, partitioned by day)
  - `usage_hourly` (90-day retention, materialized view)
  - `usage_daily` (540-day retention, materialized view)
  - `errors`, `latency_metrics`, `rate_limit_events`

**SigNoz ClickHouse**:
- Use `signoz_traces.distributed_signoz_index_v3` (NOT v2)
- Managed by SigNoz migrations

### Multi-Chain Routing

**Pattern**: Each chain has a dedicated Kong service + route:

```bash
# Service per chain
curl -X POST http://localhost:8001/services \
  --data name=eth-mainnet \
  --data url=http://eth-mainnet:8545

curl -X POST http://localhost:8001/services \
  --data name=arb-mainnet \
  --data url=http://arbitrum-one:8547

# Route per chain
curl -X POST http://localhost:8001/routes \
  --data service.name=eth-mainnet \
  --data 'paths[]=/eth-mainnet' \
  --data name=eth-mainnet-route
```

**Supported Chains**: See `database/postgresql/init/02_chains.sql` for complete list.

### Rate Limiting Strategy

**Plan-based limits** (per minute):
- Free: 100 requests/min
- Basic: 1,000 requests/min
- Pro: 10,000 requests/min
- Enterprise: 100,000 requests/min

**Implementation**:
- Kong `rate-limiting` plugin (PRIORITY=900, runs after auth)
- Consumer identified by `organizationId` from Unkey metadata
- Plan info in `X-Plan` header set by unkey-auth plugin
- Policy: `local` (single-node) or `cluster` (Redis-backed for multi-node)

**Future**: Compute-unit based metering (method costs: eth_blockNumber=1 CU, debug_traceTransaction=50 CU)

### Observability Stack

**OpenTelemetry**:
- Kong exports spans via `opentelemetry` plugin
- Collector: `otel-collector:4317` (gRPC) and `:4318` (HTTP)
- Storage: ClickHouse (SigNoz schema)

**SigNoz**:
- UI: `http://localhost:3301`
- Query service, frontend, alert manager
- Trace retention: configured in ClickHouse

**Prometheus**:
- Scrapes Kong metrics: `http://kong:8001/metrics`
- Port: `9090`
- Retention: 30 days (configurable)

**Grafana**:
- Port: `3000`
- Data sources: Prometheus, ClickHouse
- Dashboards: Kong metrics, usage analytics

## Critical Development Rules

### Service URLs - NEVER use localhost

**WRONG** (will fail in Docker network):
```bash
UNKEY_BASE_URL=http://localhost:3001  # ❌
auth_bridge_url=http://localhost:8081  # ❌
```

**CORRECT** (Docker service names):
```bash
UNKEY_BASE_URL=http://unkey:7070       # ✅
auth_bridge_url=http://auth-bridge:8081 # ✅
```

**Exception**: Host machine access (e.g., curl from terminal) uses localhost.

### Kong Plugin Development

**DO**:
- ✅ Create custom plugins in `services/kong-plugins/<plugin-name>/`
- ✅ Use Kong PDK (Plugin Development Kit): `kong.log`, `kong.request`, `kong.service.request`
- ✅ Rebuild Kong image after plugin changes: `docker-compose build kong`
- ✅ Set proper PRIORITY (1000+ for auth, 900 for rate-limiting)

**DON'T**:
- ❌ Use `pre-function` plugin for HTTP calls (sandbox restrictions)
- ❌ Use `require 'resty.http'` in pre-function (not allowed)
- ❌ Store secrets in Kong database (use Unkey)

### Database Schema Changes

**Unkey MySQL**:
- Always use complete schema from `examples/unkey/go/pkg/db/schema.sql`
- Never attempt "minimal schema" - missing tables/columns cause runtime failures
- Volume recreation required for schema changes: `docker-compose down -v`

**ClickHouse**:
- Schema in `database/clickhouse/init/01_schema.sql`
- TTL policies defined per table (ALTER TABLE ... MODIFY TTL)
- Partitioning by day for high-volume tables

**Kong PostgreSQL**:
- Managed by Kong - do not modify manually
- Migrations run automatically on startup

### Unkey API Keys

**Key Metadata Structure** (critical):
```json
{
  "apiId": "api_local_root_keys",
  "name": "Customer-Org-123",
  "prefix": "sk_prod",
  "meta": {
    "organizationId": "org_customer_123",    // REQUIRED by Auth Bridge
    "plan": "pro",                           // REQUIRED for rate limiting
    "allowedChains": ["eth-mainnet"]         // Optional, future scope control
  }
}
```

**Missing `organizationId` will cause Auth Bridge to fail.**

### Troubleshooting Common Issues

**Issue**: Auth Bridge connection refused
**Cause**: `.env` has `UNKEY_BASE_URL=http://localhost:3001`
**Fix**: Change to `UNKEY_BASE_URL=http://unkey:7070`

**Issue**: Kong plugin not loaded
**Cause**: `KONG_PLUGINS` environment variable missing plugin name
**Fix**: Set `KONG_PLUGINS=bundled,unkey-auth` in docker-compose.yml

**Issue**: Unkey API error "Table doesn't exist"
**Cause**: Incomplete MySQL schema (missing RBAC tables)
**Fix**: Replace `database/mysql/init/02-main-schema.sql` with complete schema from `examples/unkey/go/pkg/db/schema.sql`

**Issue**: No traces in ClickHouse
**Cause**: Querying wrong table version
**Fix**: Use `signoz_traces.distributed_signoz_index_v3` (not v2)

**Issue**: Rate limiting not working
**Cause**: Plugin priority conflict or consumer not set
**Fix**: Ensure `unkey-auth` (PRIORITY=1000) runs before `rate-limiting` (PRIORITY=900)

## File Structure

```
.
├── services/
│   ├── kong-plugins/
│   │   └── unkey-auth/           # Custom Kong plugin (Lua)
│   │       ├── handler.lua       # Plugin logic
│   │       └── schema.lua        # Config schema
│   ├── kong/
│   │   └── Dockerfile            # Custom Kong image
│   ├── auth-bridge/              # Go microservice
│   │   ├── cmd/server/main.go
│   │   ├── internal/             # Handlers, cache, config
│   │   └── go.mod
│   └── reporting-api/            # Go analytics API
│       ├── cmd/server/main.go
│       ├── internal/             # Repository, models
│       └── go.mod
├── database/
│   ├── mysql/init/               # Unkey schema (28 tables)
│   ├── postgresql/init/          # Kong + app schema
│   └── clickhouse/init/          # Telemetry schema
├── config/
│   └── kong/
│       ├── kong-otel-plugin.json # OpenTelemetry config
│       └── archive/              # Deprecated pre-function scripts
├── scripts/
│   ├── setup-unkey.sh            # Initialize Unkey workspace
│   ├── setup-kong.sh             # Configure Kong for all chains
│   ├── health-check.sh           # Service health verification
│   └── stats.sh                  # Usage statistics
├── docs/
│   ├── ARCHITECTURE.md           # High-level architecture
│   └── BILLING.md                # Billing implementation (future)
├── .env                          # Service configuration
├── docker-compose.yml            # Service orchestration
├── SETUP.md                      # End-to-end setup guide
└── README.md                     # Project overview
```

## Additional Resources

- **Kong Documentation**: https://docs.konghq.com/gateway/latest/
- **Kong Plugin Development**: https://docs.konghq.com/gateway/latest/plugin-development/
- **Unkey Documentation**: https://unkey.com/docs
- **SigNoz Documentation**: https://signoz.io/docs/
- **ClickHouse Documentation**: https://clickhouse.com/docs/

## Production Deployment Notes

- Replace all default passwords in `.env`
- Enable TLS for Kong Proxy (port 8443)
- Configure Kong Admin API authentication
- Set up PostgreSQL and ClickHouse backups
- Implement high availability (multiple Kong nodes)
- Use Redis-backed rate limiting for multi-node Kong
- Configure proper resource limits (CPU/memory)
- Set up monitoring alerts (Prometheus Alertmanager)
- Review data retention policies (ClickHouse TTL)
- Implement secrets rotation (Vault integration)
