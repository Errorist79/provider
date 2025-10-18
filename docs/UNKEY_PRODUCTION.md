# Unkey Production Deployment Guide

This guide covers secure deployment of Unkey in production environments.

## ⚠️ Security Warning

The default development setup includes a hardcoded root key (`unkey_root`) for convenience.
**NEVER use this in production!**

## Production Setup Steps

### 1. Generate Secure Root Key

Generate a cryptographically secure root key:

```bash
# Option 1: Using OpenSSL
openssl rand -base64 32

# Option 2: Using Python
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# Example output:
# xK9mP2nQ4rS5tU6vW7xY8zA1bC2dE3fG4hI5jK6lM7nO8
```

### 2. Store in Secrets Manager

**DO NOT** commit root keys to git or store in plain text files!

Store in a secure secrets manager:
- **AWS**: AWS Secrets Manager or Systems Manager Parameter Store
- **GCP**: Secret Manager
- **Azure**: Key Vault
- **HashiCorp**: Vault
- **Local Dev**: 1Password, Bitwarden, etc.

### 3. Set Environment Variable

Production `.env` file (gitignored):

```bash
# Production Unkey Configuration
UNKEY_ROOT_KEY=your-generated-secure-key-here
UNKEY_MYSQL_USER=unkey_prod
UNKEY_MYSQL_PASSWORD=your-mysql-password
UNKEY_MYSQL_ROOT_PASSWORD=your-mysql-root-password
UNKEY_MYSQL_DB=unkey
```

### 4. Remove Development Root Key

Before deploying to production, remove the development root key seed file:

```bash
# Option 1: Delete the development seed file
rm database/mysql/init/05-seed-root-key.sql

# Option 2: Rename it to prevent loading
mv database/mysql/init/05-seed-root-key.sql database/mysql/init/05-seed-root-key.sql.dev
```

### 5. Initialize Root Key

After first deployment, run the initialization script:

```bash
# This will read UNKEY_ROOT_KEY from environment
./scripts/init-root-key.sh
```

The script will:
- Read the root key from `UNKEY_ROOT_KEY` environment variable
- Hash it securely (SHA256 + base64)
- Insert it into the database
- Show you confirmation (but NOT the key value for security)

### 6. Verify Setup

Test that the root key works:

```bash
# Create a test API key
curl -X POST http://your-unkey-host:3001/v2/keys.createKey \
  -H "Authorization: Bearer $UNKEY_ROOT_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "apiId": "api_local_root_keys",
    "name": "Production Test Key",
    "prefix": "sk_prod"
  }'
```

Expected response:
```json
{
  "data": {
    "key": "sk_prod_...",
    "keyId": "key_..."
  }
}
```

## Environment-Specific Configuration

### Development
```bash
UNKEY_ROOT_KEY=unkey_root  # Hardcoded in 05-seed-root-key.sql
```

### Staging
```bash
UNKEY_ROOT_KEY=$(aws secretsmanager get-secret-value --secret-id staging/unkey/root-key --query SecretString --output text)
```

### Production
```bash
UNKEY_ROOT_KEY=$(aws secretsmanager get-secret-value --secret-id prod/unkey/root-key --query SecretString --output text)
```

## Key Rotation

To rotate the root key:

1. Generate new root key
2. Run `./scripts/init-root-key.sh` with update option
3. Update all references to use new key
4. Revoke old key if needed

## Backup & Recovery

### Backup Root Key Hash
```bash
docker exec unkey-mysql mysqldump -u unkey_prod -p unkey \
  --tables keys --where="id='key_production_root'" \
  > unkey_root_key_backup.sql
```

### Restore
```bash
docker exec -i unkey-mysql mysql -u unkey_prod -p unkey \
  < unkey_root_key_backup.sql
```

## Troubleshooting

### Root key authentication fails

Check if key exists in database:
```bash
docker exec unkey-mysql mysql -u unkey_prod -p unkey \
  -e "SELECT id, start, name, enabled FROM \`keys\` WHERE id LIKE '%root%';"
```

### Verify hash matches

The hash in database should be base64-encoded SHA256 of your root key.

To verify manually:
```bash
python3 -c "
import hashlib
import base64
key = 'your-root-key'
hash_obj = hashlib.sha256(key.encode())
print(base64.b64encode(hash_obj.digest()).decode())
"
```

Compare this output with the `hash` column in database.

## Security Best Practices

1. ✅ Use unique root keys per environment (dev/staging/prod)
2. ✅ Rotate root keys every 90 days
3. ✅ Audit root key usage regularly
4. ✅ Use least-privilege permissions (don't grant `api.*.*`)
5. ✅ Monitor failed authentication attempts
6. ✅ Enable audit logging
7. ✅ Use secrets manager (never plaintext)
8. ✅ Restrict network access to Unkey API

## References

- [Unkey Self-Hosted Documentation](https://github.com/unkeyed/unkey/tree/main/deployment)
- [Unkey API Reference](https://www.unkey.com/docs/api-reference/v2/overview)
- [Root Key Permissions](https://www.unkey.com/docs/security/root-keys)
