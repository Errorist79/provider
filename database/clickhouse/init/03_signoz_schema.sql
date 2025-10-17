-- ============================================================================
-- SigNoz Schema in ClickHouse
-- ============================================================================
-- Creates databases and tables for SigNoz traces and metrics

-- Traces database
CREATE DATABASE IF NOT EXISTS signoz_traces;

-- Metrics database
CREATE DATABASE IF NOT EXISTS signoz_metrics;

-- Logs database
CREATE DATABASE IF NOT EXISTS signoz_logs;

-- Use traces database for trace tables
USE signoz_traces;

-- Distributed tracing index table
CREATE TABLE IF NOT EXISTS signoz_index_v2 (
    timestamp DateTime64(9) CODEC(DoubleDelta, LZ4),
    traceID String CODEC(ZSTD(1)),
    spanID String CODEC(ZSTD(1)),
    parentSpanID String CODEC(ZSTD(1)),
    serviceName LowCardinality(String) CODEC(ZSTD(1)),
    name LowCardinality(String) CODEC(ZSTD(1)),
    kind Int8 CODEC(T64, LZ4),
    durationNano UInt64 CODEC(T64, LZ4),
    statusCode Int16 CODEC(T64, LZ4),

    -- Custom RPC attributes
    rpcMethod LowCardinality(String) CODEC(ZSTD(1)),
    rpcChain LowCardinality(String) CODEC(ZSTD(1)),
    rpcPlan LowCardinality(String) CODEC(ZSTD(1)),
    rpcOrganizationId String CODEC(ZSTD(1)),
    rpcComputeUnits UInt32 CODEC(T64, LZ4),

    -- Resource attributes
    resourceAttributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),

    -- HTTP attributes
    httpMethod LowCardinality(String) CODEC(ZSTD(1)),
    httpUrl String CODEC(ZSTD(1)),
    httpStatusCode UInt16 CODEC(T64, LZ4),

    INDEX idx_trace_id traceID TYPE bloom_filter(0.001) GRANULARITY 1,
    INDEX idx_duration durationNano TYPE minmax GRANULARITY 1,
    INDEX idx_rpc_method rpcMethod TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_rpc_chain rpcChain TYPE bloom_filter(0.01) GRANULARITY 1
) ENGINE = MergeTree()
PARTITION BY toDate(timestamp)
ORDER BY (serviceName, timestamp)
TTL toDateTime(timestamp) + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;

-- ============================================================================
-- Useful queries for RPC observability
-- ============================================================================

-- Trace requests by chain (last hour)
-- SELECT
--     rpcChain,
--     count() as trace_count,
--     avg(durationNano) / 1000000 as avg_duration_ms,
--     quantile(0.95)(durationNano) / 1000000 as p95_duration_ms
-- FROM signoz_index_v2
-- WHERE timestamp >= now() - INTERVAL 1 HOUR
-- GROUP BY rpcChain
-- ORDER BY trace_count DESC;

-- Expensive methods performance
-- SELECT
--     rpcMethod,
--     rpcChain,
--     count() as count,
--     avg(durationNano) / 1000000 as avg_ms,
--     max(durationNano) / 1000000 as max_ms,
--     sum(rpcComputeUnits) as total_cu
-- FROM signoz_index_v2
-- WHERE timestamp >= now() - INTERVAL 1 HOUR
--   AND rpcComputeUnits >= 10
-- GROUP BY rpcMethod, rpcChain
-- ORDER BY total_cu DESC;

-- Error traces
-- SELECT
--     timestamp,
--     rpcChain,
--     rpcMethod,
--     httpStatusCode,
--     durationNano / 1000000 as duration_ms
-- FROM signoz_index_v2
-- WHERE timestamp >= now() - INTERVAL 1 HOUR
--   AND statusCode = 2  -- STATUS_CODE_ERROR
-- ORDER BY timestamp DESC
-- LIMIT 100;
