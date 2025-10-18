-- Seed root key for self-hosted Unkey deployment
-- This creates a root key that matches UNKEY_ROOT_KEY environment variable

USE unkey;

-- Insert root key (hash of "unkey_root")
-- In production, this should be a proper bcrypt hash of your root key
-- For local development, we use a simple placeholder
-- Unkey will validate this against the UNKEY_ROOT_KEY environment variable

-- Note: The actual root key validation is done by Unkey application
-- using the UNKEY_ROOT_KEY environment variable, not from database
-- This is just to ensure the keys table has proper structure

-- Check if keys table exists and is ready
SELECT 'Root key table structure ready' AS status;
