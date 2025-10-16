 **production-grade Billing Guide** — aligned with our existing multi-chain RPC provider architecture (Kong + Unkey + SigNoz + PSQL + ClickHouse + OpenMeter + Stripe + Paraşüt).

---

# 💳 Billing Architecture Guide (Multi-Region: Global + Turkey)

## 1. Overview

| Layer              | Purpose                                                                                           |
| ------------------ | ------------------------------------------------------------------------------------------------- |
| **OpenMeter**      | Source of truth for usage metering & rating. Translates ClickHouse telemetry into billable units. |
| **Stripe Billing** | Global (USD/EUR) billing, subscriptions, taxes, payments, and invoices.                           |
| **Paraşüt API**    | Turkish e-invoice (e-Fatura/e-Arşiv) compliance, TL invoices, tax reporting.                      |
| **PostgreSQL**     | Contracts, plans, pricing metadata, and invoice records (ledger).                                 |
| **ClickHouse**     | Raw usage telemetry (requests, egress, latency) feeding OpenMeter.                                |
| **Vault/KMS**      | Protects all credentials and API tokens (Stripe, Paraşüt, OpenMeter).                             |

---

## 2. Billing Flow

```
Kong / OTel / ClickHouse → OpenMeter (ingest)
   ↓
OpenMeter → computes usage → applies plan rules
   ↓
(Stripe or Paraşüt, depending on customer region)
   ↓
Invoice → Payment / e-Fatura → Audit Ledger (Postgres)
```

---

## 3. Core Concepts

| Concept           | Description                                                                        |
| ----------------- | ---------------------------------------------------------------------------------- |
| **Meter**         | A usage metric definition, e.g. “requests”, “egress_GB”, “latency_weighted_calls”. |
| **Rating Rule**   | Defines how usage converts to cost (free tier, per-unit, chain-based multipliers). |
| **Contract**      | Customer agreement (fixed, metered, or hybrid). Stored in Postgres.                |
| **Billing Cycle** | Typically monthly; OpenMeter finalizes a “snapshot” at period close.               |
| **Invoice Sink**  | Where finalized bill data is pushed — Stripe (global) or Paraşüt (Turkey).         |

---

## 4. Stripe (Global Customers)

### Flow

1. OpenMeter sends **Usage Records** → Stripe’s [Metered Billing API](https://stripe.com/docs/billing/subscriptions/metered-billing).
2. Stripe automatically:

   * Computes per-plan totals.
   * Adds taxes & currency conversion.
   * Generates invoices and receipts.
   * Handles payments, dunning, refunds.

### Setup

* One **Stripe Product** per RPC plan (`Free`, `Pro`, `Enterprise`).
* Each Product has one or more **Prices**:

  * `type=recurring` for base fee.
  * `type=metered` for overage (requests, bandwidth, etc.).
* OpenMeter → `stripe_usage_records` endpoint (daily or hourly batches).
* Webhooks → `invoice.finalized`, `payment_succeeded` → store invoice in Postgres.

### Fixed Contracts

* Mark `contract.type = FIXED`.
* Stripe issues recurring fixed invoices (e.g., $500/mo).
* OpenMeter still reports usage → analytics only (no charge).

---

## 5. Paraşüt (Turkey Customers)

### Flow

1. OpenMeter computes usage & cost in **TL** (using daily FX rate).
2. Generates **invoice draft payload** for Paraşüt:

   * Line items: `"ETH Mainnet - 120M requests"`, `"Egress 45 GB"`, etc.
   * Customer VAT info, address, contract reference.
3. Sends to **Paraşüt API** → auto-create & finalize e-Fatura/e-Arşiv invoice.

### Fixed Contracts

* `contract.type = FIXED` → static line item (“Monthly RPC Service – 25,000 TL”).
* Usage report (OpenMeter) attached as JSON/PDF appendix (for SLA proof).

### Compliance

* Paraşüt handles Turkish tax (KDV), serial numbers, archiving.
* Invoices auto-stored in **Postgres** with `invoice_number`, `hash`, and `pdf_url`.

---

## 6. OpenMeter Integration Details

| Task                 | Responsibility                                                            |
| -------------------- | ------------------------------------------------------------------------- |
| **Ingestion**        | Collect usage from ClickHouse (`requests_raw`) every N minutes.           |
| **Meter Definition** | YAML/JSON per chain or service (`req_count`, `egress_GB`, `weighted_tx`). |
| **Rating Logic**     | Free tiers, overage prices, per-chain coefficients (ETH vs. BSC, etc.).   |
| **Contract Mapping** | Each OpenMeter “consumer” = one contract in Postgres.                     |
| **Closing Cycle**    | Hourly/daily snapshots → monthly aggregation → push to Stripe/Paraşüt.    |
| **Reconciliation**   | Compare invoice totals vs. OpenMeter snapshot → store proof hash.         |

---

## 7. Database Schema (PostgreSQL)

| Table       | Key Fields                                                                                 | Purpose                                |
| ----------- | ------------------------------------------------------------------------------------------ | -------------------------------------- |
| `contracts` | id, org_id, type (FIXED/METERED), price_fixed, plan_id, start_at, end_at, currency, region | Source of truth for pricing agreements |
| `plans`     | id, name, base_fee, included_units, overage_rate, currency, billing_cycle                  | Pricing templates                      |
| `invoices`  | id, contract_id, period_start, period_end, subtotal, tax, total, status, pdf_url           | Final billing record                   |
| `ledger`    | id, entity_type, entity_id, event, amount, currency, timestamp, hash                       | Immutable audit log                    |

---

## 8. Currency & Conversion

* **OpenMeter Rating** always uses a normalized base (USD).
* **Paraşüt** invoices require TL; use daily CBRT or ECB exchange rate snapshot.
* Store FX rate per invoice to keep audit consistency.

---

## 9. Audit & Proof

| Layer                   | Proof Mechanism                                                    |
| ----------------------- | ------------------------------------------------------------------ |
| **OpenMeter**           | Signed daily usage snapshots (JSON + SHA256) → S3 Glacier.         |
| **Postgres Ledger**     | Append-only; every change hashed & timestamped.                    |
| **Invoice Copies**      | PDF stored in cloud storage (immutable).                           |
| **Reconciliation Logs** | OpenMeter vs Stripe/Paraşüt invoice totals verified automatically. |

---

## 10. Security & Reliability

* **API tokens** (Stripe, Paraşüt, OpenMeter) in Vault/SOPS (rotated ≤90 days).
* **mTLS / HTTPS only** between internal services.
* **Billing worker** retries with exponential backoff for network failures.
* **Immutable backups** (S3 + local encrypted archive).
* **Double-entry ledger** ensures financial integrity.

---

## 11. Failure & Edge Cases

| Scenario               | Mitigation                                           |
| ---------------------- | ---------------------------------------------------- |
| OpenMeter down         | Buffer usage in ClickHouse → replay once recovered.  |
| Stripe outage          | Queue usage reports → retry.                         |
| Paraşüt API rate-limit | Back-off + staggered submission.                     |
| Currency API fail      | Reuse last known FX rate (mark invoice “estimated”). |
| Audit mismatch         | Alert + manual reconciliation dashboard.             |

---

## 12. Reporting & Analytics

* Dashboard metrics:

  * Revenue per chain / per plan.
  * Top 10 customers by usage.
  * Margin analysis (infra cost vs. revenue).
* Source: ClickHouse (usage) + Postgres (contracts/invoices).

---

## ✅ TL;DR

| Role                         | Tool                                                    |
| ---------------------------- | ------------------------------------------------------- |
| **Metering & Rating Engine** | 🧮 **OpenMeter** (on-prem/self-hosted)                  |
| **Global Billing**           | 🌎 **Stripe Billing** (automated subscriptions & taxes) |
| **Local Billing (Turkey)**   | 🇹🇷 **Paraşüt API** (official e-Fatura/e-Arşiv)        |
| **Contract & Ledger DB**     | 🗄️ **PostgreSQL**                                      |
| **Usage Source**             | 📊 **ClickHouse → OpenMeter ingestion**                 |

→ **Result:**
Fully auditable, legally compliant, hybrid (usage + fixed) billing pipeline —
works globally via Stripe and locally in Turkey via Paraşüt, with OpenMeter as the unified metering core.
