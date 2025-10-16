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
    timestamp DateTime64(3) CODEC(DoubleDelta, LZ4),
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

    -- Error tracking
    error_message String CODEC(ZSTD(1)),
    is_error UInt8 CODEC(T64, LZ4),

    -- Metadata
    metadata String CODEC(ZSTD(1))  -- JSON string
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (timestamp, organization_id, consumer_id, status_code)
TTL timestamp + INTERVAL 14 DAY  -- Keep raw data for 14 days
SETTINGS index_granularity = 8192;

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_consumer ON requests_raw (consumer_id) TYPE bloom_filter(0.01);
CREATE INDEX IF NOT EXISTS idx_org ON requests_raw (organization_id) TYPE bloom_filter(0.01);
CREATE INDEX IF NOT EXISTS idx_error ON requests_raw (is_error) TYPE set(2);
CREATE INDEX IF NOT EXISTS idx_status ON requests_raw (status_code) TYPE set(100);

-- ============================================================================
-- Hourly Usage Aggregation (Medium retention)
-- ============================================================================
CREATE TABLE IF NOT EXISTS usage_hourly (
    hour DateTime CODEC(DoubleDelta, LZ4),

    -- Dimensions
    organization_id String CODEC(ZSTD(1)),
    consumer_id String CODEC(ZSTD(1)),
    plan_slug String CODEC(ZSTD(1)),
    route_name String CODEC(ZSTD(1)),
    rpc_method String CODEC(ZSTD(1)),

    -- Metrics
    request_count UInt64 CODEC(T64, LZ4),
    error_count UInt64 CODEC(T64, LZ4),

    -- Success by status code
    status_2xx_count UInt64 CODEC(T64, LZ4),
    status_4xx_count UInt64 CODEC(T64, LZ4),
    status_5xx_count UInt64 CODEC(T64, LZ4),

    -- Bandwidth
    total_response_size UInt64 CODEC(T64, LZ4),

    -- Latency percentiles (in ms)
    latency_p50 Float32 CODEC(T64, LZ4),
    latency_p95 Float32 CODEC(T64, LZ4),
    latency_p99 Float32 CODEC(T64, LZ4),
    latency_max Float32 CODEC(T64, LZ4),

    -- Upstream latency percentiles
    upstream_latency_p50 Float32 CODEC(T64, LZ4),
    upstream_latency_p95 Float32 CODEC(T64, LZ4),
    upstream_latency_p99 Float32 CODEC(T64, LZ4)
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (hour, organization_id, consumer_id, plan_slug, route_name, rpc_method)
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
    plan_slug,
    route_name,
    rpc_method,

    count() as request_count,
    countIf(is_error = 1) as error_count,

    countIf(status_code >= 200 AND status_code < 300) as status_2xx_count,
    countIf(status_code >= 400 AND status_code < 500) as status_4xx_count,
    countIf(status_code >= 500) as status_5xx_count,

    sum(response_size) as total_response_size,

    quantile(0.50)(latency_ms) as latency_p50,
    quantile(0.95)(latency_ms) as latency_p95,
    quantile(0.99)(latency_ms) as latency_p99,
    max(latency_ms) as latency_max,

    quantile(0.50)(upstream_latency_ms) as upstream_latency_p50,
    quantile(0.95)(upstream_latency_ms) as upstream_latency_p95,
    quantile(0.99)(upstream_latency_ms) as upstream_latency_p99
FROM requests_raw
GROUP BY
    hour,
    organization_id,
    consumer_id,
    plan_slug,
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
    plan_slug String CODEC(ZSTD(1)),

    -- Metrics
    request_count UInt64 CODEC(T64, LZ4),
    error_count UInt64 CODEC(T64, LZ4),

    status_2xx_count UInt64 CODEC(T64, LZ4),
    status_4xx_count UInt64 CODEC(T64, LZ4),
    status_5xx_count UInt64 CODEC(T64, LZ4),

    total_response_size UInt64 CODEC(T64, LZ4),

    -- Latency
    avg_latency_ms Float32 CODEC(T64, LZ4),
    max_latency_ms Float32 CODEC(T64, LZ4),

    -- Uptime/reliability
    success_rate Float32 CODEC(T64, LZ4),
    error_rate Float32 CODEC(T64, LZ4)
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (date, organization_id, consumer_id, plan_slug)
TTL date + INTERVAL 540 DAY  -- Keep daily data for 18 months
SETTINGS index_granularity = 8192;

-- Materialized view to populate usage_daily from usage_hourly
CREATE MATERIALIZED VIEW IF NOT EXISTS usage_daily_mv
TO usage_daily
AS
SELECT
    toDate(hour) as date,
    organization_id,
    consumer_id,
    plan_slug,

    sum(request_count) as request_count,
    sum(error_count) as error_count,

    sum(status_2xx_count) as status_2xx_count,
    sum(status_4xx_count) as status_4xx_count,
    sum(status_5xx_count) as status_5xx_count,

    sum(total_response_size) as total_response_size,

    avg(latency_p50) as avg_latency_ms,
    max(latency_max) as max_latency_ms,

    sum(status_2xx_count) / sum(request_count) * 100 as success_rate,
    sum(error_count) / sum(request_count) * 100 as error_rate
FROM usage_hourly
GROUP BY
    date,
    organization_id,
    consumer_id,
    plan_slug;

-- ============================================================================
-- Error Tracking (Detailed error logs)
-- ============================================================================
CREATE TABLE IF NOT EXISTS errors (
    timestamp DateTime64(3) CODEC(DoubleDelta, LZ4),
    request_id String CODEC(ZSTD(1)),

    -- Context
    organization_id String CODEC(ZSTD(1)),
    consumer_id String CODEC(ZSTD(1)),

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
    p50 Float32 CODEC(T64, LZ4),
    p95 Float32 CODEC(T64, LZ4),
    p99 Float32 CODEC(T64, LZ4),
    p999 Float32 CODEC(T64, LZ4)
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
    timestamp DateTime64(3) CODEC(DoubleDelta, LZ4),

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
