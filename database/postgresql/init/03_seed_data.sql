-- ============================================================================
-- Seed Data for Development/Testing
-- ============================================================================

-- ============================================================================
-- Create a test organization
-- ============================================================================
INSERT INTO organizations (id, name, slug, email, status)
VALUES
    ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'Acme Corporation', 'acme-corp', 'admin@acme.example.com', 'active'),
    ('b1ffcd00-ad1c-5ff9-cc7e-7cc0cd491b22', 'Beta Labs', 'beta-labs', 'hello@betalabs.example.com', 'active'),
    ('20460adf-d589-4921-a78f-40e4d346f234', 'Gamma DAO', 'gamma-dao', 'dao@gamma.example.com', 'active')
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- Create test users
-- ============================================================================
INSERT INTO users (id, organization_id, email, name, role, status)
VALUES
    ('d070c9c9-85e5-4b35-a395-322e880c1eef', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'alice@acme.example.com', 'Alice Admin', 'owner', 'active'),
    ('d429914b-7667-4a62-a671-46023b291652', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'bob@acme.example.com', 'Bob Builder', 'admin', 'active'),
    ('1d9c90db-82f9-46cd-91c0-cf1829340528', 'b1ffcd00-ad1c-5ff9-cc7e-7cc0cd491b22', 'charlie@betalabs.example.com', 'Charlie Coder', 'owner', 'active')
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- Create subscriptions for test organizations
-- ============================================================================
INSERT INTO subscriptions (
    id,
    organization_id,
    plan_id,
    status,
    billing_period,
    current_period_start,
    current_period_end
)
VALUES
    -- Acme Corp on Pro plan
    (
        '8e0c7ed9-48d8-4ab0-a0b0-457a1e1d0eee',
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        (SELECT id FROM plans WHERE slug = 'pro'),
        'active',
        'monthly',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP + INTERVAL '30 days'
    ),
    -- Beta Labs on Basic plan
    (
        'db89d862-c718-4c9e-bb4c-9ecd2bb067c7',
        'b1ffcd00-ad1c-5ff9-cc7e-7cc0cd491b22',
        (SELECT id FROM plans WHERE slug = 'basic'),
        'active',
        'monthly',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP + INTERVAL '30 days'
    ),
    -- Gamma DAO on Free plan
    (
        '4340a8c7-d198-470f-9534-db7437cd0a4d',
        '20460adf-d589-4921-a78f-40e4d346f234',
        (SELECT id FROM plans WHERE slug = 'free'),
        'active',
        'monthly',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP + INTERVAL '30 days'
    )
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- Create test consumers (Kong consumers linked to Unkey identities)
-- ============================================================================
INSERT INTO consumers (
    id,
    organization_id,
    kong_consumer_id,
    unkey_identity_id,
    status
)
VALUES
    (
        'dfae3125-0ef6-4cb6-9228-78e2894fe0e6',
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        'kong_acme_001',
        'unkey_acme_identity_001',
        'active'
    ),
    (
        '25937f15-677d-4243-82b6-294e75462faa',
        'b1ffcd00-ad1c-5ff9-cc7e-7cc0cd491b22',
        'kong_beta_001',
        'unkey_beta_identity_001',
        'active'
    ),
    (
        'd5363f6c-dbc3-4959-9d30-5755b3c1fb63',
        '20460adf-d589-4921-a78f-40e4d346f234',
        'kong_gamma_001',
        'unkey_gamma_identity_001',
        'active'
    )
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- Create test API keys (metadata only, secrets in Unkey)
-- ============================================================================
INSERT INTO api_keys (
    id,
    organization_id,
    consumer_id,
    unkey_key_id,
    key_prefix,
    name,
    description,
    status,
    allowed_chains
)
VALUES
    (
        'd06c10bc-0a1b-4413-b17c-3f494143293e',
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        'dfae3125-0ef6-4cb6-9228-78e2894fe0e6',
        'unkey_key_acme_prod_001',
        'sk_prod_acme',
        'Acme Production Key',
        'Main production API key for Acme Corp',
        'active',
        '["*"]'
    ),
    (
        '4f51cee2-6e38-42b1-bdf4-53c18b88d2db',
        'b1ffcd00-ad1c-5ff9-cc7e-7cc0cd491b22',
        '25937f15-677d-4243-82b6-294e75462faa',
        'unkey_key_beta_dev_001',
        'sk_dev_beta',
        'Beta Dev Key',
        'Development API key for Beta Labs',
        'active',
        '["eth-mainnet", "eth-sepolia", "polygon-mainnet"]'
    ),
    (
        '096c8ef4-36f0-4d9d-be50-5f17e3a20d48',
        '20460adf-d589-4921-a78f-40e4d346f234',
        'd5363f6c-dbc3-4959-9d30-5755b3c1fb63',
        'unkey_key_gamma_test_001',
        'sk_test_gamma',
        'Gamma Test Key',
        'Test API key for Gamma DAO',
        'active',
        '["eth-sepolia", "polygon-amoy"]'
    )
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- Add some RPC endpoints for popular chains
-- ============================================================================

-- Ethereum Mainnet endpoints
INSERT INTO rpc_endpoints (chain_id, name, url, endpoint_type, is_archive, weight, is_active, provider)
VALUES
    ((SELECT id FROM chains WHERE slug = 'eth-mainnet'), 'Ethereum Node 1', 'http://eth-node-1.internal:8545', 'http', false, 100, true, 'internal'),
    ((SELECT id FROM chains WHERE slug = 'eth-mainnet'), 'Ethereum Node 2', 'http://eth-node-2.internal:8545', 'http', false, 100, true, 'internal'),
    ((SELECT id FROM chains WHERE slug = 'eth-mainnet'), 'Ethereum Archive', 'http://eth-archive.internal:8545', 'http', true, 50, true, 'internal')
ON CONFLICT DO NOTHING;

-- Ethereum Sepolia testnet
INSERT INTO rpc_endpoints (chain_id, name, url, endpoint_type, is_archive, weight, is_active, provider)
VALUES
    ((SELECT id FROM chains WHERE slug = 'eth-sepolia'), 'Sepolia Node 1', 'http://sepolia-node-1.internal:8545', 'http', false, 100, true, 'internal'),
    ((SELECT id FROM chains WHERE slug = 'eth-sepolia'), 'Sepolia Node 2', 'http://sepolia-node-2.internal:8545', 'http', false, 100, true, 'internal')
ON CONFLICT DO NOTHING;

-- Arbitrum One
INSERT INTO rpc_endpoints (chain_id, name, url, endpoint_type, is_archive, weight, is_active, provider)
VALUES
    ((SELECT id FROM chains WHERE slug = 'arb-mainnet'), 'Arbitrum Node 1', 'http://arb-node-1.internal:8545', 'http', false, 100, true, 'internal'),
    ((SELECT id FROM chains WHERE slug = 'arb-mainnet'), 'Arbitrum Node 2', 'http://arb-node-2.internal:8545', 'http', false, 100, true, 'internal')
ON CONFLICT DO NOTHING;

-- Polygon
INSERT INTO rpc_endpoints (chain_id, name, url, endpoint_type, is_archive, weight, is_active, provider)
VALUES
    ((SELECT id FROM chains WHERE slug = 'polygon-mainnet'), 'Polygon Node 1', 'http://polygon-node-1.internal:8545', 'http', false, 100, true, 'internal'),
    ((SELECT id FROM chains WHERE slug = 'polygon-mainnet'), 'Polygon Node 2', 'http://polygon-node-2.internal:8545', 'http', false, 100, true, 'internal')
ON CONFLICT DO NOTHING;

-- Base
INSERT INTO rpc_endpoints (chain_id, name, url, endpoint_type, is_archive, weight, is_active, provider)
VALUES
    ((SELECT id FROM chains WHERE slug = 'base-mainnet'), 'Base Node 1', 'http://base-node-1.internal:8545', 'http', false, 100, true, 'internal'),
    ((SELECT id FROM chains WHERE slug = 'base-mainnet'), 'Base Node 2', 'http://base-node-2.internal:8545', 'http', false, 100, true, 'internal')
ON CONFLICT DO NOTHING;

-- Optimism
INSERT INTO rpc_endpoints (chain_id, name, url, endpoint_type, is_archive, weight, is_active, provider)
VALUES
    ((SELECT id FROM chains WHERE slug = 'op-mainnet'), 'Optimism Node 1', 'http://op-node-1.internal:8545', 'http', false, 100, true, 'internal'),
    ((SELECT id FROM chains WHERE slug = 'op-mainnet'), 'Optimism Node 2', 'http://op-node-2.internal:8545', 'http', false, 100, true, 'internal')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- Verify seed data
-- ============================================================================

-- Count organizations
SELECT 'Organizations created:' as info, COUNT(*) as count FROM organizations;

-- Count users
SELECT 'Users created:' as info, COUNT(*) as count FROM users;

-- Count subscriptions
SELECT 'Subscriptions created:' as info, COUNT(*) as count FROM subscriptions;

-- Count consumers
SELECT 'Consumers created:' as info, COUNT(*) as count FROM consumers;

-- Count API keys
SELECT 'API keys created:' as info, COUNT(*) as count FROM api_keys;

-- Count chains
SELECT 'Chains available:' as info, COUNT(*) as count FROM chains WHERE is_active = true;

-- Count endpoints
SELECT 'RPC endpoints:' as info, COUNT(*) as count FROM rpc_endpoints WHERE is_active = true;

-- Show subscription details
SELECT
    o.name as organization,
    p.name as plan,
    s.status,
    s.current_period_end
FROM subscriptions s
JOIN organizations o ON s.organization_id = o.id
JOIN plans p ON s.plan_id = p.id
ORDER BY o.name;
