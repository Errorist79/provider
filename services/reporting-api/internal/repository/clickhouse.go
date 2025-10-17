package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/ClickHouse/clickhouse-go/v2"
	"github.com/ClickHouse/clickhouse-go/v2/lib/driver"
	"github.com/hoodrun/rpc-gateway/reporting-api/internal/config"
	"github.com/hoodrun/rpc-gateway/reporting-api/internal/models"
)

type ClickHouseRepository struct {
	conn driver.Conn
}

func NewClickHouseRepository(cfg *config.ClickHouseConfig) (*ClickHouseRepository, error) {
	conn, err := clickhouse.Open(&clickhouse.Options{
		Addr: []string{fmt.Sprintf("%s:%d", cfg.Host, cfg.Port)},
		Auth: clickhouse.Auth{
			Database: cfg.Database,
			Username: cfg.Username,
			Password: cfg.Password,
		},
		Debug: cfg.Debug,
		Settings: clickhouse.Settings{
			"max_execution_time": 60,
		},
		Compression: &clickhouse.Compression{
			Method: clickhouse.CompressionLZ4,
		},
		DialTimeout:     10 * time.Second,
		MaxOpenConns:    10,
		MaxIdleConns:    5,
		ConnMaxLifetime: time.Hour,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to clickhouse: %w", err)
	}

	// Test connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := conn.Ping(ctx); err != nil {
		return nil, fmt.Errorf("failed to ping clickhouse: %w", err)
	}

	return &ClickHouseRepository{conn: conn}, nil
}

func (r *ClickHouseRepository) Close() error {
	return r.conn.Close()
}

func (r *ClickHouseRepository) Ping(ctx context.Context) error {
	return r.conn.Ping(ctx)
}

// GetUsageSummary retrieves aggregated usage data for an organization
func (r *ClickHouseRepository) GetUsageSummary(ctx context.Context, orgID string, startDate, endDate time.Time) (*models.UsageSummary, error) {
	query := `
		SELECT
			sumMerge(request_count) AS total_requests,
			sumMerge(compute_units_used) AS total_compute_units,
			sumMerge(total_response_size) / 1024.0 / 1024.0 / 1024.0 AS total_egress_gb,
			sumMerge(error_count) AS error_count,
			(sumMerge(error_count) / nullIf(sumMerge(request_count), 0)) * 100 AS error_rate_pct,
			toFloat64(arrayElement(quantilesMerge(0.50, 0.95, 0.99)(latency_ms_quantiles), 2)) AS latency_p95,
			toFloat64(arrayElement(quantilesMerge(0.50, 0.95, 0.99)(latency_ms_quantiles), 3)) AS latency_p99
		FROM usage_daily
		WHERE organization_id = ?
		  AND date >= ?
		  AND date <= ?
	`

	var summary models.SummaryMetrics
	err := r.conn.QueryRow(ctx, query, orgID, startDate, endDate).Scan(
		&summary.TotalRequests,
		&summary.TotalComputeUnits,
		&summary.TotalEgressGB,
		&summary.ErrorCount,
		&summary.ErrorRatePct,
		&summary.AvgLatencyP95MS,
		&summary.AvgLatencyP99MS,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to get usage summary: %w", err)
	}

	if summary.TotalRequests > 0 {
		summary.SuccessRate = 100.0 - summary.ErrorRatePct
	}

	return &models.UsageSummary{
		OrganizationID: orgID,
		Period: models.Period{
			Start: startDate,
			End:   endDate,
		},
		Summary: summary,
	}, nil
}

// GetUsageByChain retrieves usage data broken down by chain
func (r *ClickHouseRepository) GetUsageByChain(ctx context.Context, orgID string, startDate, endDate time.Time) ([]models.ChainUsage, error) {
	query := `
		SELECT
			chain_slug,
			chain_type,
			sumMerge(request_count) AS requests,
			sumMerge(compute_units_used) AS compute_units,
			sumMerge(total_response_size) / 1024.0 / 1024.0 / 1024.0 AS egress_gb,
			sumMerge(error_count) AS error_count,
			(sumMerge(error_count) / nullIf(sumMerge(request_count), 0)) * 100 AS error_rate_pct,
			toFloat64(arrayElement(quantilesMerge(0.50, 0.95, 0.99)(latency_ms_quantiles), 2)) AS avg_latency_p95
		FROM usage_daily
		WHERE organization_id = ?
		  AND date >= ?
		  AND date <= ?
		GROUP BY chain_slug, chain_type
		ORDER BY requests DESC
		LIMIT 50
	`

	rows, err := r.conn.Query(ctx, query, orgID, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to get usage by chain: %w", err)
	}
	defer rows.Close()

	var chainUsage []models.ChainUsage
	for rows.Next() {
		var usage models.ChainUsage
		if err := rows.Scan(
			&usage.ChainSlug,
			&usage.ChainType,
			&usage.Requests,
			&usage.ComputeUnits,
			&usage.EgressGB,
			&usage.ErrorCount,
			&usage.ErrorRatePct,
			&usage.AvgLatencyP95,
		); err != nil {
			return nil, fmt.Errorf("failed to scan chain usage row: %w", err)
		}
		chainUsage = append(chainUsage, usage)
	}

	return chainUsage, rows.Err()
}

// GetUsageByMethod retrieves usage data broken down by RPC method
func (r *ClickHouseRepository) GetUsageByMethod(ctx context.Context, orgID string, startDate, endDate time.Time, limit int) ([]models.MethodUsage, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}

	query := `
		SELECT
			rpc_method,
			sumMerge(request_count) AS requests,
			sumMerge(compute_units_used) AS compute_units,
			sumMerge(error_count) AS error_count,
			toFloat64(arrayElement(quantilesMerge(0.50, 0.95, 0.99)(latency_ms_quantiles), 1)) AS latency_p50
		FROM usage_hourly
		WHERE organization_id = ?
		  AND hour >= ?
		  AND hour <= ?
		  AND rpc_method != ''
		GROUP BY rpc_method
		ORDER BY requests DESC
		LIMIT ?
	`

	rows, err := r.conn.Query(ctx, query, orgID, startDate, endDate, limit)
	if err != nil {
		return nil, fmt.Errorf("failed to get usage by method: %w", err)
	}
	defer rows.Close()

	var methodUsage []models.MethodUsage
	for rows.Next() {
		var usage models.MethodUsage
		if err := rows.Scan(
			&usage.Method,
			&usage.Requests,
			&usage.ComputeUnits,
			&usage.ErrorCount,
			&usage.AvgLatencyMS,
		); err != nil {
			return nil, fmt.Errorf("failed to scan method usage row: %w", err)
		}
		methodUsage = append(methodUsage, usage)
	}

	return methodUsage, rows.Err()
}

// GetDailyUsage retrieves daily aggregated usage
func (r *ClickHouseRepository) GetDailyUsage(ctx context.Context, orgID string, startDate, endDate time.Time) ([]models.DailyUsage, error) {
	query := `
		SELECT
			date,
			sumMerge(request_count) AS requests,
			sumMerge(compute_units_used) AS compute_units,
			sumMerge(total_response_size) / 1024.0 / 1024.0 / 1024.0 AS egress_gb,
			sumMerge(error_count) AS error_count,
			(sumMerge(error_count) / nullIf(sumMerge(request_count), 0)) * 100 AS error_rate_pct,
			(sumMerge(status_2xx_count) / nullIf(sumMerge(request_count), 0)) * 100 AS success_rate
		FROM usage_daily
		WHERE organization_id = ?
		  AND date >= ?
		  AND date <= ?
		GROUP BY date
		ORDER BY date ASC
	`

	rows, err := r.conn.Query(ctx, query, orgID, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to get daily usage: %w", err)
	}
	defer rows.Close()

	var dailyUsage []models.DailyUsage
	for rows.Next() {
		var usage models.DailyUsage
		if err := rows.Scan(
			&usage.Date,
			&usage.Requests,
			&usage.ComputeUnits,
			&usage.EgressGB,
			&usage.ErrorCount,
			&usage.ErrorRatePct,
			&usage.SuccessRate,
		); err != nil {
			return nil, fmt.Errorf("failed to scan daily usage row: %w", err)
		}
		dailyUsage = append(dailyUsage, usage)
	}

	return dailyUsage, rows.Err()
}

// GetHourlyUsage retrieves hourly aggregated usage
func (r *ClickHouseRepository) GetHourlyUsage(ctx context.Context, orgID string, startDate, endDate time.Time, chainSlug string) ([]models.HourlyUsage, error) {
	query := `
		SELECT
			hour,
			chain_slug,
			sumMerge(request_count) AS requests,
			sumMerge(compute_units_used) AS compute_units,
			sumMerge(total_response_size) / 1024.0 / 1024.0 / 1024.0 AS egress_gb,
			sumMerge(error_count) AS error_count,
			toFloat64(arrayElement(quantilesMerge(0.50, 0.95, 0.99)(latency_ms_quantiles), 1)) AS latency_p50,
			toFloat64(arrayElement(quantilesMerge(0.50, 0.95, 0.99)(latency_ms_quantiles), 2)) AS latency_p95,
			toFloat64(arrayElement(quantilesMerge(0.50, 0.95, 0.99)(latency_ms_quantiles), 3)) AS latency_p99
		FROM usage_hourly
		WHERE organization_id = ?
		  AND hour >= ?
		  AND hour <= ?
	`

	args := []interface{}{orgID, startDate, endDate}
	if chainSlug != "" {
		query += " AND chain_slug = ?"
		args = append(args, chainSlug)
	}

	query += " GROUP BY hour, chain_slug ORDER BY hour ASC LIMIT 500"

	rows, err := r.conn.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to get hourly usage: %w", err)
	}
	defer rows.Close()

	var hourlyUsage []models.HourlyUsage
	for rows.Next() {
		var usage models.HourlyUsage
		if err := rows.Scan(
			&usage.Hour,
			&usage.ChainSlug,
			&usage.Requests,
			&usage.ComputeUnits,
			&usage.EgressGB,
			&usage.ErrorCount,
			&usage.LatencyP50,
			&usage.LatencyP95,
			&usage.LatencyP99,
		); err != nil {
			return nil, fmt.Errorf("failed to scan hourly usage row: %w", err)
		}
		hourlyUsage = append(hourlyUsage, usage)
	}

	return hourlyUsage, rows.Err()
}

// GetAPIKeyUsage retrieves usage for a specific API key
func (r *ClickHouseRepository) GetAPIKeyUsage(ctx context.Context, keyPrefix string, startDate, endDate time.Time) (*models.APIKeyUsage, error) {
	// First get the organization_id from the key prefix
	orgQuery := `
		SELECT DISTINCT organization_id
		FROM usage_daily
		WHERE api_key_prefix = ?
		LIMIT 1
	`

	var orgID string
	if err := r.conn.QueryRow(ctx, orgQuery, keyPrefix).Scan(&orgID); err != nil {
		return nil, fmt.Errorf("failed to get organization for key: %w", err)
	}

	// Get summary for this key
	summaryQuery := `
		SELECT
			sumMerge(request_count) AS total_requests,
			sumMerge(compute_units_used) AS total_compute_units,
			sumMerge(total_response_size) / 1024.0 / 1024.0 / 1024.0 AS total_egress_gb,
			sumMerge(error_count) AS error_count,
			(sumMerge(error_count) / nullIf(sumMerge(request_count), 0)) * 100 AS error_rate_pct,
			toFloat64(arrayElement(quantilesMerge(0.50, 0.95, 0.99)(latency_ms_quantiles), 2)) AS latency_p95
		FROM usage_daily
		WHERE api_key_prefix = ?
		  AND date >= ?
		  AND date <= ?
	`

	var summary models.SummaryMetrics
	err := r.conn.QueryRow(ctx, summaryQuery, keyPrefix, startDate, endDate).Scan(
		&summary.TotalRequests,
		&summary.TotalComputeUnits,
		&summary.TotalEgressGB,
		&summary.ErrorCount,
		&summary.ErrorRatePct,
		&summary.AvgLatencyP95MS,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to get key usage summary: %w", err)
	}

	if summary.TotalRequests > 0 {
		summary.SuccessRate = 100.0 - summary.ErrorRatePct
	}

	return &models.APIKeyUsage{
		KeyPrefix:      keyPrefix,
		OrganizationID: orgID,
		Period: models.Period{
			Start: startDate,
			End:   endDate,
		},
		Summary: summary,
	}, nil
}
