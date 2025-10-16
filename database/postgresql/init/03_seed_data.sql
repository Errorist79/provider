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
    ('c2ggde11-be2d-6gga-dd8f-8dd1de5a2c33', 'Gamma DAO', 'gamma-dao', 'dao@gamma.example.com', 'active')
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- Create test users
-- ============================================================================
INSERT INTO users (id, organization_id, email, name, role, status)
VALUES
    ('d3hhef22-cf3e-7hhb-ee9g-9ee2ef6b3d44', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'alice@acme.example.com', 'Alice Admin', 'owner', 'active'),
    ('e4iifg33-dg4f-8iic-ff0h-0ff3fg7c4e55', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'bob@acme.example.com', 'Bob Builder', 'admin', 'active'),
    ('f5jjgh44-eh5g-9jjd-gg1i-1gg4gh8d5f66', 'b1ffcd00-ad1c-5ff9-cc7e-7cc0cd491b22', 'charlie@betalabs.example.com', 'Charlie Coder', 'owner', 'active')
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
        'g6kkih55-fi6h-0kkd-hh2j-2hh5hi9e6g77',
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        (SELECT id FROM plans WHERE slug = 'pro'),
        'active',
        'monthly',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP + INTERVAL '30 days'
    ),
    -- Beta Labs on Basic plan
    (
        'h7llji66-gj7i-1lld-ii3k-3ii6ij0f7h88',
        'b1ffcd00-ad1c-5ff9-cc7e-7cc0cd491b22',
        (SELECT id FROM plans WHERE slug = 'basic'),
        'active',
        'monthly',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP + INTERVAL '30 days'
    ),
    -- Gamma DAO on Free plan
    (
        'i8mmkj77-hk8j-2mmd-jj4l-4jj7jk1g8i99',
        'c2ggde11-be2d-6gga-dd8f-8dd1de5a2c33',
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
        'j9nnlk88-il9k-3nnd-kk5m-5kk8kl2h9j00',
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        'kong_acme_001',
        'unkey_acme_identity_001',
        'active'
    ),
    (
        'k0ooml99-jm0l-4ood-ll6n-6ll9lm3i0k11',
        'b1ffcd00-ad1c-5ff9-cc7e-7cc0cd491b22',
        'kong_beta_001',
        'unkey_beta_identity_001',
        'active'
    ),
    (
        'l1ppnm00-kn1m-5ppd-mm7o-7mm0mn4j1l22',
        'c2ggde11-be2d-6gga-dd8f-8dd1de5a2c33',
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
        'm2qqon11-lo2n-6qqd-nn8p-8nn1no5k2m33',
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        'j9nnlk88-il9k-3nnd-kk5m-5kk8kl2h9j00',
        'unkey_key_acme_prod_001',
        'sk_prod_acme',
        'Acme Production Key',
        'Main production API key for Acme Corp',
        'active',
        '["*"]'
    ),
    (
        'n3rrop22-mp3o-7rrd-oo9q-9oo2op6l3n44',
        'b1ffcd00-ad1c-5ff9-cc7e-7cc0cd491b22',
        'k0ooml99-jm0l-4ood-ll6n-6ll9lm3i0k11',
        'unkey_key_beta_dev_001',
        'sk_dev_beta',
        'Beta Dev Key',
        'Development API key for Beta Labs',
        'active',
        '["eth-mainnet", "eth-sepolia", "polygon-mainnet"]'
    ),
    (
        'o4sspq33-nq4p-8ssd-pp0r-0pp3pq7m4o55',
        'c2ggde11-be2d-6gga-dd8f-8dd1de5a2c33',
        'l1ppnm00-kn1m-5ppd-mm7o-7mm0mn4j1l22',
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
