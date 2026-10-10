CREATE DATABASE IF NOT EXISTS multibase;

-- One row per probe execution from any site.
CREATE TABLE IF NOT EXISTS multibase.probe_results
(
    ts          DateTime64(3, 'UTC'),
    site        LowCardinality(String),
    probe       LowCardinality(String),   -- query | replication_lag | auth
    target      LowCardinality(String),
    ok          UInt8,
    latency_ms  Float32,
    value       Float64 DEFAULT 0,        -- probe-specific, e.g. lag seconds
    error       String DEFAULT ''
)
ENGINE = MergeTree
PARTITION BY toYYYYMMDD(ts)
ORDER BY (probe, site, ts)
TTL toDateTime(ts) + INTERVAL 30 DAY DELETE;

CREATE TABLE IF NOT EXISTS multibase.logs
(
    ts        DateTime64(3, 'UTC'),
    node      LowCardinality(String),
    namespace LowCardinality(String),
    pod       String,
    level     LowCardinality(String),
    line      String
)
ENGINE = MergeTree
PARTITION BY toYYYYMMDD(ts)
ORDER BY (namespace, node, ts)
TTL toDateTime(ts) + INTERVAL 14 DAY DELETE;

-- Per-minute rollup kept longer than raw rows.
CREATE TABLE IF NOT EXISTS multibase.probe_1m
(
    minute   DateTime,
    site     LowCardinality(String),
    probe    LowCardinality(String),
    total    UInt64,
    failures UInt64,
    p95      AggregateFunction(quantile(0.95), Float32)
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(minute)
ORDER BY (probe, site, minute)
TTL minute + INTERVAL 180 DAY DELETE;

CREATE MATERIALIZED VIEW IF NOT EXISTS multibase.probe_1m_mv TO multibase.probe_1m AS
SELECT
    toStartOfMinute(toDateTime(ts)) AS minute,
    site,
    probe,
    count() AS total,
    countIf(ok = 0) AS failures,
    quantileState(0.95)(latency_ms) AS p95
FROM multibase.probe_results
GROUP BY minute, site, probe;
