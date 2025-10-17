-- ============================================================================
-- RPC Gateway - ClickHouse Schema for Telemetry & Analytics
-- ============================================================================
-- High-volume request logs, usage metrics, and analytics
-- Compatible with OpenTelemetry and SigNoz

-- Use the telemetry database
CREATE DATABASE IF NOT EXISTS telemetry;
USE telemetry;

-- ============================================================================
-- Raw Request Logs (High volume, short retention)
-- ============================================================================
CREATE TABLE IF NOT EXISTS requests_raw (
    timestamp DateTime CODEC(DoubleDelta, LZ4),
    timestamp_ms DateTime64(3) CODEC(DoubleDelta, LZ4),
    request_id String CODEC(ZSTD(1)),

    -- Request metadata
    method String CODEC(ZSTD(1)),
    path String CODEC(ZSTD(1)),
    route_name String CODEC(ZSTD(1)),

    -- Consumer/Organization
    consumer_id String CODEC(ZSTD(1)),
    organization_id String CODEC(ZSTD(1)),
    api_key_prefix String CODEC(ZSTD(1)),
    plan_slug String CODEC(ZSTD(1)),

    -- Chain information (MULTICHAIN SUPPORT)
    chain_slug String CODEC(ZSTD(1)),
    chain_type String CODEC(ZSTD(1)),
    chain_id String CODEC(ZSTD(1)),

    -- Response
    status_code UInt16 CODEC(T64, LZ4),
    response_size UInt32 CODEC(T64, LZ4),

    -- Timing (in milliseconds)
    latency_ms UInt32 CODEC(T64, LZ4),
    upstream_latency_ms UInt32 CODEC(T64, LZ4),
    kong_latency_ms UInt32 CODEC(T64, LZ4),

    -- Upstream
    upstream_host String CODEC(ZSTD(1)),
    upstream_status UInt16 CODEC(T64, LZ4),

    -- Client info
    client_ip String CODEC(ZSTD(1)),
    user_agent String CODEC(ZSTD(1)),

    -- RPC specific (for Ethereum/EVM RPCs)
    rpc_method String CODEC(ZSTD(1)),
    rpc_id String CODEC(ZSTD(1)),
    compute_units UInt32 CODEC(T64, LZ4),

    -- Error tracking
    error_message String CODEC(ZSTD(1)),
    is_error UInt8 CODEC(T64, LZ4),

    -- Metadata
    metadata String CODEC(ZSTD(1))  -- JSON string
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (timestamp, chain_slug, organization_id, consumer_id, status_code)
TTL timestamp + INTERVAL 14 DAY  -- Keep raw data for 14 days
SETTINGS index_granularity = 8192;

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_consumer ON requests_raw (consumer_id) TYPE bloom_filter(0.01);
CREATE INDEX IF NOT EXISTS idx_org ON requests_raw (organization_id) TYPE bloom_filter(0.01);
CREATE INDEX IF NOT EXISTS idx_chain ON requests_raw (chain_slug) TYPE bloom_filter(0.01);
CREATE INDEX IF NOT EXISTS idx_error ON requests_raw (is_error) TYPE set(2);
CREATE INDEX IF NOT EXISTS idx_status ON requests_raw (status_code) TYPE set(100);
CREATE INDEX IF NOT EXISTS idx_rpc_method ON requests_raw (rpc_method) TYPE bloom_filter(0.01);

-- ============================================================================
-- Hourly Usage Aggregation (Medium retention)
-- ============================================================================
CREATE TABLE IF NOT EXISTS usage_hourly (
    hour DateTime CODEC(DoubleDelta, LZ4),

    -- Dimensions
    organization_id String CODEC(ZSTD(1)),
    consumer_id String CODEC(ZSTD(1)),
    api_key_prefix String CODEC(ZSTD(1)),
    plan_slug String CODEC(ZSTD(1)),
    chain_slug String CODEC(ZSTD(1)),
    chain_type String CODEC(ZSTD(1)),
    route_name String CODEC(ZSTD(1)),
    rpc_method String CODEC(ZSTD(1)),

    -- Metric states (finalised via views)
    request_count AggregateFunction(sum, UInt64),
    error_count AggregateFunction(sum, UInt64),
    compute_units_used AggregateFunction(sum, UInt64),

    status_2xx_count AggregateFunction(sum, UInt64),
    status_4xx_count AggregateFunction(sum, UInt64),
    status_5xx_count AggregateFunction(sum, UInt64),

    total_response_size AggregateFunction(sum, UInt64),

    latency_ms_avg AggregateFunction(avg, UInt32),
    latency_ms_quantiles AggregateFunction(quantiles(0.50, 0.95, 0.99), Float32),
    latency_ms_max AggregateFunction(max, UInt32),

    upstream_latency_quantiles AggregateFunction(quantiles(0.50, 0.95, 0.99), Float32)
)
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (hour, chain_slug, organization_id, consumer_id, api_key_prefix, plan_slug, route_name, rpc_method)
TTL hour + INTERVAL 90 DAY  -- Keep hourly data for 90 days
SETTINGS index_granularity = 8192;

-- Materialized view to populate usage_hourly from requests_raw
CREATE MATERIALIZED VIEW IF NOT EXISTS usage_hourly_mv
TO usage_hourly
AS
SELECT
    toStartOfHour(timestamp) as hour,
    organization_id,
    consumer_id,
    api_key_prefix,
    plan_slug,
    chain_slug,
    chain_type,
    route_name,
    rpc_method,

    sumState(toUInt64(1)) as request_count,
    sumState(toUInt64(is_error = 1)) as error_count,
    sumState(toUInt64(compute_units)) as compute_units_used,

    sumState(toUInt64(status_code >= 200 AND status_code < 300)) as status_2xx_count,
    sumState(toUInt64(status_code >= 400 AND status_code < 500)) as status_4xx_count,
    sumState(toUInt64(status_code >= 500)) as status_5xx_count,

    sumState(toUInt64(response_size)) as total_response_size,

    avgState(toUInt32(latency_ms)) as latency_ms_avg,
    quantilesState(0.50, 0.95, 0.99)(toFloat32(latency_ms)) as latency_ms_quantiles,
    maxState(toUInt32(latency_ms)) as latency_ms_max,

    quantilesState(0.50, 0.95, 0.99)(toFloat32(upstream_latency_ms)) as upstream_latency_quantiles
FROM requests_raw
GROUP BY
    hour,
    organization_id,
    consumer_id,
    api_key_prefix,
    plan_slug,
    chain_slug,
    chain_type,
    route_name,
    rpc_method;

-- ============================================================================
-- Daily Usage Aggregation (Long retention for billing)
-- ============================================================================
CREATE TABLE IF NOT EXISTS usage_daily (
    date Date CODEC(DoubleDelta, LZ4),

    -- Dimensions
    organization_id String CODEC(ZSTD(1)),
    consumer_id String CODEC(ZSTD(1)),
    api_key_prefix String CODEC(ZSTD(1)),
    plan_slug String CODEC(ZSTD(1)),
    chain_slug String CODEC(ZSTD(1)),
    chain_type String CODEC(ZSTD(1)),

    -- Metric states (finalised via views)
    request_count AggregateFunction(sum, UInt64),
    error_count AggregateFunction(sum, UInt64),
    compute_units_used AggregateFunction(sum, UInt64),

    status_2xx_count AggregateFunction(sum, UInt64),
    status_4xx_count AggregateFunction(sum, UInt64),
    status_5xx_count AggregateFunction(sum, UInt64),

    total_response_size AggregateFunction(sum, UInt64),

    latency_ms_avg AggregateFunction(avg, UInt32),
    latency_ms_quantiles AggregateFunction(quantiles(0.50, 0.95, 0.99), Float32),
    latency_ms_max AggregateFunction(max, UInt32),

    upstream_latency_quantiles AggregateFunction(quantiles(0.50, 0.95, 0.99), Float32)
)
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (date, chain_slug, organization_id, consumer_id, api_key_prefix, plan_slug)
TTL date + INTERVAL 540 DAY  -- Keep daily data for 18 months
SETTINGS index_granularity = 8192;

-- Materialized view to populate usage_daily from hourly state table
CREATE MATERIALIZED VIEW IF NOT EXISTS usage_daily_mv
TO usage_daily
AS
SELECT
    toDate(hour) as date,
    organization_id,
    consumer_id,
    api_key_prefix,
    plan_slug,
    chain_slug,
    chain_type,

    sumMergeState(request_count) as request_count,
    sumMergeState(error_count) as error_count,
    sumMergeState(compute_units_used) as compute_units_used,

    sumMergeState(status_2xx_count) as status_2xx_count,
    sumMergeState(status_4xx_count) as status_4xx_count,
    sumMergeState(status_5xx_count) as status_5xx_count,

    sumMergeState(total_response_size) as total_response_size,

    avgMergeState(latency_ms_avg) as latency_ms_avg,
    quantilesMergeState(0.50, 0.95, 0.99)(latency_ms_quantiles) as latency_ms_quantiles,
    maxMergeState(latency_ms_max) as latency_ms_max,

    quantilesMergeState(0.50, 0.95, 0.99)(upstream_latency_quantiles) as upstream_latency_quantiles
FROM usage_hourly
GROUP BY
    date,
    organization_id,
    consumer_id,
    api_key_prefix,
    plan_slug,
    chain_slug,
    chain_type;

-- Note: Query from AggregatingMergeTree tables with the pattern below to get final metrics
-- SELECT
--     hour,
--     organization_id,
--     sumMerge(request_count) AS request_count,
--     sumMerge(error_count) AS error_count,
--     sumMerge(status_2xx_count) AS status_2xx_count,
--     avgMerge(latency_ms_avg) AS avg_latency_ms,
--     quantileMerge(0.50)(latency_ms_quantiles) AS latency_p50,
--     quantileMerge(0.95)(latency_ms_quantiles) AS latency_p95,
--     quantileMerge(0.99)(latency_ms_quantiles) AS latency_p99,
--     ...
-- FROM usage_hourly
-- GROUP BY hour, organization_id, ...;

-- Daily rollups follow the same pattern using usage_daily
-- (replacing the GROUP BY list with date, organization_id, ...)

-- ============================================================================
-- Error Tracking (Detailed error logs)
-- ============================================================================
CREATE TABLE IF NOT EXISTS errors (
    timestamp DateTime CODEC(DoubleDelta, LZ4),
    timestamp_ms DateTime64(3) CODEC(DoubleDelta, LZ4),
    request_id String CODEC(ZSTD(1)),

    -- Context
    organization_id String CODEC(ZSTD(1)),
    consumer_id String CODEC(ZSTD(1)),
    chain_slug String CODEC(ZSTD(1)),

    -- Error details
    error_type String CODEC(ZSTD(1)),
    error_message String CODEC(ZSTD(1)),
    error_stack String CODEC(ZSTD(1)),

    -- Request info
    method String CODEC(ZSTD(1)),
    path String CODEC(ZSTD(1)),
    status_code UInt16 CODEC(T64, LZ4),

    -- RPC specific
    rpc_method String CODEC(ZSTD(1)),

    -- Client
    client_ip String CODEC(ZSTD(1)),

    metadata String CODEC(ZSTD(1))
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (timestamp, organization_id, error_type)
TTL timestamp + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- Materialized view to populate errors from requests_raw
CREATE MATERIALIZED VIEW IF NOT EXISTS errors_mv
TO errors
AS
SELECT
    timestamp,
    request_id,
    organization_id,
    consumer_id,
    'http_error' as error_type,
    error_message,
    '' as error_stack,
    method,
    path,
    status_code,
    rpc_method,
    client_ip,
    metadata
FROM requests_raw
WHERE is_error = 1;

-- ============================================================================
-- Latency Tracking (for SLA monitoring)
-- ============================================================================
CREATE TABLE IF NOT EXISTS latency_metrics (
    timestamp DateTime CODEC(DoubleDelta, LZ4),

    -- Dimensions
    route_name String CODEC(ZSTD(1)),
    upstream_host String CODEC(ZSTD(1)),

    -- Latency buckets (histogram)
    latency_0_10ms UInt32 CODEC(T64, LZ4),
    latency_10_50ms UInt32 CODEC(T64, LZ4),
    latency_50_100ms UInt32 CODEC(T64, LZ4),
    latency_100_500ms UInt32 CODEC(T64, LZ4),
    latency_500_1000ms UInt32 CODEC(T64, LZ4),
    latency_1000ms_plus UInt32 CODEC(T64, LZ4),

    -- Percentiles
    p50 Float32 CODEC(LZ4),
    p95 Float32 CODEC(LZ4),
    p99 Float32 CODEC(LZ4),
    p999 Float32 CODEC(LZ4)
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (timestamp, route_name, upstream_host)
TTL timestamp + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- Materialized view to populate latency_metrics from requests_raw
CREATE MATERIALIZED VIEW IF NOT EXISTS latency_metrics_mv
TO latency_metrics
AS
SELECT
    toStartOfMinute(timestamp) as timestamp,
    route_name,
    upstream_host,

    countIf(latency_ms < 10) as latency_0_10ms,
    countIf(latency_ms >= 10 AND latency_ms < 50) as latency_10_50ms,
    countIf(latency_ms >= 50 AND latency_ms < 100) as latency_50_100ms,
    countIf(latency_ms >= 100 AND latency_ms < 500) as latency_100_500ms,
    countIf(latency_ms >= 500 AND latency_ms < 1000) as latency_500_1000ms,
    countIf(latency_ms >= 1000) as latency_1000ms_plus,

    quantile(0.50)(latency_ms) as p50,
    quantile(0.95)(latency_ms) as p95,
    quantile(0.99)(latency_ms) as p99,
    quantile(0.999)(latency_ms) as p999
FROM requests_raw
GROUP BY timestamp, route_name, upstream_host;

-- ============================================================================
-- Rate Limit Events
-- ============================================================================
CREATE TABLE IF NOT EXISTS rate_limit_events (
    timestamp DateTime CODEC(DoubleDelta, LZ4),
    timestamp_ms DateTime64(3) CODEC(DoubleDelta, LZ4),

    -- Consumer
    organization_id String CODEC(ZSTD(1)),
    consumer_id String CODEC(ZSTD(1)),
    plan_slug String CODEC(ZSTD(1)),

    -- Limit info
    limit_type String CODEC(ZSTD(1)),  -- 'second', 'minute', 'hour', 'day'
    limit_value UInt32 CODEC(T64, LZ4),
    current_count UInt32 CODEC(T64, LZ4),

    -- Client
    client_ip String CODEC(ZSTD(1)),

    metadata String CODEC(ZSTD(1))
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (timestamp, organization_id, consumer_id)
TTL timestamp + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- ============================================================================
-- Useful queries for dashboards and analytics
-- ============================================================================

-- Top consumers by request count (last 24 hours)
-- SELECT
--     organization_id,
--     consumer_id,
--     sum(request_count) as total_requests
-- FROM usage_hourly
-- WHERE hour >= now() - INTERVAL 24 HOUR
-- GROUP BY organization_id, consumer_id
-- ORDER BY total_requests DESC
-- LIMIT 10;

-- Error rate by organization (last 7 days)
-- SELECT
--     date,
--     organization_id,
--     sum(error_count) / sum(request_count) * 100 as error_rate_pct
-- FROM usage_daily
-- WHERE date >= today() - INTERVAL 7 DAY
-- GROUP BY date, organization_id
-- ORDER BY date DESC, error_rate_pct DESC;

-- Latency percentiles over time (last hour)
-- SELECT
--     timestamp,
--     route_name,
--     p50,
--     p95,
--     p99
-- FROM latency_metrics
-- WHERE timestamp >= now() - INTERVAL 1 HOUR
-- ORDER BY timestamp DESC;

-- Usage by plan for billing (current month)
-- SELECT
--     organization_id,
--     plan_slug,
--     sum(request_count) as total_requests,
--     sum(total_response_size) / 1024 / 1024 / 1024 as total_gb
-- FROM usage_daily
-- WHERE date >= toStartOfMonth(today())
-- GROUP BY organization_id, plan_slug
-- ORDER BY total_requests DESC;
