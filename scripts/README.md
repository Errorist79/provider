# Setup Scripts

Production-ready scripts for RPC Gateway management.

## Available Scripts

### `health-check.sh`
Check health of all services (Kong, Unkey, Auth Bridge, databases, observability stack).

```bash
./scripts/health-check.sh
```

### `init-root-key.sh`
Create or update Unkey root key in database.

**Development:**
```bash
./scripts/init-root-key.sh
# Press Enter to use default 'unkey_root'
```

**Production:**
```bash
# Generate secure key
openssl rand -base64 32

# Set environment variable
export UNKEY_ROOT_KEY="your-generated-key"

# Run script
./scripts/init-root-key.sh
```

### `create-customer-key.sh`
Create a customer API key with organization metadata.

```bash
./scripts/create-customer-key.sh <org_id> [plan] [key_name]

# Examples:
./scripts/create-customer-key.sh org_customer_123 pro "Production Key"
./scripts/create-customer-key.sh org_customer_456 basic
```

**Plans:** free, basic, pro, enterprise

### `verify-key.sh`
Verify an API key through Auth Bridge.

```bash
./scripts/verify-key.sh <api_key>

# Example:
./scripts/verify-key.sh sk_prod_xxxxxx
```

### `setup-kong-service.sh`
Create Kong service and route for RPC endpoint.

```bash
./scripts/setup-kong-service.sh <chain_slug> <upstream_url>

# Examples:
./scripts/setup-kong-service.sh eth-mainnet http://eth-node:8545
./scripts/setup-kong-service.sh polygon-mainnet http://polygon-node:8545
```

## Production Checklist

1. Generate secure root key: `openssl rand -base64 32`
2. Store in secrets manager (AWS Secrets Manager, Vault, etc.)
3. Set `UNKEY_ROOT_KEY` environment variable
4. Run `./scripts/init-root-key.sh`
5. Verify health: `./scripts/health-check.sh`
6. Create customer keys: `./scripts/create-customer-key.sh`

## Environment Variables

Required in `.env`:
```bash
UNKEY_ROOT_KEY=unkey_root                      # Change in production!
UNKEY_API_ID=api_local_root_keys               # Auto-populated
KONG_ADMIN_URL=http://localhost:8001
KONG_PROXY_URL=http://localhost:8000
UNKEY_BASE_URL=http://localhost:3001
AUTH_BRIDGE_URL=http://localhost:8081
```

## Archived Scripts

Old scripts moved to `scripts/archive/`:
- `setup-kong.sh` - Used pre-function plugins (deprecated)
- `setup-unkey.sh` - Workspace/API creation (manual setup now)
- `unkey.sh` - Duplicate of setup-unkey.sh
- `monitor-rate-limits.sh` - Outdated Prometheus queries
- `stats.sh` - Database tables don't exist

## See Also

- [SETUP.md](../SETUP.md) - Complete end-to-end setup guide
- [ARCHITECTURE.md](../docs/ARCHITECTURE.md) - System architecture
