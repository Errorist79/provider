-- Initialize Unkey database for self-hosted deployment
-- Based on Unkey deployment examples

-- The database and user are already created by environment variables
-- Just seed the root key directly into the database

USE unkey;

-- Note: Unkey v2.0.28 manages schema migrations automatically
-- We just need to ensure the root key is properly set up

-- The UNKEY_ROOT_KEY environment variable should match what's configured in docker-compose
-- For local development: unkey_root
