package repository

import (
	"context"
	"fmt"

	"github.com/hoodrun/rpc-gateway/reporting-api/internal/config"
	"github.com/hoodrun/rpc-gateway/reporting-api/internal/models"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresRepository(cfg *config.PostgreSQLConfig) (*PostgresRepository, error) {
	connString := fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s pool_max_conns=%d pool_min_conns=%d",
		cfg.Host,
		cfg.Port,
		cfg.Username,
		cfg.Password,
		cfg.Database,
		cfg.SSLMode,
		cfg.MaxConns,
		cfg.MinConns,
	)

	poolConfig, err := pgxpool.ParseConfig(connString)
	if err != nil {
		return nil, fmt.Errorf("failed to parse postgres config: %w", err)
	}

	pool, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create postgres pool: %w", err)
	}

	// Test connection
	if err := pool.Ping(context.Background()); err != nil {
		return nil, fmt.Errorf("failed to ping postgres: %w", err)
	}

	return &PostgresRepository{pool: pool}, nil
}

func (r *PostgresRepository) Close() {
	r.pool.Close()
}

func (r *PostgresRepository) Ping(ctx context.Context) error {
	return r.pool.Ping(ctx)
}

// GetOrganization retrieves organization details
func (r *PostgresRepository) GetOrganization(ctx context.Context, orgID string) (*models.Organization, error) {
	query := `
		SELECT
			o.id,
			o.name,
			o.slug,
			COALESCE(p.slug, '') as plan_slug,
			o.status,
			o.created_at
		FROM organizations o
		LEFT JOIN subscriptions s ON o.id = s.organization_id AND s.status = 'active'
		LEFT JOIN plans p ON s.plan_id = p.id
		WHERE o.id = $1
		LIMIT 1
	`

	var org models.Organization
	err := r.pool.QueryRow(ctx, query, orgID).Scan(
		&org.ID,
		&org.Name,
		&org.Slug,
		&org.PlanSlug,
		&org.Status,
		&org.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to get organization: %w", err)
	}

	return &org, nil
}

// GetOrganizationBySlug retrieves organization by slug
func (r *PostgresRepository) GetOrganizationBySlug(ctx context.Context, slug string) (*models.Organization, error) {
	query := `
		SELECT
			o.id,
			o.name,
			o.slug,
			COALESCE(p.slug, '') as plan_slug,
			o.status,
			o.created_at
		FROM organizations o
		LEFT JOIN subscriptions s ON o.id = s.organization_id AND s.status = 'active'
		LEFT JOIN plans p ON s.plan_id = p.id
		WHERE o.slug = $1
		LIMIT 1
	`

	var org models.Organization
	err := r.pool.QueryRow(ctx, query, slug).Scan(
		&org.ID,
		&org.Name,
		&org.Slug,
		&org.PlanSlug,
		&org.Status,
		&org.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to get organization by slug: %w", err)
	}

	return &org, nil
}

// ValidateAPIKey checks if an API key is valid (simple auth for Phase 6)
func (r *PostgresRepository) ValidateAPIKey(ctx context.Context, keyPrefix string) (bool, string, error) {
	query := `
		SELECT organization_id
		FROM api_keys
		WHERE key_prefix = $1
		  AND status = 'active'
		  AND (expires_at IS NULL OR expires_at > NOW())
		LIMIT 1
	`

	var orgID string
	err := r.pool.QueryRow(ctx, query, keyPrefix).Scan(&orgID)
	if err != nil {
		// Key not found or expired
		return false, "", nil
	}

	return true, orgID, nil
}

// ListOrganizations retrieves all active organizations (admin only)
func (r *PostgresRepository) ListOrganizations(ctx context.Context, limit, offset int) ([]models.Organization, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	query := `
		SELECT
			o.id,
			o.name,
			o.slug,
			COALESCE(p.slug, '') as plan_slug,
			o.status,
			o.created_at
		FROM organizations o
		LEFT JOIN subscriptions s ON o.id = s.organization_id AND s.status = 'active'
		LEFT JOIN plans p ON s.plan_id = p.id
		WHERE o.status = 'active'
		ORDER BY o.created_at DESC
		LIMIT $1 OFFSET $2
	`

	rows, err := r.pool.Query(ctx, query, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to list organizations: %w", err)
	}
	defer rows.Close()

	var orgs []models.Organization
	for rows.Next() {
		var org models.Organization
		if err := rows.Scan(
			&org.ID,
			&org.Name,
			&org.Slug,
			&org.PlanSlug,
			&org.Status,
			&org.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("failed to scan organization row: %w", err)
		}
		orgs = append(orgs, org)
	}

	return orgs, rows.Err()
}
