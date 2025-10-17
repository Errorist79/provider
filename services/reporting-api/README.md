# Reporting API - Usage Analytics Service

High-performance Go microservice for querying RPC gateway usage analytics and metrics.

## Overview

The Reporting API is part of Phase 6 of the RPC Gateway project. It provides REST endpoints for retrieving usage data from ClickHouse and organization metadata from PostgreSQL.

**Key Features:**
- Real-time usage analytics
- Multi-chain usage breakdown
- RPC method statistics
- Hourly/daily/monthly aggregations
- Fast response times (< 200ms for typical queries)
- Prometheus metrics exposure
- Health check endpoints for Kubernetes/Docker
- Optional authentication (API key based)

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ HTTP/JSON
       ▼
┌─────────────────────────────────┐
│      Reporting API (Go)         │
│  ┌──────────┐   ┌─────────────┐ │
│  │ Handlers │──▶│ Middleware  │ │
│  └────┬─────┘   └─────────────┘ │
│       │                          │
│  ┌────▼──────────┐               │
│  │  Repository   │               │
│  └───┬───────┬───┘               │
└──────┼───────┼───────────────────┘
       │       │
       ▼       ▼
┌─────────┐ ┌───────────┐
│ClickHouse│ │PostgreSQL │
│(Telemetry)│ │(Metadata) │
└──────────┘ └───────────┘
```

## Quick Start

### Prerequisites

- Go 1.21+
- Docker & Docker Compose
- Running ClickHouse instance (with telemetry data)
- Running PostgreSQL instance (with org/plan data)

### Run with Docker Compose (Recommended)

```bash
# From the root of the gateway project
docker-compose up -d reporting-api

# Check logs
docker logs -f reporting-api

# Check health
curl http://localhost:4000/health
```

### Run Locally (Development)

```bash
cd services/reporting-api

# Install dependencies
go mod download

# Set environment variables
export REPORTING_API_CLICKHOUSE_HOST=localhost
export REPORTING_API_CLICKHOUSE_PORT=9000
export REPORTING_API_POSTGRESQL_HOST=localhost
export REPORTING_API_POSTGRESQL_PORT=5432

# Run the server
go run cmd/server/main.go
```

### Build from Source

```bash
# Build binary
go build -o bin/reporting-api ./cmd/server

# Run
./bin/reporting-api
```

## Configuration

Configuration is loaded from:
1. Environment variables (recommended for Docker)
2. Config file (`config.yaml`) - optional
3. Default values

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REPORTING_API_SERVER_PORT` | `8080` | HTTP server port |
| `REPORTING_API_SERVER_ENVIRONMENT` | `development` | Environment (development/production) |
| `REPORTING_API_CLICKHOUSE_HOST` | `localhost` | ClickHouse hostname |
| `REPORTING_API_CLICKHOUSE_PORT` | `9000` | ClickHouse native port |
| `REPORTING_API_CLICKHOUSE_DATABASE` | `telemetry` | ClickHouse database name |
| `REPORTING_API_CLICKHOUSE_USERNAME` | `default` | ClickHouse username |
| `REPORTING_API_CLICKHOUSE_PASSWORD` | `` | ClickHouse password |
| `REPORTING_API_POSTGRESQL_HOST` | `localhost` | PostgreSQL hostname |
| `REPORTING_API_POSTGRESQL_PORT` | `5432` | PostgreSQL port |
| `REPORTING_API_POSTGRESQL_DATABASE` | `rpc_gateway` | PostgreSQL database |
| `REPORTING_API_POSTGRESQL_USERNAME` | `rpcuser` | PostgreSQL username |
| `REPORTING_API_POSTGRESQL_PASSWORD` | `rpcpass` | PostgreSQL password |
| `REPORTING_API_AUTH_ENABLED` | `false` | Enable API key authentication |
| `REPORTING_API_AUTH_ADMINAPIKEY` | `` | Admin API key (if auth enabled) |
| `REPORTING_API_LOGGING_LEVEL` | `info` | Log level (debug/info/warn/error) |
| `REPORTING_API_LOGGING_FORMAT` | `json` | Log format (json/console) |

## API Endpoints

### Health Checks

**Liveness Probe** (always returns 200 if running)
```bash
GET /health/live
```

**Readiness Probe** (checks database connections)
```bash
GET /health/ready
```

**Detailed Health Check**
```bash
GET /health
```

### Metrics

**Prometheus Metrics**
```bash
GET /metrics
```

### Usage Analytics (v1)

All usage endpoints support authentication via `Authorization: Bearer <token>` header if auth is enabled.

#### 1. Organization Usage Summary

Get aggregated usage for an organization.

```bash
GET /api/v1/usage/organization/:orgId/summary
```

**Query Parameters:**
- `start_date` (optional): Start date (YYYY-MM-DD), defaults to first day of current month
- `end_date` (optional): End date (YYYY-MM-DD), defaults to now
- `include_breakdown` (optional): Include chain and method breakdowns (true/false)

**Example:**
```bash
curl "http://localhost:4000/api/v1/usage/organization/a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11/summary?start_date=2025-10-01&end_date=2025-10-31&include_breakdown=true"
```

**Response:**
```json
{
  "organization": {
    "id": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
    "name": "Acme Corporation",
    "plan_slug": "pro"
  },
  "usage": {
    "organization_id": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
    "period": {
      "start": "2025-10-01T00:00:00Z",
      "end": "2025-10-31T23:59:59Z"
    },
    "summary": {
      "total_requests": 12580450,
      "total_compute_units": 15234890,
      "total_egress_gb": 45.67,
      "error_count": 52837,
      "error_rate_pct": 0.42,
      "avg_latency_p95_ms": 234.5,
      "success_rate_pct": 99.58
    },
    "by_chain": [
      {
        "chain_slug": "eth-mainnet",
        "chain_type": "mainnet",
        "requests": 8234567,
        "compute_units": 10123456,
        "egress_gb": 32.1,
        "error_count": 34567,
        "error_rate_pct": 0.42,
        "avg_latency_p95_ms": 245.3
      }
    ],
    "top_methods": [
      {
        "method": "eth_getBlockByNumber",
        "requests": 4567890,
        "compute_units": 4567890,
        "error_count": 1234,
        "avg_latency_ms": 123.4
      }
    ]
  }
}
```

#### 2. Daily Usage Breakdown

Get daily usage aggregation.

```bash
GET /api/v1/usage/organization/:orgId/daily?start_date=2025-10-01&end_date=2025-10-31
```

**Response:**
```json
{
  "organization_id": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
  "period": {
    "start": "2025-10-01T00:00:00Z",
    "end": "2025-10-31T23:59:59Z"
  },
  "daily_usage": [
    {
      "date": "2025-10-01T00:00:00Z",
      "requests": 450123,
      "compute_units": 567890,
      "egress_gb": 1.82,
      "error_count": 1892,
      "error_rate_pct": 0.42,
      "success_rate_pct": 99.58
    }
  ]
}
```

#### 3. Hourly Usage Breakdown

Get hourly usage (limited to 7 days).

```bash
GET /api/v1/usage/organization/:orgId/hourly?start_date=2025-10-15&end_date=2025-10-16&chain=eth-mainnet
```

**Query Parameters:**
- `chain` (optional): Filter by specific chain slug

#### 4. Usage by Chain

Get usage broken down by blockchain.

```bash
GET /api/v1/usage/organization/:orgId/by-chain?start_date=2025-10-01&end_date=2025-10-31
```

#### 5. API Key Usage

Get usage for a specific API key.

```bash
GET /api/v1/usage/key/:keyPrefix?start_date=2025-10-01&end_date=2025-10-31
```

## Authentication

### Phase 6 (Current): Simple API Key

Set `REPORTING_API_AUTH_ENABLED=true` and `REPORTING_API_AUTH_ADMINAPIKEY=your_secret_key`

All requests must include:
```
Authorization: Bearer your_secret_key
```

### Phase 7+ (Future): Unkey Integration

Will integrate with Unkey for API key verification and JWT token validation.

## Performance

**Typical Query Times:**
- Summary endpoint: < 100ms
- Daily breakdown (30 days): < 150ms
- Hourly breakdown (7 days): < 200ms
- By chain breakdown: < 120ms

**Optimization:**
- Connection pooling (ClickHouse & PostgreSQL)
- Efficient SQL queries using materialized views
- LZ4 compression for ClickHouse queries
- Indexed columns for fast filtering

## Development

### Project Structure

```
reporting-api/
├── cmd/
│   └── server/
│       └── main.go              # Entry point
├── internal/
│   ├── config/                  # Configuration
│   ├── handlers/                # HTTP handlers
│   │   ├── health.go
│   │   ├── usage.go
│   │   └── metrics.go
│   ├── repository/              # Data access
│   │   ├── clickhouse.go
│   │   └── postgres.go
│   ├── models/                  # Domain models
│   │   └── usage.go
│   └── middleware/              # Middleware
│       └── auth.go
├── Dockerfile                   # Multi-stage build
├── go.mod
├── go.sum
└── README.md
```

### Testing

```bash
# Run tests
go test ./...

# Run with coverage
go test -cover ./...

# Run with race detector
go test -race ./...
```

### Linting

```bash
# Install golangci-lint
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

# Run linter
golangci-lint run
```

## Deployment

### Docker

```bash
# Build image
docker build -t reporting-api:latest .

# Run container
docker run -d \
  -p 8080:8080 \
  -e REPORTING_API_CLICKHOUSE_HOST=clickhouse \
  -e REPORTING_API_POSTGRESQL_HOST=postgres \
  --name reporting-api \
  reporting-api:latest
```

### Kubernetes

See example manifests in `k8s/` directory (coming in Phase 8).

**Recommended Resources:**
```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

**Horizontal Pod Autoscaler:**
```yaml
minReplicas: 2
maxReplicas: 10
targetCPUUtilizationPercentage: 70
```

## Monitoring

### Prometheus Metrics

The `/metrics` endpoint exposes:
- HTTP request count
- Request duration histograms
- Active connections
- Database query duration
- Error rates

**Example scrape config:**
```yaml
scrape_configs:
  - job_name: 'reporting-api'
    static_configs:
      - targets: ['reporting-api:8080']
```

### Grafana Dashboard

Import dashboard template from `monitoring/grafana/reporting-api-dashboard.json` (coming soon).

## Troubleshooting

### Connection Issues

**ClickHouse connection timeout:**
```bash
# Check ClickHouse is accessible
docker exec -it clickhouse clickhouse-client --query "SELECT 1"

# Check network connectivity
docker exec -it reporting-api wget -O- http://clickhouse:8123/ping
```

**PostgreSQL connection refused:**
```bash
# Check PostgreSQL is running
docker exec -it app-database pg_isready

# Check credentials
docker exec -it app-database psql -U rpcuser -d rpc_gateway -c "SELECT 1"
```

### Performance Issues

**Slow queries:**
- Check ClickHouse materialized views are populated
- Verify indexes exist on filter columns
- Use smaller date ranges for hourly queries

**High memory usage:**
- Reduce connection pool size
- Enable query result streaming for large datasets

## Roadmap

### Phase 6 (Current)
- [x] Basic usage endpoints
- [x] Health checks
- [x] Prometheus metrics
- [x] Docker deployment

### Phase 7
- [ ] Unkey integration for auth
- [ ] Redis caching layer
- [ ] WebSocket support for real-time updates
- [ ] Rate limiting per client

### Phase 8
- [ ] Kubernetes manifests
- [ ] Grafana dashboards
- [ ] Load testing results
- [ ] Production hardening

## Contributing

See main project [CONTRIBUTING.md](../../CONTRIBUTING.md).

## License

See main project [LICENSE](../../LICENSE).

## Support

For issues and questions:
- GitHub Issues: [rpc-gateway/issues](../../issues)
- Documentation: [docs/](../../docs/)
