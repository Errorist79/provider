-- ============================================================================
-- Multichain Support - Chains, Networks, and Endpoints
-- ============================================================================

-- ============================================================================
-- Chains (Blockchain types)
-- ============================================================================
CREATE TABLE chains (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    slug VARCHAR(50) NOT NULL UNIQUE,
    chain_type VARCHAR(50) NOT NULL, -- 'evm', 'solana', 'cosmos', etc.

    -- Chain identifiers
    chain_id VARCHAR(50), -- For EVM chains (e.g., '1' for Ethereum mainnet)

    -- Display info
    display_name VARCHAR(100),
    icon_url VARCHAR(500),
    color VARCHAR(7), -- Hex color code

    -- Chain properties
    block_time_seconds INTEGER,
    native_currency JSONB, -- {"symbol": "ETH", "name": "Ether", "decimals": 18}

    -- Features
    supports_websocket BOOLEAN DEFAULT true,
    supports_archive BOOLEAN DEFAULT true,
    supports_trace BOOLEAN DEFAULT false,

    -- Status
    is_active BOOLEAN DEFAULT true,
    is_testnet BOOLEAN DEFAULT false,

    -- Documentation
    documentation_url VARCHAR(500),

    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_chains_slug ON chains(slug);
CREATE INDEX idx_chains_active ON chains(is_active);
CREATE INDEX idx_chains_chain_id ON chains(chain_id);
CREATE INDEX idx_chains_type ON chains(chain_type);

-- Insert major chains
INSERT INTO chains (name, slug, chain_type, chain_id, display_name, is_testnet, native_currency, supports_trace, block_time_seconds) VALUES
-- Ethereum
('Ethereum Mainnet', 'eth-mainnet', 'evm', '1', 'Ethereum', false, '{"symbol": "ETH", "name": "Ether", "decimals": 18}', true, 12),
('Ethereum Sepolia', 'eth-sepolia', 'evm', '11155111', 'Sepolia', true, '{"symbol": "ETH", "name": "Sepolia Ether", "decimals": 18}', true, 12),
('Ethereum Holesky', 'eth-holesky', 'evm', '17000', 'Holesky', true, '{"symbol": "ETH", "name": "Holesky Ether", "decimals": 18}', false, 12),

-- Layer 2s
('Arbitrum One', 'arb-mainnet', 'evm', '42161', 'Arbitrum', false, '{"symbol": "ETH", "name": "Ether", "decimals": 18}', true, 1),
('Arbitrum Sepolia', 'arb-sepolia', 'evm', '421614', 'Arbitrum Sepolia', true, '{"symbol": "ETH", "name": "Sepolia Ether", "decimals": 18}', false, 1),
('Optimism', 'op-mainnet', 'evm', '10', 'Optimism', false, '{"symbol": "ETH", "name": "Ether", "decimals": 18}', true, 2),
('Optimism Sepolia', 'op-sepolia', 'evm', '11155420', 'OP Sepolia', true, '{"symbol": "ETH", "name": "Sepolia Ether", "decimals": 18}', false, 2),
('Base', 'base-mainnet', 'evm', '8453', 'Base', false, '{"symbol": "ETH", "name": "Ether", "decimals": 18}', true, 2),
('Base Sepolia', 'base-sepolia', 'evm', '84532', 'Base Sepolia', true, '{"symbol": "ETH", "name": "Sepolia Ether", "decimals": 18}', false, 2),

-- Polygon
('Polygon', 'polygon-mainnet', 'evm', '137', 'Polygon', false, '{"symbol": "MATIC", "name": "MATIC", "decimals": 18}', true, 2),
('Polygon Amoy', 'polygon-amoy', 'evm', '80002', 'Polygon Amoy', true, '{"symbol": "MATIC", "name": "MATIC", "decimals": 18}', false, 2),
('Polygon zkEVM', 'polygon-zkevm', 'evm', '1101', 'Polygon zkEVM', false, '{"symbol": "ETH", "name": "Ether", "decimals": 18}', false, 1),

-- BSC
('BNB Smart Chain', 'bsc-mainnet', 'evm', '56', 'BSC', false, '{"symbol": "BNB", "name": "BNB", "decimals": 18}', true, 3),
('BNB Testnet', 'bsc-testnet', 'evm', '97', 'BSC Testnet', true, '{"symbol": "tBNB", "name": "Test BNB", "decimals": 18}', false, 3),

-- Avalanche
('Avalanche C-Chain', 'avax-mainnet', 'evm', '43114', 'Avalanche', false, '{"symbol": "AVAX", "name": "AVAX", "decimals": 18}', true, 2),
('Avalanche Fuji', 'avax-fuji', 'evm', '43113', 'Avalanche Fuji', true, '{"symbol": "AVAX", "name": "AVAX", "decimals": 18}', false, 2),

-- Other EVMs
('Fantom', 'ftm-mainnet', 'evm', '250', 'Fantom', false, '{"symbol": "FTM", "name": "FTM", "decimals": 18}', true, 1),
('Gnosis Chain', 'gnosis-mainnet', 'evm', '100', 'Gnosis', false, '{"symbol": "xDAI", "name": "xDAI", "decimals": 18}', true, 5),
('Celo', 'celo-mainnet', 'evm', '42220', 'Celo', false, '{"symbol": "CELO", "name": "CELO", "decimals": 18}', false, 5),

-- Non-EVM (placeholders for future)
('Solana Mainnet', 'sol-mainnet', 'solana', NULL, 'Solana', false, '{"symbol": "SOL", "name": "SOL", "decimals": 9}', false, 0),
('Solana Devnet', 'sol-devnet', 'solana', NULL, 'Solana Devnet', true, '{"symbol": "SOL", "name": "SOL", "decimals": 9}', false, 0);

-- ============================================================================
-- RPC Endpoints (upstream nodes)
-- ============================================================================
CREATE TABLE rpc_endpoints (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_id UUID NOT NULL REFERENCES chains(id) ON DELETE CASCADE,

    name VARCHAR(255) NOT NULL,

    -- Endpoint details
    url VARCHAR(500) NOT NULL,
    endpoint_type VARCHAR(50) NOT NULL CHECK (endpoint_type IN ('http', 'https', 'ws', 'wss')),

    -- Archive node?
    is_archive BOOLEAN DEFAULT false,
    supports_trace BOOLEAN DEFAULT false,

    -- Load balancing
    weight INTEGER DEFAULT 100 CHECK (weight >= 0 AND weight <= 1000),
    priority INTEGER DEFAULT 100, -- Lower = higher priority

    -- Health
    is_healthy BOOLEAN DEFAULT true,
    last_health_check TIMESTAMP WITH TIME ZONE,
    health_check_failures INTEGER DEFAULT 0,

    -- Performance
    avg_latency_ms INTEGER,

    -- Status
    is_active BOOLEAN DEFAULT true,

    -- Provider info (if using third-party)
    provider VARCHAR(100), -- 'internal', 'alchemy', 'infura', 'quicknode', etc.

    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_rpc_endpoints_chain ON rpc_endpoints(chain_id);
CREATE INDEX idx_rpc_endpoints_active ON rpc_endpoints(is_active);
CREATE INDEX idx_rpc_endpoints_healthy ON rpc_endpoints(is_healthy);
CREATE INDEX idx_rpc_endpoints_type ON rpc_endpoints(endpoint_type);

-- ============================================================================
-- Plans already have chain access columns (defined in 01_schema.sql)
-- ============================================================================
-- No ALTER TABLE needed - columns exist in base schema

-- ============================================================================
-- Chain-specific rate limits (per plan per chain)
-- ============================================================================
CREATE TABLE plan_chain_limits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    plan_id UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
    chain_id UUID NOT NULL REFERENCES chains(id) ON DELETE CASCADE,

    -- Rate limits
    rate_limit_per_second INTEGER,
    rate_limit_per_minute INTEGER,
    rate_limit_per_hour INTEGER,
    rate_limit_per_day INTEGER,

    -- Compute units (for expensive methods)
    compute_units_per_second INTEGER,
    compute_units_per_day INTEGER,

    -- Override default plan limits for specific chains
    is_override BOOLEAN DEFAULT false,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(plan_id, chain_id)
);

CREATE INDEX idx_plan_chain_limits_plan ON plan_chain_limits(plan_id);
CREATE INDEX idx_plan_chain_limits_chain ON plan_chain_limits(chain_id);

-- ============================================================================
-- Method-specific compute units (for expensive operations)
-- ============================================================================
CREATE TABLE method_compute_units (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_type VARCHAR(50) NOT NULL, -- 'evm', 'solana', etc.
    method_name VARCHAR(100) NOT NULL,

    compute_units INTEGER NOT NULL DEFAULT 1,

    -- Method properties
    is_expensive BOOLEAN DEFAULT false,
    requires_archive BOOLEAN DEFAULT false,
    requires_trace BOOLEAN DEFAULT false,

    description TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(chain_type, method_name)
);

CREATE INDEX idx_method_compute_units_type ON method_compute_units(chain_type);
CREATE INDEX idx_method_compute_units_expensive ON method_compute_units(is_expensive);

-- Insert common EVM methods with compute units
INSERT INTO method_compute_units (chain_type, method_name, compute_units, is_expensive, requires_archive, requires_trace) VALUES
-- Standard methods (1 CU)
('evm', 'eth_blockNumber', 1, false, false, false),
('evm', 'eth_chainId', 1, false, false, false),
('evm', 'eth_gasPrice', 1, false, false, false),
('evm', 'eth_getBalance', 1, false, false, false),
('evm', 'eth_getCode', 1, false, false, false),
('evm', 'eth_getTransactionCount', 1, false, false, false),
('evm', 'eth_call', 2, false, false, false),
('evm', 'eth_estimateGas', 2, false, false, false),
('evm', 'eth_sendRawTransaction', 2, false, false, false),

-- Block methods
('evm', 'eth_getBlockByNumber', 3, false, false, false),
('evm', 'eth_getBlockByHash', 3, false, false, false),
('evm', 'eth_getBlockTransactionCountByNumber', 2, false, false, false),

-- Transaction methods
('evm', 'eth_getTransactionByHash', 2, false, false, false),
('evm', 'eth_getTransactionReceipt', 2, false, false, false),

-- Log/Filter methods (can be expensive)
('evm', 'eth_getLogs', 10, true, false, false),
('evm', 'eth_newFilter', 5, false, false, false),
('evm', 'eth_getFilterLogs', 10, true, false, false),

-- Archive methods
('evm', 'eth_getStorageAt', 5, false, true, false),
('evm', 'eth_getBalance_historical', 5, false, true, false),

-- Trace methods (very expensive)
('evm', 'debug_traceTransaction', 50, true, true, true),
('evm', 'debug_traceBlockByNumber', 100, true, true, true),
('evm', 'debug_traceBlockByHash', 100, true, true, true),
('evm', 'trace_transaction', 50, true, true, true),
('evm', 'trace_block', 100, true, true, true),
('evm', 'trace_filter', 100, true, true, true);

-- ============================================================================
-- API Keys already have chain access columns (defined in 01_schema.sql)
-- ============================================================================
-- No ALTER TABLE needed - columns exist in base schema

-- ============================================================================
-- Views for chain-aware queries
-- ============================================================================

-- Active chains with endpoint counts
CREATE OR REPLACE VIEW v_chains_status AS
SELECT
    c.*,
    COUNT(e.id) as endpoint_count,
    COUNT(e.id) FILTER (WHERE e.is_active AND e.is_healthy) as healthy_endpoint_count,
    AVG(e.avg_latency_ms) as avg_latency_ms
FROM chains c
LEFT JOIN rpc_endpoints e ON c.id = e.chain_id
WHERE c.is_active = true
GROUP BY c.id;

-- Plan capabilities by chain
CREATE OR REPLACE VIEW v_plan_chain_access AS
SELECT
    p.id as plan_id,
    p.slug as plan_slug,
    c.id as chain_id,
    c.slug as chain_slug,
    CASE
        WHEN p.allowed_chains = '["*"]'::jsonb THEN true
        WHEN p.allowed_chains ? c.slug THEN true
        ELSE false
    END as has_access,
    COALESCE(pcl.rate_limit_per_minute, p.rate_limit_per_minute) as rate_limit_per_minute,
    p.archive_access,
    p.trace_access,
    p.websocket_access
FROM plans p
CROSS JOIN chains c
LEFT JOIN plan_chain_limits pcl ON p.id = pcl.plan_id AND c.id = pcl.chain_id
WHERE p.is_active = true AND c.is_active = true;

-- Consumer chain access (via subscription)
CREATE OR REPLACE VIEW v_consumer_chain_access AS
SELECT
    c.id as consumer_id,
    c.unkey_identity_id,
    s.plan_id,
    p.slug as plan_slug,
    ch.id as chain_id,
    ch.slug as chain_slug,
    ch.chain_type,
    pca.has_access,
    pca.rate_limit_per_minute,
    pca.archive_access,
    pca.trace_access,
    pca.websocket_access
FROM consumers c
JOIN subscriptions s ON c.organization_id = s.organization_id
JOIN plans p ON s.plan_id = p.id
CROSS JOIN chains ch
LEFT JOIN v_plan_chain_access pca ON p.id = pca.plan_id AND ch.id = pca.chain_id
WHERE s.status = 'active'
  AND ch.is_active = true;

-- ============================================================================
-- Triggers
-- ============================================================================
CREATE TRIGGER update_chains_updated_at BEFORE UPDATE ON chains FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_rpc_endpoints_updated_at BEFORE UPDATE ON rpc_endpoints FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_plan_chain_limits_updated_at BEFORE UPDATE ON plan_chain_limits FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_method_compute_units_updated_at BEFORE UPDATE ON method_compute_units FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE chains IS 'Supported blockchain networks (Ethereum, Arbitrum, Polygon, etc.)';
COMMENT ON TABLE rpc_endpoints IS 'RPC node endpoints for each chain with health and load balancing';
COMMENT ON TABLE plan_chain_limits IS 'Chain-specific rate limits per plan';
COMMENT ON TABLE method_compute_units IS 'Compute unit weights for RPC methods';
