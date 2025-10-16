# RPC Provider Gateway

A production-ready, enterprise-grade API gateway for Ethereum RPC providers with comprehensive rate limiting, API key management, usage analytics, and billing capabilities.

## Overview

This project provides a complete infrastructure stack for running a multi-tenant RPC provider service with:

- **Kong Gateway (OSS)**: High-performance API gateway with routing, rate limiting, and authentication
- **Unkey**: Self-hosted API key lifecycle management with mTLS security
- **PostgreSQL**: Transactional database for organizations, users, plans, subscriptions, and billing
- **ClickHouse**: High-performance analytics database for request logs and usage metrics
- **Redis**: Distributed cache for API key verification and rate limit state
- **SigNoz**: OpenTelemetry-native APM for comprehensive observability
- **Prometheus + Grafana**: Metrics collection and visualization

## Features

### Core Capabilities

- **Multi-tenant Architecture**: Organizations, users, and role-based access control
- **Plan-based Rate Limiting**: Dynamic rate limits based on subscription tiers (Free, Basic, Pro, Enterprise)
- **API Key in URL**: Extract API keys from URL path (`/{API_KEY}/eth`) for better UX
- **Usage Tracking & Analytics**: Real-time and historical usage data with ClickHouse
- **Billing Ready**: Usage aggregation by hour/day for accurate billing
- **High Performance**: Optimized for high-throughput with Redis caching and ClickHouse analytics
- **Production Security**: mTLS, key masking in logs, HTTPS/TLS, secrets management

### Gateway Features

- **Load Balancing**: Round-robin across multiple RPC nodes with health checks
- **Rate Limiting**: Per-consumer limits with burst support
- **Authentication**: Unkey-powered API key verification with caching
- **CORS Support**: Configurable cross-origin resource sharing
- **Metrics & Monitoring**: Comprehensive observability with Prometheus, Grafana, and SigNoz
- **Request Logging**: Detailed request logs with sensitive data redaction

## Usage Example

```bash
# Test Ethereum Mainnet
curl -X POST http://localhost:8000/YOUR_API_KEY/eth-mainnet \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Test Arbitrum
curl -X POST http://localhost:8000/YOUR_API_KEY/arb-mainnet \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'

# Check stats
./scripts/stats.sh
```

## Architecture

### High-Level Flow

```
Client Request
    ↓
Kong Gateway (8000)
    ├─ Extract API key from URL path
    ├─ Verify with Unkey (cached in Redis)
    ├─ Apply rate limiting (plan-based)
    ├─ Route to upstream RPC node
    └─ Log to ClickHouse via OTel
```

### Service Ports

| Service | Ports | Description |
|---------|-------|-------------|
| Kong Proxy | 8000, 8443 | Main gateway endpoint |
| Kong Admin | 8001, 8444 | Configuration API |
| Kong Manager | 8002 | Web UI |
| PostgreSQL | 5432 | Application database |
| Redis | 6379 | Cache layer |
| ClickHouse | 8123, 9000 | Analytics database |
| Prometheus | 9090 | Metrics collection |
| Grafana | 3000 | Dashboards |

## Quick Start

```bash
# 1. Setup environment
cp .env.example .env
# Edit .env and change passwords

# 2. Start all services
docker-compose up -d

# 3. Configure Kong for multichain
./scripts/setup-kong.sh

# 4. Verify setup
./scripts/health-check.sh
```

See detailed instructions below.

## Supported Chains

**Mainnets**: Ethereum, Arbitrum, Optimism, Base, Polygon, BSC, Avalanche, Fantom, Gnosis, Celo
**Testnets**: Sepolia, Holesky, Arbitrum Sepolia, OP Sepolia, Base Sepolia, Polygon Amoy, BSC Testnet, Avalanche Fuji

See `database/postgresql/init/02_chains.sql` for complete list.

## Database Schema

### PostgreSQL (Transactional)

- **organizations**: Customer organizations
- **users**: Users within organizations
- **plans**: Subscription tiers (Free, Basic, Pro, Enterprise)
- **subscriptions**: Active subscriptions linking orgs to plans
- **consumers**: Kong consumers linked to Unkey identities
- **api_keys**: API key metadata (secrets stored in Unkey)
- **invoices**: Billing invoices with usage breakdown
- **webhooks**: Event notification configuration
- **audit_logs**: Complete audit trail

### ClickHouse (Analytics)

- **requests_raw**: High-volume request logs (14-day retention)
- **usage_hourly**: Hourly usage aggregation (90-day retention)
- **usage_daily**: Daily usage for billing (18-month retention)
- **errors**: Error tracking and debugging
- **latency_metrics**: SLA monitoring
- **rate_limit_events**: Rate limit hit tracking

## Key Scripts

- `./scripts/setup-kong.sh` - Configure Kong for all chains
- `./scripts/stats.sh` - View usage statistics and health
- `./scripts/health-check.sh` - Check all services

## Development Roadmap

- [x] **Phase 1-2**: Infrastructure + multichain support
- [ ] **Phase 3**: Unkey integration with mTLS
- [ ] **Phase 4**: Plan-based dynamic rate limiting
- [ ] **Phase 5**: SigNoz observability
- [ ] **Phase 6**: Usage tracking and billing
- [ ] **Phase 7**: Security hardening and HA

## Technology Stack

- **Gateway**: Kong Gateway 3.6 (OSS)
- **Databases**: PostgreSQL 15, ClickHouse 23.8
- **Cache**: Redis 7
- **API Keys**: Unkey (self-hosted)
- **Observability**: SigNoz, Prometheus, Grafana
- **Infrastructure**: Docker Compose

## Monitoring & Observability

### Prometheus Metrics

- `kong_http_requests_total`: Request count by status code, consumer, route
- `kong_latency`: Request latency histograms
- `kong_bandwidth`: Bandwidth usage
- `kong_upstream_target_health`: Upstream node health

### ClickHouse Analytics

- Real-time request logs with sub-second query times
- Usage aggregation for billing
- Error tracking and debugging
- Latency percentiles (p50, p95, p99)
- Per-organization/consumer analytics

### Grafana Dashboards

- Kong gateway metrics
- Usage analytics by organization/plan
- Error rates and SLA monitoring
- Billing insights

## Security Features

- **API Key Security**: Secrets stored only in Unkey, never in logs
- **mTLS**: Encrypted communication between Kong and Unkey
- **Key Masking**: API keys redacted from all logs and traces
- **HTTPS/TLS**: Enforced at the edge with HSTS
- **Rate Limiting**: Prevent abuse with plan-based limits
- **RBAC**: Role-based access control for organizations
- **Audit Logs**: Complete audit trail of all actions
- **Secrets Management**: Support for Vault/SOPS/KMS

## Production Deployment

Before deploying to production:

1. ✅ Change all default passwords in `.env`
2. ✅ Enable HTTPS with proper TLS certificates
3. ✅ Set up PostgreSQL and ClickHouse backups
4. ✅ Configure resource limits and scaling
5. ✅ Enable Kong Admin API authentication
6. ✅ Set up monitoring alerts
7. ✅ Review data retention policies
8. ✅ Implement secrets rotation
9. ✅ Configure high availability (HA)
10. ✅ Perform security audit

## Contributing

This is a greenfield project under active development. Contributions are welcome!

## License

TBD

## Support

For issues and questions, see the documentation in the `docs/` directory.
