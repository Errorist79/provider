-- Add wildcard permissions to root key
-- This grants full access to all APIs and operations

USE unkey;

-- Insert wildcard permissions for API operations
INSERT INTO permissions (id, workspace_id, name, slug, description, created_at_m) VALUES
  ('perm_local_api_create_key', 'ws_local_root', 'api.*.create_key', 'api.*.create_key', 'Permission to create keys on any API', UNIX_TIMESTAMP() * 1000),
  ('perm_local_api_verify_key', 'ws_local_root', 'api.*.verify_key', 'api.*.verify_key', 'Permission to verify keys on any API', UNIX_TIMESTAMP() * 1000),
  ('perm_local_api_read_api', 'ws_local_root', 'api.*.read_api', 'api.*.read_api', 'Permission to read API info', UNIX_TIMESTAMP() * 1000),
  ('perm_local_api_read_key', 'ws_local_root', 'api.*.read_key', 'api.*.read_key', 'Permission to read key info', UNIX_TIMESTAMP() * 1000)
ON DUPLICATE KEY UPDATE created_at_m = UNIX_TIMESTAMP() * 1000;

-- Link permissions to root key
INSERT INTO keys_permissions (key_id, permission_id, workspace_id, created_at_m) VALUES
  ('key_local_root', 'perm_local_api_create_key', 'ws_local_root', UNIX_TIMESTAMP() * 1000),
  ('key_local_root', 'perm_local_api_verify_key', 'ws_local_root', UNIX_TIMESTAMP() * 1000),
  ('key_local_root', 'perm_local_api_read_api', 'ws_local_root', UNIX_TIMESTAMP() * 1000),
  ('key_local_root', 'perm_local_api_read_key', 'ws_local_root', UNIX_TIMESTAMP() * 1000)
ON DUPLICATE KEY UPDATE created_at_m = UNIX_TIMESTAMP() * 1000;
