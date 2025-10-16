How to handle **billing** (for both usage-based (aka pay-as-you-go) and fixed-price contracts) while staying compliant, auditable, and future-proof.

---

## 💳 1. Billing Model Architecture

| Layer                                      | Purpose                                                                                               |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| **ClickHouse**                             | Source of truth for metered usage — requests, bandwidth, success/error, latency.                      |
| **PostgreSQL**                             | Plans, pricing rules, contracts, invoices, payments, audit trail.                                     |
| **Billing Engine (microservice / worker)** | Computes charges periodically from CH → PSQL. Handles fixed contracts, usage tiers, or hybrid models. |
| **Payment Gateway / Invoicing**            | Stripe, Lemon Squeezy, Paddle, or your own legal invoice generator.                                   |
| **Audit & Compliance Storage**             | Immutable logs (Postgres “ledger” table + encrypted offsite backup) for billing proofs and disputes.  |

---

## ⚙️ 2. Billing Models Supported

### **A. Usage-based (Metered)**

* Unit = requests, bandwidth (bytes_out), or combined compute weight.
* Pricing tiers: e.g., first 5M free, next 100M = $0.00005/req, etc.
* Daily/Hourly rollups from CH → aggregated per key/project → invoice per month.
* Discounts, overage protection, or “credit balance” system supported.

### **B. Fixed-price (Contract / SLA)**

* `contract_type = FIXED`, `price_monthly` or `price_yearly`, `start_at`, `end_at`.
* Metering still collected for analytics but **not charged** (optional usage cap enforcement).
* Legal contract ID linked to the billing record.
* Auto-renew or manual renewal workflow.

### **C. Hybrid (Base + Variable)**

* Example: $500/mo base (includes 50M requests) + $0.00005 per extra request.
* Simple to implement with plan templates in Postgres.

---

## 🧾 3. Database Schema (Core Tables in PostgreSQL)

| Table           | Key Columns                                                                                     | Purpose                                |
| --------------- | ----------------------------------------------------------------------------------------------- | -------------------------------------- |
| `plans`         | id, name, type (metered/fixed/hybrid), base_price, rate_per_unit, included_units, billing_cycle | Template for pricing logic             |
| `contracts`     | id, org_id, plan_id, start_at, end_at, price_fixed, currency, sla, custom_terms, signed_doc_url | One per client (even for custom deals) |
| `usage_rollups` | project_id, chain, day, requests, bytes_out, cost_calculated                                    | CH → PSQL daily import                 |
| `invoices`      | id, contract_id, period_start, period_end, subtotal, tax, total, status, pdf_url                | Actual invoice data                    |
| `ledger`        | id, entity_type, entity_id, event, amount, currency, timestamp, hash                            | Immutable audit ledger                 |

> Use append-only “ledger” design for provable billing logs (each row hashed + signed → audit trail).

---

## 🔐 4. Legal & Compliance Layer

| Requirement           | Implementation                                                                                                                                                                           |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Proof of usage**    | Immutable rollups (CH snapshot + signed export → PSQL ledger).                                                                                                                           |
| **Proof of delivery** | Log retention of request timestamps & source IPs for enterprise audits.                                                                                                                  |
| **Tax/VAT**           | Stripe/Paddle handle automatically per country. For direct invoices, integrate with a compliant provider (e.g., **FattureInCloud**, **Paraşüt**, **Netsis**, depending on jurisdiction). |
| **Contracts & SLAs**  | Store signed PDF (DocuSign / PandaDoc) URL + hash in `contracts`.                                                                                                                        |
| **Data retention**    | 5+ years for financial records; GDPR right-to-be-forgotten exemptions for billing data.                                                                                                  |
| **Audit exports**     | Monthly signed CSV/JSON snapshot of usage + invoice summary, stored in S3/Backblaze (immutability bucket).                                                                               |

---

## 🧮 5. Fixed-Price Enterprise Deals (like “X Company RPC Plan”)

**Recommended flow:**

1. Negotiate & sign a PDF contract (price, duration, SLA, limits).
2. Create a `contract` record with `type = FIXED`, reference document hash.
3. Billing service issues **recurring fixed invoices** monthly/yearly.
4. (Optional) enforce soft/hard usage cap → alert if they exceed SLA volume.
5. Renewal notifications via webhook/email; manual approval for renewal.

For legal protection:

* Always link the invoice to the signed contract by hash.
* Store both in encrypted, offsite, versioned storage (S3 Glacier / Backblaze B2).
* Keep copies of tax certificates, company info, and signed TOS snapshots.

---

## 💡 6. Billing Workflow Overview

```
CH (usage metrics)
  ↓ (hourly/daily rollup)
Billing Worker
  → calculate cost (plan rules, fixed/variable)
  → insert invoice_draft
  → generate PDF (Stripe or internal)
  → email/webhook → customer portal
  → on payment → mark paid → ledger event
```

*All transactions logged in `ledger` for audit proofs.*

---

## 🧰 7. Recommended Stack

* **Billing Service:** Node.js/NestJS worker or Go microservice (connects to PSQL + CH).
* **PDF Invoices:** `pdfkit`, `react-pdf`, or 3rd-party (Stripe, LemonSqueezy, Paddle).
* **Payment Gateway:**

  * Stripe (international SaaS)
  * Paddle (EU/UK VAT compliant)
  * Local: Iyzico, PayTR (for Turkish ops).
* **Contracts:** PandaDoc / DocuSign integration + webhook into `contracts` table.

---

## 🧭 TL;DR

* **Usage metering** → ClickHouse
* **Pricing logic + invoices** → PostgreSQL
* **Computation engine** → Billing Worker (hourly/daily)
* **Proof & Compliance** → Ledger + immutable storage
* **Fixed-price contracts** fully supported — legally binding, auditable, SLA-aware.
* Everything traceable, exportable, and provable — ready for enterprise deals and regulator audits.
