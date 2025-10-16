# High-Level Architecture

* **Edge/Gateway:** Kong OSS + Kong Manager OSS
* **Auth/Keys:** Unkey (self-hosted; sole source of secrets)
* **Observability:** SigNoz (OTel on ClickHouse)
* **OLTP:** PostgreSQL (orgs/users/projects/plans/billing/metadata)
* **OLAP/Telemetry:** ClickHouse (high-volume requests/latency/errors + usage rollups)
* **Cache:** Redis (short-TTL verify cache + revoke purge)
* **Secrets:** Vault/SOPS/KMS
* **(Optional)** Queue/Workers (ETL, async sync, webhooks)

# Multi-Chain Request Flow

```
Client → https://{chain}.{domain}/v1/{API_KEY}/{rpc-path?} → Kong
  1) Pre-Function: extract API_KEY from path → move to header, mask path
  2) Unkey Verify (mTLS + IP allowlist) → {identityId, projectId, plan, scopes}
  3) Map to Kong Consumer: consumer.custom_id = identityId (tag project/plan)
  4) Rate-Limit (Kong): per-consumer + per-chain (+ global burst)
  5) Route by chain → Upstream pool (active health checks, retries/circuit breaker)
  6) Emit OTel spans/logs → SigNoz/ClickHouse
```

# Multi-Chain Routing Model

* **DNS/Subdomain per chain:** `eth-mainnet.rpc101.org`, `eth-sepolia.rpc101.org`, `bsc-mainnet…`, etc.
  *(Alt: single domain + `/chain/{id}/v1/{API_KEY}` with a strict router.)*
* **Kong Routes:** one route per chain (regex host/path), **Service** per chain → **Upstream** load-balancing to multiple nodes/providers.
* **Health & Resilience:** active checks, outlier ejection, per-chain timeouts/retries, circuit-breaker on 5xx/rate exceeded.

# Key & Project Scoping

* **Unkey** stores: key secret, owner, **projectId**, **allowed_chains** (scopes), plan/tier, status.
* **Authorization rule:** request host/route chain **must be in key.scopes** (deny otherwise).
* **Rate-limit policy selection:** by (consumer + chain + plan).
* **Rotation/Revocation:** multiple active keys per project; revoke → webhook → cache purge.

# Data Model (minimal, multi-tenant)

**PostgreSQL (no secrets):**

* `orgs`, `users`, `projects (org_id)`
* `consumers (custom_id = unkey_identity_id, org_id)`
* `api_keys (unkey_key_id, prefix, project_id, status, plan, allowed_chains, created_at, last_used_at)`
* `plans`, `subscriptions`, `invoices`, `webhooks`

**ClickHouse (telemetry/usage):**

* `requests_raw`: `ts, chain, project_id, consumer_id, key_id, method, http_status, rpc_code, latency_ms, bytes_in/out`
* **Materialized views:**

  * `usage_hourly(chain, project_id, key_id, counts, egress_bytes, p50/p95/p99)`
  * `usage_daily(chain, project_id, key_id, …)`
* **Retention:** raw 7–14d, hourly 90d, daily 12–18m; partition by day.

# Rate-Limiting Strategy

* **Enforced in Kong** (fast, inline):

  * Per-consumer **and** per-chain limits (e.g., 200 RPS per chain)
  * Per-project global cap (e.g., 1000 RPS total)
  * Bursting + steady limits; request/body size limits; connection caps
* **Policy mapping:** Unkey `plan` → Kong limit configs (tag-driven)
* **Block-lists/Allow-lists:** IP/CIDR as needed (abuse control)

# Security (key in URL, but hardened)

* **Secret custody:** full API key **only in Unkey** (KMS at rest). No key/secret hash in our DB.
* **mTLS:** Kong ↔ Unkey; **HSTS** at edge; TLS everywhere.
* **Redaction:** remove/mask key from **all** logs/traces/metrics (Kong log filter + OTel attribute processor).
* **Cache:** verify cache TTL 30–60s; revoke webhook → targeted purge.
* **Method allow-lists:** per chain (e.g., disable `eth_sendRawTransaction` on public/free tiers if desired).
* **RBAC:** Admin APIs behind SSO; least-privilege tokens for Unkey (verify vs rotate).

# Observability & SLOs

* **OTel**: add attributes `chain`, `project_id`, `method`, `key_id (hashed or token_id)`, `upstream`.
* **SigNoz Dashboards:** per-chain p95 latency, error rate, throughput; top projects/keys; RL hit ratios; upstream health.
* **SLOs:** p95 gateway latency < 300ms; 99.9% availability per chain; alerts for 5xx spikes, RL saturation, Unkey verify failures, upstream health.

# Upstream Pools (per chain)

* Multiple nodes/providers per chain; spread across AZs/regions if possible.
* Active health checks, jittered timeouts, **circuit-breaking** (fail fast), method-based routing if you split archival/trace vs full nodes.
* Optional **read/write split** by RPC method (e.g., tracing to dedicated pool).

# Usage, Billing, Plans

* **Usage source of truth:** ClickHouse hourly/daily rollups.
* **Billing logic:** PostgreSQL (plans/price tiers), compute from CH aggregates.
* **Egress accounting:** CH stores bytes_out per request; cost reports per chain/project.
* **Free/Pro/Enterprise:** map to RL, allowed methods, archive/trace access, retention, webhook rate, support SLAs.

# Environments & Tenant Isolation

* Separate **prod/stage** projects/keys; tags in Unkey and Kong.
* Per-tenant isolation via `consumer.custom_id` + project_id; CH queries always filter by tenant.
* Config-as-Code for Kong (declarative), CI/CD: lint + smoke tests, canary deploys per chain.

# Failure & Degrade Modes

* If Unkey is degraded: temporarily increase verify-cache TTL (with strict time-bound) and deny unknown/new keys.
* If a chain upstream is degraded: auto-throttle that chain; keep others healthy.
* Runbooks: revoke/rotate procedure, key leak response, RL tuning, upstream brownout.

---

**TL;DR**

* **Kong** = edge, auth binding, **rate-limit**, per-chain routing, resilience.
* **Unkey** = sole secret store + verify/scopes/plans; maps to Consumer.
* **SigNoz (ClickHouse)** = high-scale telemetry & dashboards; you also store your own **usage rollups** in CH.
* **PostgreSQL** = tenants/projects/plans/billing/metadata (no secrets).
* All flows are **multi-chain aware**: chain is a first-class field in routing, auth scopes, limits, metrics, and billing.
