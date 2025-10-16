# Multichain RPC Provider Setup

This guide explains how to set up and use the multichain RPC provider gateway.

## Architecture

The gateway supports multiple blockchain networks with a unified API:

```
Client Request
    ↓
https://your-domain.com/{API_KEY}/{chain-slug}
    ↓
Kong Gateway
    ├─ Extract API key from URL
    ├─ Verify with Unkey (cached)
    ├─ Apply chain-specific rate limits
    ├─ Route to chain-specific upstream
    └─ Log to ClickHouse with chain metadata
```

## Supported Chains

### Mainnets
- **Ethereum**: `eth-mainnet` (Chain ID: 1)
- **Arbitrum One**: `arb-mainnet` (Chain ID: 42161)
- **Optimism**: `op-mainnet` (Chain ID: 10)
- **Base**: `base-mainnet` (Chain ID: 8453)
- **Polygon**: `polygon-mainnet` (Chain ID: 137)
- **Polygon zkEVM**: `polygon-zkevm` (Chain ID: 1101)
- **BSC**: `bsc-mainnet` (Chain ID: 56)
- **Avalanche**: `avax-mainnet` (Chain ID: 43114)
- **Fantom**: `ftm-mainnet` (Chain ID: 250)
- **Gnosis**: `gnosis-mainnet` (Chain ID: 100)
- **Celo**: `celo-mainnet` (Chain ID: 42220)

### Testnets
- **Ethereum Sepolia**: `eth-sepolia` (Chain ID: 11155111)
- **Ethereum Holesky**: `eth-holesky` (Chain ID: 17000)
- **Arbitrum Sepolia**: `arb-sepolia` (Chain ID: 421614)
- **Optimism Sepolia**: `op-sepolia` (Chain ID: 11155420)
- **Base Sepolia**: `base-sepolia` (Chain ID: 84532)
- **Polygon Amoy**: `polygon-amoy` (Chain ID: 80002)
- **BSC Testnet**: `bsc-testnet` (Chain ID: 97)
- **Avalanche Fuji**: `avax-fuji` (Chain ID: 43113)

### Coming Soon
- **Solana Mainnet**: `sol-mainnet`
- **Solana Devnet**: `sol-devnet`

## Quick Start

### 1. Start Services

```bash
# Start all services
docker-compose up -d

# Wait for services to be healthy
docker-compose ps
```

### 2. Configure Kong for Multichain

```bash
# Run the multichain setup script
./config/kong/multichain-setup.sh
```

This creates:
- Upstreams for each chain
- Services for each chain
- Routes with pattern: `/{API_KEY}/{chain-slug}`
- Plugins: key-auth, rate-limiting, CORS, pre-function

### 3. Create a Test Consumer

```bash
ADMIN=http://localhost:8001

# Create consumer
curl -X POST $ADMIN/consumers \
  -H 'Content-Type: application/json' \
  -d '{
    "username": "test-user",
    "custom_id": "test-org-001"
  }'

# Create API key
curl -X POST $ADMIN/consumers/test-user/key-auth \
  -H 'Content-Type: application/json' \
  -d '{
    "key": "sk_test_your_api_key_here"
  }'
```

### 4. Test Multichain Access

```bash
API_KEY="sk_test_your_api_key_here"
PROXY=http://localhost:8000

# Ethereum Mainnet
curl -X POST $PROXY/$API_KEY/eth-mainnet \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_blockNumber",
    "params": [],
    "id": 1
  }'

# Arbitrum
curl -X POST $PROXY/$API_KEY/arb-mainnet \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_chainId",
    "params": [],
    "id": 1
  }'

# Polygon
curl -X POST $PROXY/$API_KEY/polygon-mainnet \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_gasPrice",
    "params": [],
    "id": 1
  }'

# Base
curl -X POST $PROXY/$API_KEY/base-mainnet \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_blockNumber",
    "params": [],
    "id": 1
  }'
```

## Chain-Specific Features

### Archive Nodes

Some chains have dedicated archive node endpoints for historical state queries:

```bash
# Requires Pro plan or higher
curl -X POST $PROXY/$API_KEY/eth-mainnet \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_getBalance",
    "params": ["0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb", "0x1000000"],
    "id": 1
  }'
```

### Trace Methods

Enterprise plans have access to trace/debug methods:

```bash
# Requires Enterprise plan
curl -X POST $PROXY/$API_KEY/eth-mainnet \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "debug_traceTransaction",
    "params": ["0x..."],
    "id": 1
  }'
```

## Plan-Based Access Control

### Free Plan
- Access: All chains
- Rate Limit: 100 req/min per chain
- Archive: No
- Trace: No
- WebSocket: Yes

### Basic Plan
- Access: All chains
- Rate Limit: 1,000 req/min per chain
- Archive: No
- Trace: No
- WebSocket: Yes

### Pro Plan
- Access: All chains
- Rate Limit: 10,000 req/min per chain
- Archive: Yes
- Trace: Yes
- WebSocket: Yes

### Enterprise Plan
- Access: All chains (custom)
- Rate Limit: Custom per chain
- Archive: Yes
- Trace: Yes
- WebSocket: Yes
- Dedicated nodes available

## Adding a New Chain

### 1. Add Chain to Database

```sql
INSERT INTO chains (name, slug, chain_type, chain_id, display_name, native_currency)
VALUES (
    'New Chain',
    'newchain-mainnet',
    'evm',
    '999',
    'NewChain',
    '{"symbol": "NEW", "name": "NewToken", "decimals": 18}'
);
```

### 2. Add RPC Endpoints

```sql
INSERT INTO rpc_endpoints (chain_id, name, url, endpoint_type, weight, is_active)
VALUES
    ((SELECT id FROM chains WHERE slug = 'newchain-mainnet'),
     'NewChain Node 1',
     'http://newchain-node-1.internal:8545',
     'http',
     100,
     true),
    ((SELECT id FROM chains WHERE slug = 'newchain-mainnet'),
     'NewChain Node 2',
     'http://newchain-node-2.internal:8545',
     'http',
     100,
     true);
```

### 3. Configure Kong

```bash
# Add to Kong via API or run multichain-setup.sh again
CHAIN_SLUG="newchain-mainnet"

# Create upstream
curl -X POST $ADMIN/upstreams \
  -d "name=${CHAIN_SLUG}-rpc"

# Add targets
curl -X POST $ADMIN/upstreams/${CHAIN_SLUG}-rpc/targets \
  -d "target=newchain-node-1.internal:8545"

# Create service
curl -X POST $ADMIN/services \
  -d "name=${CHAIN_SLUG}-svc" \
  -d "host=${CHAIN_SLUG}-rpc"

# Create route (see multichain-setup.sh for full configuration)
```

## Monitoring & Analytics

### View Chain Statistics

```bash
# Run the chain stats script
./scripts/chain-stats.sh
```

### Query Usage by Chain

```sql
-- PostgreSQL: Chain endpoints health
SELECT * FROM v_chains_status;

-- ClickHouse: Requests by chain (last 24h)
SELECT
    chain_slug,
    count() as requests,
    uniq(consumer_id) as unique_users,
    avg(latency_ms) as avg_latency
FROM telemetry.requests_raw
WHERE timestamp >= now() - INTERVAL 24 HOUR
GROUP BY chain_slug
ORDER BY requests DESC;

-- ClickHouse: Most popular methods by chain
SELECT
    chain_slug,
    rpc_method,
    count() as requests
FROM telemetry.requests_raw
WHERE timestamp >= now() - INTERVAL 24 HOUR
GROUP BY chain_slug, rpc_method
ORDER BY chain_slug, requests DESC;
```

### Grafana Dashboards

Create dashboards to visualize:
- Request volume by chain
- Chain latency comparison
- Error rates per chain
- Popular methods per chain
- Chain-specific costs

## Compute Units

Different RPC methods consume different compute units (CU):

| Method | CU | Notes |
|--------|-----|-------|
| eth_blockNumber | 1 | Cheapest |
| eth_call | 2 | Standard |
| eth_getLogs | 10 | Can be expensive |
| debug_traceTransaction | 50 | Very expensive |
| trace_block | 100 | Most expensive |

Compute units are tracked per request and used for:
- Usage-based billing
- Fair rate limiting
- Abuse prevention

## Chain-Specific Rate Limiting

Set custom rate limits per chain:

```sql
-- Set higher limits for testnets
INSERT INTO plan_chain_limits (plan_id, chain_id, rate_limit_per_minute)
VALUES
    ((SELECT id FROM plans WHERE slug = 'free'),
     (SELECT id FROM chains WHERE slug = 'eth-sepolia'),
     500);  -- 5x higher for testnet
```

## WebSocket Support

Coming soon: WebSocket endpoints for real-time subscriptions

```
wss://your-domain.com/{API_KEY}/{chain-slug}
```

## Troubleshooting

### Chain not responding

```bash
# Check upstream health
curl $ADMIN/upstreams/eth-mainnet-rpc/health

# Check targets
curl $ADMIN/upstreams/eth-mainnet-rpc/targets

# View recent errors
./scripts/db-query.sh clickhouse "
  SELECT timestamp, chain_slug, error_message
  FROM telemetry.errors
  WHERE timestamp >= now() - INTERVAL 1 HOUR
  ORDER BY timestamp DESC
  LIMIT 10
"
```

### High latency

```bash
# Check chain latency
./scripts/chain-stats.sh

# View slow queries
./scripts/db-query.sh clickhouse "
  SELECT chain_slug, rpc_method, latency_ms
  FROM telemetry.requests_raw
  WHERE timestamp >= now() - INTERVAL 1 HOUR
    AND latency_ms > 1000
  ORDER BY latency_ms DESC
  LIMIT 20
"
```

## Next Steps

1. Add more chains to the database
2. Configure plan-based chain access
3. Set up chain-specific monitoring alerts
4. Implement WebSocket support
5. Add chain health checks
6. Configure automatic failover

## Resources

- [Kong Admin API](http://localhost:8001)
- [Kong Manager](http://localhost:8002)
- [Prometheus](http://localhost:9090)
- [Grafana](http://localhost:3000)
- [ClickHouse](http://localhost:8123)
