package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/hoodrun/rpc-gateway/reporting-api/internal/repository"
)

type HealthHandler struct {
	clickhouseRepo *repository.ClickHouseRepository
	postgresRepo   *repository.PostgresRepository
}

func NewHealthHandler(ch *repository.ClickHouseRepository, pg *repository.PostgresRepository) *HealthHandler {
	return &HealthHandler{
		clickhouseRepo: ch,
		postgresRepo:   pg,
	}
}

// LivenessProbe checks if the service is alive (always returns 200 if running)
// GET /health/live
func (h *HealthHandler) LivenessProbe(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status": "ok",
		"time":   time.Now().UTC(),
	})
}

// ReadinessProbe checks if the service is ready to handle requests (checks DB connections)
// GET /health/ready
func (h *HealthHandler) ReadinessProbe(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	checks := make(map[string]string)
	allHealthy := true

	// Check ClickHouse
	if err := h.clickhouseRepo.Ping(ctx); err != nil {
		checks["clickhouse"] = "unhealthy: " + err.Error()
		allHealthy = false
	} else {
		checks["clickhouse"] = "healthy"
	}

	// Check PostgreSQL
	if err := h.postgresRepo.Ping(ctx); err != nil {
		checks["postgresql"] = "unhealthy: " + err.Error()
		allHealthy = false
	} else {
		checks["postgresql"] = "healthy"
	}

	status := "ready"
	statusCode := http.StatusOK
	if !allHealthy {
		status = "not_ready"
		statusCode = http.StatusServiceUnavailable
	}

	c.JSON(statusCode, gin.H{
		"status": status,
		"checks": checks,
		"time":   time.Now().UTC(),
	})
}

// HealthCheck provides detailed health information
// GET /health
func (h *HealthHandler) HealthCheck(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	checks := make(map[string]interface{})

	// Check ClickHouse with timing
	chStart := time.Now()
	chErr := h.clickhouseRepo.Ping(ctx)
	chDuration := time.Since(chStart)

	checks["clickhouse"] = map[string]interface{}{
		"healthy":      chErr == nil,
		"response_ms":  chDuration.Milliseconds(),
		"error":        formatError(chErr),
	}

	// Check PostgreSQL with timing
	pgStart := time.Now()
	pgErr := h.postgresRepo.Ping(ctx)
	pgDuration := time.Since(pgStart)

	checks["postgresql"] = map[string]interface{}{
		"healthy":      pgErr == nil,
		"response_ms":  pgDuration.Milliseconds(),
		"error":        formatError(pgErr),
	}

	allHealthy := chErr == nil && pgErr == nil
	status := "healthy"
	statusCode := http.StatusOK

	if !allHealthy {
		status = "degraded"
		statusCode = http.StatusServiceUnavailable
	}

	c.JSON(statusCode, gin.H{
		"status":    status,
		"checks":    checks,
		"timestamp": time.Now().UTC(),
		"version":   "1.0.0", // TODO: load from build info
	})
}

func formatError(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}
