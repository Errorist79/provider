# Architecture (High Level)

* **Kong Gateway (OSS) + Kong Manager OSS**: Entry point, auth/rate limit/route management.
* **Unkey (self-hosted)**: API key lifecycle (issue/verify/revoke), source of truth for plans/owners.
* **SigNoz (OTel-native)**: APM/log/trace UI (**runs on ClickHouse**).
* **PostgreSQL (OLTP)**: Organization, user, plan/policy, billing, key **metadata** (no secrets).
* **ClickHouse (OLAP/Telemetry)**: Request logs, latency/error metrics, and **usage roll-up**.
* **Redis (cache)**: Short TTL cache for Unkey verify results + revoke webhook purge.
* **Vault/SOPS/KMS**: Secrets for Unkey/DB/MTLS, rotation.
* **(Optional) Queue**: ETL/roll-up and async sync jobs.

## Traffic Flow

1. `eth-mainnet.rpc101.org/v1/API_KEY/...` → **Kong**
2. Pre-function: `API_KEY` extracted from path → moved to **header**, **path is masked**.
3. **Unkey Verify** (mTLS + allowlist) → returns `identityId`, `plan`.
4. `consumer.custom_id = identityId` with **kong.client.authenticate(...)**
5. **Rate limiting** and policy matching (per-consumer/per-route, burst + steady)
6. Upstream RPC; **OTel** exports metrics/logs/traces to SigNoz.

## Data Model & Resources

### PostgreSQL (transactional)

* `orgs, users, consumers (custom_id = unkey_identity_id)`
* `api_keys (unkey_key_id, prefix, status, plan, created_at, last_used_at)` **(no secret)**
* `plans, subscriptions, invoices, webhooks`
* **Real-time decisions** (plan/policy, RBAC, billing rules) are read from here.

### ClickHouse (telemetry/analytics)

* `requests_raw` (very high volume; compatible with OTel/SigNoz ingest format)
* **Materialized Views**:

  * `usage_hourly` (per key/route/method)
  * `usage_daily` (billing and reporting)
* `errors`, `latency` (precomputed metric columns: p50/p95/p99)
* **Partitioning**: by day; **TTL policy** (e.g. raw 7–14 days, hourly 90 days, daily 12–18 months)

> Note: **SigNoz** already uses ClickHouse; your **usage tables can run in the same cluster** as SigNoz (using a separate database/namespace).

## ETL & Usage Flow

* **Ingest**: Kong access logs/OTel → SigNoz (ClickHouse).
* **Roll-up**: `requests_raw` → `usage_hourly/daily` (materialized views and/or periodic merge).
* **Billing/UI**: Customer UI reads **usage data from CH** and plan/policy **from PostgreSQL**.

## Security

* **API key secrets exist only in Unkey** (at-rest KMS, in-transit TLS).
* **mTLS**: Kong ↔ Unkey; **HSTS + enforced HTTPS** at the edge.
* **Redaction**: Kong log/OTel attribute processor → masks key in URL/path.
* **Least-privilege IAM**: Separate Unkey tokens for `verify` vs `rotate/revoke`.
* **Cache**: Verify results cached 30–60 sec TTL; **revoke webhook** triggers purge.
* **Rate limiting**: Only in **Kong** (IP/key/route); global & burst limits; body/req-size limit.
* **Secrets**: Vault/SOPS; scheduled rotation (≤90 days).
* **Backups**: Encrypted daily PostgreSQL snapshots; CH with S3-backed disk + TTL/replication.

## Operations & Resilience

* **HA**: Kong/Unkey/SigNoz/PSQL/CH min 2 replicas; L4 LB health checks.
* **SLO**: p95 < 300 ms (gateway), 99.9% availability; **alerts**: 5xx rate, RL hit, verify failure, upstream timeout.
* **Runbook**: Throttle → upstream; revoke flow; key leak; **degraded mode** (increase verify cache TTL).
* **Config-as-Code**: Declarative Kong config, lint + smoke test in CI/CD.

## Multi-Tenancy & Policy

* **Plan → Policy mapping**: Unkey `plan` tag → Kong rate-limit policy (tag-driven).
* **Tenant isolation**: `consumer.custom_id` = `unkey_identity_id`; **row-level filter** in CH by tenant/consumer key.

## Extra Measures for API Key in URL Requirement

* Extract + mask in path → move to header (pass downstream via header).
* **Full key is never persisted** in any logs/trace fields.
* Ephemeral/rotation-friendly design (multiple active keys allowed; one-click revoke).

**Summary:**

* **PostgreSQL**: identity, plan/policy, billing, metadata (no secrets).
* **ClickHouse**: high-volume telemetry + usage roll-up (natural fit with SigNoz).
* **Kong**: auth (Unkey verify), **rate limiting**, secure edge.
* **Unkey**: single “source of secret”.
* All connected using **cache, mTLS, redaction, TTL, HA** principles.