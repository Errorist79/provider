#!/bin/bash
# Initialize Unkey root key in database
# This script should be run ONCE after first deployment

set -e
source "$(dirname "$0")/common.sh"

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | grep -E "UNKEY_MYSQL|UNKEY_ROOT_KEY" | xargs)
fi

MYSQL_HOST="${UNKEY_MYSQL_HOST:-unkey-mysql}"
MYSQL_USER="${UNKEY_MYSQL_USER:-mysqluser}"
MYSQL_PASS="${UNKEY_MYSQL_PASSWORD:-mysqlpass}"
MYSQL_DB="${UNKEY_MYSQL_DB:-unkey}"

# Get root key from environment or prompt
if [ -z "$UNKEY_ROOT_KEY" ]; then
    warn "UNKEY_ROOT_KEY not set in environment"
    echo ""
    info "For production, generate a secure root key:"
    echo "  openssl rand -base64 32"
    echo ""
    read -p "Enter root key value (or press Enter to use 'unkey_root' for development): " ROOT_KEY
    ROOT_KEY="${ROOT_KEY:-unkey_root}"
else
    ROOT_KEY="$UNKEY_ROOT_KEY"
    success "Using UNKEY_ROOT_KEY from environment"
fi

# Calculate hash (base64 encoded SHA256)
# We'll use Python since it's more portable than expecting specific shell tools
HASH=$(python3 -c "
import hashlib
import base64
key = '$ROOT_KEY'
hash_obj = hashlib.sha256(key.encode())
print(base64.b64encode(hash_obj.digest()).decode())
")

# Get first 4 characters for 'start' field
START="${ROOT_KEY:0:4}"

info "Initializing root key in database..."

# Check if root key already exists
EXISTING_KEY=$(docker exec unkey-mysql mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" "$MYSQL_DB" \
    -sN -e "SELECT id FROM \`keys\` WHERE id = 'key_production_root';" 2>/dev/null || echo "")

if [ -n "$EXISTING_KEY" ]; then
    warn "Root key already exists in database"
    echo ""
    read -p "Do you want to update it? (y/N): " UPDATE
    if [[ ! "$UPDATE" =~ ^[Yy]$ ]]; then
        info "Keeping existing root key"
        exit 0
    fi

    # Update existing key
    docker exec unkey-mysql mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" "$MYSQL_DB" <<EOF 2>&1 | grep -v Warning
UPDATE \`keys\`
SET hash = '$HASH',
    start = '$START',
    enabled = 1,
    updated_at_m = UNIX_TIMESTAMP() * 1000
WHERE id = 'key_production_root';
EOF
    success "Root key updated successfully"
else
    # Insert new key
    docker exec unkey-mysql mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" "$MYSQL_DB" <<EOF 2>&1 | grep -v Warning
INSERT INTO \`keys\` (
  id,
  hash,
  workspace_id,
  for_workspace_id,
  key_auth_id,
  start,
  created_at_m,
  enabled,
  name
) VALUES (
  'key_production_root',
  '$HASH',
  'ws_local_root',
  'ws_local_root',
  'ks_local_root_keys',
  '$START',
  UNIX_TIMESTAMP() * 1000,
  1,
  'Production Root Key'
);
EOF
    success "Root key created successfully"
fi

echo ""
info "Root key details:"
echo "  Key ID: key_production_root"
echo "  Start: $START"
if [ "$ROOT_KEY" = "unkey_root" ]; then
    warn "You are using the default development key!"
    warn "For production, regenerate with a secure random key"
fi

echo ""
info "Save this root key securely:"
echo "  UNKEY_ROOT_KEY=$ROOT_KEY"
echo ""
warn "This is the only time you'll see the full key value!"
warn "Store it in a secure location (e.g., secrets manager, 1Password, etc.)"
