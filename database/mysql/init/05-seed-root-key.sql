-- Seed root key for self-hosted Unkey deployment
-- This creates a default development root key: "unkey_root"
-- Based on Unkey's CreateRootKey implementation in go/pkg/testutil/seed/seed.go
--
-- WARNING: For production, do NOT use this file!
-- Instead, run: scripts/init-root-key.sh with a secure generated key
--
-- This file is only for local development to make initial setup easier

USE unkey;

-- Insert development root key ONLY if in development mode
-- Key value: "unkey_root"
-- For production: Delete this file or use init-root-key.sh script
INSERT INTO `keys` (
  id,
  hash,
  workspace_id,
  for_workspace_id,
  key_auth_id,
  start,
  created_at_m,
  enabled,
  name,
  identity_id,
  meta,
  expires,
  remaining_requests,
  refill_day,
  refill_amount
) VALUES (
  'key_local_root',                                                    -- ID
  TO_BASE64(UNHEX(SHA2('unkey_root', 256))),                          -- Hash of "unkey_root" (base64 encoded)
  'ws_local_root',                                                    -- Root workspace
  'ws_local_root',                                                    -- For workspace (self-referencing)
  'ks_local_root_keys',                                              -- Keyring ID
  'unke',                                                             -- Start (first 4 chars of 'unkey_root')
  UNIX_TIMESTAMP() * 1000,                                            -- Created timestamp in milliseconds
  1,                                                                  -- Enabled
  'Development Root Key - DO NOT USE IN PRODUCTION',                  -- Name
  NULL,                                                               -- Identity ID
  NULL,                                                               -- Meta
  NULL,                                                               -- Expires
  NULL,                                                               -- Remaining requests
  NULL,                                                               -- Refill day
  NULL                                                                -- Refill amount
) ON DUPLICATE KEY UPDATE enabled = 1;
