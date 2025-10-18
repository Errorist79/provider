# Setup Scripts

This directory contains setup and utility scripts for the RPC Gateway.

## Unkey Setup Scripts

### `setup-unkey.sh`
Initializes Unkey service and verifies it's ready.

**Usage:**
```bash
./scripts/setup-unkey.sh
```

**What it does:**
- Waits for MySQL to be ready
- Waits for Unkey API to be ready
- Finds existing API configuration
- Saves API ID to `.env`
- Attempts to create test key (requires root key)

**When to run:** After first `docker-compose up` or when resetting Unkey

---

### `init-root-key.sh`
Creates or updates Unkey root key in database.

**⚠️ IMPORTANT FOR PRODUCTION**

**Development Usage:**
```bash
./scripts/init-root-key.sh
# Press Enter to use default 'unkey_root'
```

**Production Usage:**
```bash
# 1. Generate secure key
openssl rand -base64 32

# 2. Set in environment
export UNKEY_ROOT_KEY="your-generated-key"

# 3. Run script
./scripts/init-root-key.sh
```

**What it does:**
- Reads `UNKEY_ROOT_KEY` from environment (or prompts)
- Generates secure hash (SHA256 + base64)
- Inserts/updates root key in database
- Shows confirmation and warnings

**When to run:**
- First production deployment
- Root key rotation
- After database reset

---

## Production Deployment

**DO NOT use default development keys in production!**

See: [`docs/UNKEY_PRODUCTION.md`](../docs/UNKEY_PRODUCTION.md)

### Quick Production Checklist

1. ✅ Generate secure root key: `openssl rand -base64 32`
2. ✅ Store in secrets manager (AWS Secrets Manager, Vault, etc.)
3. ✅ Remove development seed: `rm database/mysql/init/05-seed-root-key.sql`
4. ✅ Set `UNKEY_ROOT_KEY` environment variable
5. ✅ Run `./scripts/init-root-key.sh`
6. ✅ Verify with test API call

---

## Environment Variables

### Required for Unkey:
```bash
UNKEY_ROOT_KEY=your-root-key-here          # Root key for API access
UNKEY_MYSQL_USER=mysqluser                 # MySQL username
UNKEY_MYSQL_PASSWORD=mysqlpass             # MySQL password
UNKEY_MYSQL_DB=unkey                       # Database name
```

### Optional:
```bash
UNKEY_BASE_URL=http://localhost:3001       # Unkey API endpoint
UNKEY_API_ID=api_local_root_keys           # API ID (auto-detected)
```

---

## Troubleshooting

### "Root key authentication fails"

Check if root key exists:
```bash
docker exec unkey-mysql mysql -umysqluser -pmysqlpass unkey \
  -e "SELECT id, name, enabled FROM \`keys\` WHERE id LIKE '%root%';"
```

### "Permission denied"

Add required permissions (see `database/mysql/init/06-seed-root-permissions.sql`)

### "Database not ready"

Wait for healthcheck:
```bash
docker-compose ps unkey-mysql
# Wait for "(healthy)" status
```

---

## Development vs Production

| Aspect | Development | Production |
|--------|-------------|------------|
| Root Key | `unkey_root` (hardcoded) | Generated secure key |
| Storage | In SQL seed file | Secrets manager |
| Rotation | Never | Every 90 days |
| Permissions | Wildcard (`api.*.*`) | Least privilege |
| Audit | Optional | Required |

---

## See Also

- [Unkey Production Guide](../docs/UNKEY_PRODUCTION.md)
- [Unkey Official Docs](https://www.unkey.com/docs)
- [Self-Hosted Setup](https://github.com/unkeyed/unkey/tree/main/deployment)
