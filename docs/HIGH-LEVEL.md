# 🏗️ HoodRun RPC Provider — System Architecture (Microservices + Billing + Multi-Chain)

This document describes the **production-ready architecture** for the HoodRun RPC Provider platform.  
It integrates **multi-chain RPC routing**, **API key management**, **rate-limiting**, **observability**, and **billing** (Stripe + Paraşüt via OpenMeter) using a modular **microservice architecture**.

---

## 1. Overview

| Domain | Core Components | Purpose |
|--------|-----------------|----------|
| **Edge & Routing** | Kong OSS, Kong Manager OSS | Entry point, per-chain routing, rate-limit, circuit-breaker |
| **Identity & Keys** | Unkey (self-hosted), Redis | API key lifecycle + short-TTL verification cache |
| **Telemetry & Data** | ClickHouse, SigNoz (OTel) | High-volume request telemetry and analytics |
| **Business Logic** | PostgreSQL | Contracts, plans, invoices, audit ledger |
| **Billing & Rating** | OpenMeter, Stripe, Paraşüt | Metered usage + invoicing (global & local) |
| **Control Plane** | Admin API, Customer Portal (Next.js) | Admin dashboard, customer UI, key & plan management |
| **Support Services** | Vault/SOPS/KMS, Queue (NATS/Kafka) | Secrets management, async jobs, ETL, webhooks |

---

## 2. Microservices Topology

### **Edge Layer**
- **Kong Gateway** → Stateless, routes requests to per-chain upstream pools.  
  - Performs rate-limit, circuit breaking, redaction, and mTLS verification.  
- **Kong Manager OSS** → Admin/control interface (GitOps-managed declarative configs).

### **Auth & Key Layer**
- **Unkey Service** → Sole API key store (create, revoke, verify, policy).  
- **Auth Bridge** → Stateless Go service (`services/auth-bridge`) sitting between Kong and Unkey, caching verification results in Redis and enriching requests with `identityId`, `plan`, and `scopes`.  
- **Redis Cache** → 30–60s TTL cache for Unkey verify results + revoke-webhook purge.

### **Telemetry & Data Layer**
- **Ingest Worker** → Parses OTel/Kong access logs → writes to ClickHouse schema (multi-chain aware).  
- **Usage Aggregator** → Builds hourly/daily rollups in ClickHouse (materialized views).  
- **Reporting API** → Exposes metrics (per key, chain, project) for dashboards & billing reports.  
- **SigNoz** → OTel-native APM/logging/tracing, sharing the ClickHouse backend.

### **Billing & Financial Layer**
- **OpenMeter** → Metering & rating engine. Calculates billable usage from ClickHouse.  
- **Billing Orchestrator** → Pushes rated usage to **Stripe** (global) or **Paraşüt** (Turkey).  
- **Reconciliation Worker** → Cross-checks invoices with OpenMeter closing snapshots, writes immutable `ledger` entries.

### **Business & Portal Layer**
- **Admin API** → CRUD for orgs, plans, policies, contracts, and billing management (RBAC + SSO).  
- **Customer Portal (Next.js)** → Self-service key creation (via Unkey), plan upgrades, usage charts (from ClickHouse), invoice history (Stripe/Paraşüt).

---

## 3. Data & Storage

| Component | Type | Responsibility |
|------------|------|----------------|
| **PostgreSQL** | OLTP | orgs, users, projects, contracts, plans, invoices, immutable ledger (no secrets) |
| **ClickHouse** | OLAP | `requests_raw`, `usage_hourly`, `usage_daily` (TTL partitioned) |
| **Redis** | Cache | Unkey verify cache, optional rate-limit counters |
| **Vault/SOPS/KMS** | Secrets | API tokens, DB creds, mTLS certs, rotated ≤90d |
| **Queue (NATS/Kafka)** | Messaging | ETL, billing, reconciliation, webhooks |
| **Object Storage (S3/Glacier)** | Archival | Immutable storage for invoices, OpenMeter snapshots |

---

## 4. Request Flow (Multi-Chain RPC)

```

Client → https://{chain}.{domain}/v1/{API_KEY}/{rpc-path?}

1. Kong Pre-Function: extract {API_KEY} → header, mask path
2. Unkey.verify (mTLS + allowlist)
3. Kong binds Consumer (custom_id = identityId)
4. Apply rate-limit (per-consumer, per-chain, global)
5. Route to chain-specific upstream pool (health checks, retries, circuit breaker)
6. Emit OTel spans/logs → SigNoz (ClickHouse backend)

```

- **Scopes**: Keys must allow the target chain/method (e.g., disable `eth_sendRawTransaction` on Free plans).  
- **Redaction**: API key fully masked in logs/traces.  
- **Routing**: Each chain has its own `Service` and `Upstream` set.

---

## 5. Billing Flow (Usage → Invoice)

```

Kong / OTel / ClickHouse → OpenMeter (meters + rating rules)
↓
Billing Orchestrator
↓
Stripe (Global) or Paraşüt (Turkey)
↓
Invoice + Payment
↓
PostgreSQL: invoices, contracts, immutable ledger

```

- **OpenMeter** computes usage per key/chain/project.  
- **Stripe** manages global billing, currency conversion, and payment.  
- **Paraşüt** handles Turkish e-Fatura/e-Arşiv invoices in TL.  
- **Reconciliation Worker** verifies Stripe/Paraşüt totals against OpenMeter snapshots.

---

## 6. Scaling Strategy

| Service Type | Scaling Mode | Notes |
|---------------|--------------|-------|
| Stateless (Kong, Admin API, Portal, Workers) | Horizontal | Use HPA by CPU/RPS/queue lag |
| Stateful (PostgreSQL, ClickHouse, Redis, OpenMeter, SigNoz) | Replicated / Clustered | HA configurations |
| Regional Scaling | Per chain region | Independent Kong + upstream pools per region |
| Chain-Specific Scaling | Separate autoscaling policies per chain RPC load |
| Queue-Driven | Lag-based | Ingest & billing pipelines scale with queue depth |

---

## 7. Reliability & Degrade Modes

| Scenario | Mitigation |
|-----------|-------------|
| Unkey partial outage | Increase cache TTL temporarily; deny unknown/new keys; time-bounded mode. |
| Chain brownout | Throttle or reroute to healthy regions/providers; fast fail with clear RPC error. |
| ClickHouse lag | Buffer OpenMeter ingestion; re-rate late usage on next cycle. |
| Stripe/Paraşüt outage | Queue invoice writes; retry with backoff; mark `pending`. |
| Disaster Recovery | PSQL PITR, CH snapshot, Kong config via GitOps (immutable tags). |

---

## 8. Security Policies

**Secrets & Keys**
- Full API keys exist **only in Unkey** (KMS at rest, TLS in transit).  
- Service secrets in **Vault/SOPS**, rotation ≤90 days.

**Network & Transport**
- mTLS between services (SPIFFE/SPIRE or cert-manager).  
- HSTS enforced at edge; TLS ≥1.2; optional WAF/CDN layer.

**Redaction & PII**
- All logs/traces scrubbed of API keys and sensitive fields.  
- PII minimized; billing data exempted from deletion per financial law.

**RBAC & Access**
- SSO (OIDC); least-privilege tokens (verify ≠ rotate/revoke).  
- Roles: `viewer`, `ops`, `billing`, `admin`.

**Data Retention**
- ClickHouse TTL: raw 7–14 days, hourly 90 days, daily 12–18 months.  
- PostgreSQL: contracts/invoices/ledger retained ≥5 years.  
- Immutable archives in S3 (Object Lock/Glacier).

---

## 9. Rate-Limit & Abuse Policies

- **Plan → Policy mapping:** per consumer, per chain, global cap, burst/steady.  
- **IP allow/block lists** and request/body size limits.  
- **Abuse detection:** anomalies trigger temporary throttling and alerts.  
- **WAF optional** for region-specific edge filtering.

---

## 10. Observability & SLOs

| Metric | Source | Target |
|---------|---------|--------|
| p95 Latency (gateway) | OTel → SigNoz | < 300 ms |
| Error Rate (RPC) | Kong + Upstream | < 1% |
| Rate-Limit Hit Ratio | Kong Metrics | < 5% |
| Availability | per Chain | ≥ 99.9% |
| Billing Reconciliation Accuracy | OpenMeter ↔ Stripe/Paraşüt | ≥ 99.9% match |

Alerts:  
5xx spikes, rate-limit saturation, Unkey verify failures, upstream brownouts, ClickHouse lag, billing mismatches.

---

## 11. Governance & Change Management

- **Config-as-Code**: Kong declarative YAML, versioned in Git.  
- **Infra-as-Code**: Terraform; environment workspaces, drift detection.  
- **Release Strategy**: Canary per chain, auto-rollback on SLO breach.  
- **Approval Windows**: Controlled deployment windows, audit logs for infra/billing changes.  
- **Runbooks**:
  - Key leak response (revoke, cache purge, customer notice).  
  - Upstream failover & throttle plan.  
  - Billing reconciliation workflow (manual approval path).

---

## 12. Billing & Compliance Policies

- **Contract Types:** FIXED / METERED / HYBRID.  
- **FX Handling:** For TL invoices, use end-of-day CBRT/ECB rate; store per invoice.  
- **Reconciliation:** Stripe/Paraşüt total == OpenMeter closing snapshot; any difference triggers credit note flow.  
- **Ledger:** Append-only, hashed entries; signed daily exports to immutable storage.  
- **Retention:** All invoices and contracts archived ≥5 years for compliance.

---

## 13. Resource Baseline (Initial Production)

| Component | Start Configuration | Scaling Note |
|------------|---------------------|---------------|
| Kong | 2–4 replicas / region | Autoscale by RPS |
| PostgreSQL | Managed HA, 2 vCPU / 8–16 GB RAM | Scale vertically for I/O |
| ClickHouse | 3 nodes, NVMe, 32–64 GB RAM | Partition by day, replicate |
| Redis | 2–3 replicas, AOF enabled | Failover acceptable |
| OpenMeter | 2 replicas, stateless ingest | Queue buffer on lag |
| SigNoz | Shared CH cluster, separate DB | Scale by ingestion rate |

---

## 14. Why This Architecture Works

- **Separation of concerns:** Edge (Kong), Secrets (Unkey), Telemetry (CH/SigNoz), Rating (OpenMeter), Billing (Stripe/Paraşüt), Contracts (PSQL).  
- **Multi-chain native:** Chain is a first-class field in routing, scopes, limits, metrics, and billing.  
- **Audit-ready:** Immutable ledger, signed snapshots, external invoice IDs.  
- **Scalable:** Stateless edges and workers, clustered databases.  
- **Secure & compliant:** mTLS, KMS, GDPR/KVKK-aligned retention, formal runbooks.

---

## 15. TL;DR Summary

| Layer | Component | Function |
|--------|------------|-----------|
| **Edge** | Kong OSS | Routing, rate-limit, circuit breaker |
| **Identity** | Unkey + Redis | Key lifecycle & fast verification |
| **Telemetry** | SigNoz + ClickHouse | Logging, metrics, tracing |
| **Data Plane** | PostgreSQL | Contracts, invoices, ledger |
| **Billing Plane** | OpenMeter + Stripe + Paraşüt | Usage rating + invoicing |
| **Control Plane** | Admin API + Portal | Management UIs & APIs |
| **Security Plane** | Vault + mTLS + IAM | Secrets & identity hardening |

**Result:**  
A horizontally scalable, audit-compliant, multi-chain RPC infrastructure with real-time observability, secure key management, and legally sound billing across global (Stripe) and Turkish (Paraşüt) customers.
