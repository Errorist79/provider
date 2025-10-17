# Billing Implementation Status (Phases 6-8)

## Current State: Usage Tracking Only

We are currently in **Phase 6-7** of the project roadmap, focusing on getting the core RPC gateway infrastructure working end-to-end. Billing functionality is **intentionally minimal** at this stage and will be fully implemented in **Phase 9**.

## What's Working Now

### ✅ Usage Data Collection

All usage data is being collected and stored in ClickHouse:

- **`requests_raw`** table captures every request with:
  - Chain, organization, consumer, API key
  - RPC method, compute units
  - Latency, status codes, errors
  - Response sizes (for egress billing)
  - 14-day retention

- **`usage_hourly`** aggregates hourly metrics:
  - Request counts, error rates
  - Compute units used
  - Bandwidth consumption
  - Latency percentiles (p50, p95, p99)
  - 90-day retention

- **`usage_daily`** provides daily rollups:
  - Perfect for monthly billing calculations
  - Success/error rates
  - 18-month retention (audit-ready)

### ✅ Organization & Subscription Management

PostgreSQL has the foundational tables:

- **`organizations`** - Customer accounts
- **`plans`** - Subscription tiers (Free, Basic, Pro, Enterprise)
- **`subscriptions`** - Active plan assignments
- **`api_keys`** - Key metadata (secrets in Unkey)

### ✅ Rate Limiting by Plan

Kong enforces plan-based rate limits:
- Free: 100 req/min
- Basic: 1,000 req/min
- Pro: 10,000 req/min
- Enterprise: 100,000 req/min

### ✅ Compute Units System

RPC methods are weighted by computational cost (database/postgresql/init/02_chains.sql):
- Simple calls: 1 CU (eth_blockNumber)
- Archive queries: 20 CU (eth_getLogs)
- Debug/trace: 50+ CU (debug_traceTransaction)

This data flows into ClickHouse and will be the foundation for metered billing.

## What's NOT Implemented Yet (Phase 9)

### ❌ Automated Billing

The `invoices` table exists but is a **placeholder**. No automated invoice generation.

### ❌ Payment Processing

- No Stripe integration (global billing)
- No Paraşüt integration (Turkish e-invoice compliance)
- No payment collection, dunning, or refunds

### ❌ Usage Metering Engine

- No OpenMeter deployment
- No rating rules (free tiers, overage pricing)
- No contract types (fixed vs. metered)

### ❌ Multi-Currency & FX

- No TRY (Turkish Lira) support
- No daily FX rate tracking
- No currency conversion logic

### ❌ Compliance & Audit

- No e-Fatura/e-Arşiv generation (Turkey)
- No reconciliation between usage and invoices
- No immutable ledger (double-entry bookkeeping)

## Why This Approach?

Billing is a **complex, high-dependency subsystem** that would significantly delay the core RPC gateway from becoming operational. By deferring it to Phase 9, we can:

1. **Focus on core functionality** (Kong routing, Unkey auth, rate limiting, multichain support)
2. **Validate the gateway works** before adding billing complexity
3. **Collect real usage data** that informs billing design
4. **Build confidence** in the infrastructure before handling money

## Phase 9 Migration Path

When we implement full billing, the migration will be straightforward because:

### 1. Usage Data Already Exists
ClickHouse `usage_hourly` and `usage_daily` tables are the **source of truth**. OpenMeter will ingest this data retroactively if needed.

### 2. Schema is Ready
The `invoices` table structure supports future enhancements:
```sql
-- Will add in Phase 9:
ALTER TABLE invoices ADD COLUMN stripe_invoice_id VARCHAR(255);
ALTER TABLE invoices ADD COLUMN parasut_invoice_id VARCHAR(255);
ALTER TABLE invoices ADD COLUMN fx_rate DECIMAL(10,4);
ALTER TABLE invoices ADD COLUMN reconciliation_hash VARCHAR(64);
```

### 3. Clear Integration Points

**Step 1:** Deploy OpenMeter (self-hosted or cloud)

**Step 2:** Configure meters and rating rules
```yaml
# Example OpenMeter meter definition
meters:
  - name: rpc_requests
    aggregation: SUM
    eventType: request
    valueProperty: compute_units
    groupBy: [organization_id, chain_slug]
```

**Step 3:** Set up Stripe webhook listeners
```bash
# Receive invoice.finalized events
POST /webhooks/stripe -> store in invoices table
```

**Step 4:** Integrate Paraşüt for Turkish customers
```typescript
// Generate e-Fatura when invoice is finalized
if (customer.region === 'TR') {
  await parasutClient.createInvoice({...})
}
```

**Step 5:** Schedule monthly billing jobs
```typescript
// Cron: 1st of each month
- Finalize previous month usage (OpenMeter)
- Generate invoices (Stripe or Paraşüt)
- Store in PostgreSQL invoices table
- Trigger payment collection
```

## Current Workarounds

For manual billing during Phases 6-8:

### Query Usage for an Organization

```sql
-- Get current month usage for billing
SELECT
    organization_id,
    chain_slug,
    SUM(request_count) as total_requests,
    SUM(compute_units_used) as total_compute_units,
    SUM(total_response_size) / 1024 / 1024 / 1024 as total_egress_gb,
    AVG(latency_p95) as avg_p95_latency
FROM telemetry.usage_daily
WHERE date >= toStartOfMonth(today())
  AND organization_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'
GROUP BY organization_id, chain_slug;
```

### Create Manual Invoice (if needed)

```sql
-- Example: Manual invoice entry
INSERT INTO invoices (
    organization_id,
    subscription_id,
    invoice_number,
    subtotal,
    tax,
    total,
    status,
    period_start,
    period_end,
    line_items
) VALUES (
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'g6kkih55-fi6h-0kkd-hh2j-2hh5hi9e6g77',
    'INV-2025-10-001',
    99.00,
    19.80,  -- 20% VAT
    118.80,
    'open',
    '2025-10-01',
    '2025-10-31',
    '[
        {"description": "Pro Plan - October 2025", "amount": 99.00},
        {"description": "Ethereum Mainnet - 10M requests", "amount": 0.00}
    ]'::jsonb
);
```

## Timeline

- **Phase 6** (Current): Basic usage analytics API
- **Phase 7** (Current): Get everything working end-to-end
- **Phase 8**: Security hardening, HA setup, production readiness
- **Phase 9**: Full billing system
  - Week 1-2: OpenMeter deployment & configuration
  - Week 3-4: Stripe integration (global billing)
  - Week 5-6: Paraşüt integration (Turkish compliance)
  - Week 7-8: Billing workers, reconciliation, dashboards
  - Week 9-10: Testing, audit preparation, go-live

## References

- **Full Billing Architecture**: See [BILLING.md](./BILLING.md)
- **Database Schema**: See `database/postgresql/init/01_schema.sql`
- **Usage Tables**: See `database/clickhouse/init/01_schema.sql`
- **Project Roadmap**: See [README.md](../README.md#development-roadmap)

---

**Last Updated**: 2025-10-17 (Phase 6-7 implementation)
