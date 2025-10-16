-- ============================================================================
-- Chain-Specific Analytics Tables
-- ============================================================================

USE telemetry;

-- ============================================================================
-- Chain Health Metrics (for monitoring upstreams)
-- ============================================================================
CREATE TABLE IF NOT EXISTS chain_health (
    timestamp DateTime CODEC(DoubleDelta, LZ4),

    chain_slug String CODEC(ZSTD(1)),
    upstream_host String CODEC(ZSTD(1)),

    -- Health status
    is_healthy UInt8 CODEC(T64, LZ4),
    health_check_failures UInt32 CODEC(T64, LZ4),

    -- Performance
    avg_latency_ms Float32 CODEC(T64, LZ4),
    p95_latency_ms Float32 CODEC(T64, LZ4),
    p99_latency_ms Float32 CODEC(T64, LZ4),

    -- Request metrics
    request_count UInt64 CODEC(T64, LZ4),
    error_count UInt64 CODEC(T64, LZ4),
    error_rate Float32 CODEC(T64, LZ4),

    -- Block height (for sync status monitoring)
    latest_block UInt64 CODEC(T64, LZ4),

    metadata String CODEC(ZSTD(1))
)
ENGINE = ReplacingMergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (timestamp, chain_slug, upstream_host)
TTL timestamp + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- Materialized view to track chain health from requests
CREATE MATERIALIZED VIEW IF NOT EXISTS chain_health_mv
TO chain_health
AS
SELECT
    toStartOfMinute(timestamp) as timestamp,
    chain_slug,
    upstream_host,

    countIf(status_code < 500) > 0 as is_healthy,
    countIf(status_code >= 500) as health_check_failures,

    avg(latency_ms) as avg_latency_ms,
    quantile(0.95)(latency_ms) as p95_latency_ms,
    quantile(0.99)(latency_ms) as p99_latency_ms,

    count() as request_count,
    countIf(is_error = 1) as error_count,
    countIf(is_error = 1) / count() * 100 as error_rate,

    0 as latest_block, -- Will be updated via separate health check process

    '' as metadata
FROM requests_raw
GROUP BY timestamp, chain_slug, upstream_host;

-- ============================================================================
-- Method Usage by Chain (for analytics)
-- ============================================================================
CREATE TABLE IF NOT EXISTS chain_method_usage (
    date Date CODEC(DoubleDelta, LZ4),

    chain_slug String CODEC(ZSTD(1)),
    rpc_method String CODEC(ZSTD(1)),

    -- Usage metrics
    request_count UInt64 CODEC(T64, LZ4),
    unique_consumers UInt64 CODEC(T64, LZ4),
    unique_organizations UInt64 CODEC(T64, LZ4),

    -- Compute units
    total_compute_units UInt64 CODEC(T64, LZ4),
    avg_compute_units Float32 CODEC(T64, LZ4),

    -- Performance
    avg_latency_ms Float32 CODEC(T64, LZ4),
    p95_latency_ms Float32 CODEC(T64, LZ4),

    -- Error rate
    error_count UInt64 CODEC(T64, LZ4),
    error_rate Float32 CODEC(T64, LZ4)
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (date, chain_slug, rpc_method)
TTL date + INTERVAL 180 DAY
SETTINGS index_granularity = 8192;

-- Materialized view for method usage
CREATE MATERIALIZED VIEW IF NOT EXISTS chain_method_usage_mv
TO chain_method_usage
AS
SELECT
    toDate(timestamp) as date,
    chain_slug,
    rpc_method,

    count() as request_count,
    uniq(consumer_id) as unique_consumers,
    uniq(organization_id) as unique_organizations,

    sum(compute_units) as total_compute_units,
    avg(compute_units) as avg_compute_units,

    avg(latency_ms) as avg_latency_ms,
    quantile(0.95)(latency_ms) as p95_latency_ms,

    countIf(is_error = 1) as error_count,
    countIf(is_error = 1) / count() * 100 as error_rate
FROM requests_raw
GROUP BY date, chain_slug, rpc_method;

-- ============================================================================
-- Chain Usage by Organization (for billing insights)
-- ============================================================================
CREATE TABLE IF NOT EXISTS chain_org_usage (
    date Date CODEC(DoubleDelta, LZ4),

    organization_id String CODEC(ZSTD(1)),
    chain_slug String CODEC(ZSTD(1)),
    plan_slug String CODEC(ZSTD(1)),

    -- Request metrics
    request_count UInt64 CODEC(T64, LZ4),
    compute_units_used UInt64 CODEC(T64, LZ4),

    -- Bandwidth
    total_response_size UInt64 CODEC(T64, LZ4),

    -- Cost estimation (will be calculated based on pricing)
    estimated_cost Float32 CODEC(T64, LZ4)
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (date, organization_id, chain_slug)
TTL date + INTERVAL 540 DAY  -- 18 months for billing
SETTINGS index_granularity = 8192;

-- Materialized view for org usage by chain
CREATE MATERIALIZED VIEW IF NOT EXISTS chain_org_usage_mv
TO chain_org_usage
AS
SELECT
    toDate(timestamp) as date,
    organization_id,
    chain_slug,
    plan_slug,

    count() as request_count,
    sum(compute_units) as compute_units_used,
    sum(response_size) as total_response_size,

    0 as estimated_cost  -- Will be calculated in application layer
FROM requests_raw
GROUP BY date, organization_id, chain_slug, plan_slug;

-- ============================================================================
-- Popular Chains Dashboard Data
-- ============================================================================
CREATE TABLE IF NOT EXISTS chain_popularity (
    hour DateTime CODEC(DoubleDelta, LZ4),

    chain_slug String CODEC(ZSTD(1)),

    -- Usage
    request_count UInt64 CODEC(T64, LZ4),
    unique_users UInt64 CODEC(T64, LZ4),

    -- Performance
    avg_latency_ms Float32 CODEC(T64, LZ4),
    success_rate Float32 CODEC(T64, LZ4)
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (hour, chain_slug)
TTL hour + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- Materialized view for chain popularity
CREATE MATERIALIZED VIEW IF NOT EXISTS chain_popularity_mv
TO chain_popularity
AS
SELECT
    toStartOfHour(timestamp) as hour,
    chain_slug,

    count() as request_count,
    uniq(consumer_id) as unique_users,

    avg(latency_ms) as avg_latency_ms,
    countIf(status_code >= 200 AND status_code < 300) / count() * 100 as success_rate
FROM requests_raw
GROUP BY hour, chain_slug;

-- ============================================================================
-- Expensive Method Tracking (for abuse prevention)
-- ============================================================================
CREATE TABLE IF NOT EXISTS expensive_method_usage (
    timestamp DateTime CODEC(DoubleDelta, LZ4),

    consumer_id String CODEC(ZSTD(1)),
    organization_id String CODEC(ZSTD(1)),
    chain_slug String CODEC(ZSTD(1)),
    rpc_method String CODEC(ZSTD(1)),

    compute_units UInt32 CODEC(T64, LZ4),
    latency_ms UInt32 CODEC(T64, LZ4),

    -- Method properties
    requires_archive UInt8 CODEC(T64, LZ4),
    requires_trace UInt8 CODEC(T64, LZ4),

    status_code UInt16 CODEC(T64, LZ4)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (timestamp, consumer_id, chain_slug, rpc_method)
TTL timestamp + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;

-- Materialized view for expensive methods only
CREATE MATERIALIZED VIEW IF NOT EXISTS expensive_method_usage_mv
TO expensive_method_usage
AS
SELECT
    timestamp,
    consumer_id,
    organization_id,
    chain_slug,
    rpc_method,
    compute_units,
    latency_ms,
    0 as requires_archive,
    0 as requires_trace,
    status_code
FROM requests_raw
WHERE compute_units >= 10;  -- Only track methods with 10+ CU

-- ============================================================================
-- Useful Queries for Multichain Analytics
-- ============================================================================

-- Top chains by request volume (last 24 hours)
-- SELECT
--     chain_slug,
--     sum(request_count) as total_requests,
--     avg(avg_latency_ms) as avg_latency,
--     avg(success_rate) as success_rate_pct
-- FROM chain_popularity
-- WHERE hour >= now() - INTERVAL 24 HOUR
-- GROUP BY chain_slug
-- ORDER BY total_requests DESC;

-- Organization usage breakdown by chain (current month)
-- SELECT
--     organization_id,
--     chain_slug,
--     sum(request_count) as requests,
--     sum(compute_units_used) as cu_used,
--     sum(total_response_size) / 1024 / 1024 as mb_transferred
-- FROM chain_org_usage
-- WHERE date >= toStartOfMonth(today())
-- GROUP BY organization_id, chain_slug
-- ORDER BY requests DESC;

-- Most popular methods by chain (last 7 days)
-- SELECT
--     chain_slug,
--     rpc_method,
--     sum(request_count) as total_requests,
--     avg(avg_latency_ms) as avg_latency,
--     sum(error_count) / sum(request_count) * 100 as error_rate_pct
-- FROM chain_method_usage
-- WHERE date >= today() - INTERVAL 7 DAY
-- GROUP BY chain_slug, rpc_method
-- ORDER BY chain_slug, total_requests DESC;

-- Upstream health status (real-time)
-- SELECT
--     chain_slug,
--     upstream_host,
--     is_healthy,
--     avg_latency_ms,
--     error_rate,
--     request_count
-- FROM chain_health
-- WHERE timestamp >= now() - INTERVAL 5 MINUTE
-- ORDER BY chain_slug, upstream_host;

-- Expensive method abusers (last hour)
-- SELECT
--     consumer_id,
--     organization_id,
--     chain_slug,
--     rpc_method,
--     count() as usage_count,
--     sum(compute_units) as total_cu,
--     avg(latency_ms) as avg_latency
-- FROM expensive_method_usage
-- WHERE timestamp >= now() - INTERVAL 1 HOUR
-- GROUP BY consumer_id, organization_id, chain_slug, rpc_method
-- HAVING usage_count > 100
-- ORDER BY total_cu DESC
-- LIMIT 20;
