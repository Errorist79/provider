package models

import "time"

// UsageSummary represents high-level usage statistics for an organization
type UsageSummary struct {
	OrganizationID   string             `json:"organization_id"`
	Period           Period             `json:"period"`
	Summary          SummaryMetrics     `json:"summary"`
	ByChain          []ChainUsage       `json:"by_chain"`
	TopMethods       []MethodUsage      `json:"top_methods,omitempty"`
	DailyBreakdown   []DailyUsage       `json:"daily_breakdown,omitempty"`
}

// Period represents a time range
type Period struct {
	Start time.Time `json:"start"`
	End   time.Time `json:"end"`
}

// SummaryMetrics contains aggregated metrics
type SummaryMetrics struct {
	TotalRequests      uint64  `json:"total_requests"`
	TotalComputeUnits  uint64  `json:"total_compute_units"`
	TotalEgressGB      float64 `json:"total_egress_gb"`
	ErrorCount         uint64  `json:"error_count"`
	ErrorRatePct       float64 `json:"error_rate_pct"`
	AvgLatencyP95MS    float64 `json:"avg_latency_p95_ms"`
	AvgLatencyP99MS    float64 `json:"avg_latency_p99_ms,omitempty"`
	SuccessRate        float64 `json:"success_rate_pct"`
}

// ChainUsage represents usage per blockchain
type ChainUsage struct {
	ChainSlug      string  `json:"chain_slug"`
	ChainType      string  `json:"chain_type"`
	Requests       uint64  `json:"requests"`
	ComputeUnits   uint64  `json:"compute_units"`
	EgressGB       float64 `json:"egress_gb"`
	ErrorCount     uint64  `json:"error_count"`
	ErrorRatePct   float64 `json:"error_rate_pct"`
	AvgLatencyP95  float64 `json:"avg_latency_p95_ms"`
}

// MethodUsage represents usage per RPC method
type MethodUsage struct {
	Method       string  `json:"method"`
	Requests     uint64  `json:"requests"`
	ComputeUnits uint64  `json:"compute_units"`
	ErrorCount   uint64  `json:"error_count"`
	AvgLatencyMS float64 `json:"avg_latency_ms"`
}

// DailyUsage represents daily aggregated usage
type DailyUsage struct {
	Date          time.Time `json:"date"`
	Requests      uint64    `json:"requests"`
	ComputeUnits  uint64    `json:"compute_units"`
	EgressGB      float64   `json:"egress_gb"`
	ErrorCount    uint64    `json:"error_count"`
	ErrorRatePct  float64   `json:"error_rate_pct"`
	SuccessRate   float64   `json:"success_rate_pct"`
}

// HourlyUsage represents hourly aggregated usage
type HourlyUsage struct {
	Hour          time.Time      `json:"hour"`
	ChainSlug     string         `json:"chain_slug,omitempty"`
	Requests      uint64         `json:"requests"`
	ComputeUnits  uint64         `json:"compute_units"`
	EgressGB      float64        `json:"egress_gb"`
	ErrorCount    uint64         `json:"error_count"`
	LatencyP50    float64        `json:"latency_p50_ms"`
	LatencyP95    float64        `json:"latency_p95_ms"`
	LatencyP99    float64        `json:"latency_p99_ms"`
}

// APIKeyUsage represents usage for a specific API key
type APIKeyUsage struct {
	KeyPrefix        string         `json:"key_prefix"`
	OrganizationID   string         `json:"organization_id"`
	Period           Period         `json:"period"`
	Summary          SummaryMetrics `json:"summary"`
	ByChain          []ChainUsage   `json:"by_chain"`
	LastUsed         *time.Time     `json:"last_used,omitempty"`
}

// UsageQueryParams contains common query parameters
type UsageQueryParams struct {
	StartDate    time.Time
	EndDate      time.Time
	ChainSlug    string
	Aggregation  string // hour, day, month
	Limit        int
	Offset       int
}

// Organization represents basic org info from PostgreSQL
type Organization struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Slug      string    `json:"slug"`
	PlanSlug  string    `json:"plan_slug,omitempty"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}
