package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/hoodrun/rpc-gateway/reporting-api/internal/repository"
)

type UsageHandler struct {
	clickhouseRepo *repository.ClickHouseRepository
	postgresRepo   *repository.PostgresRepository
}

func NewUsageHandler(ch *repository.ClickHouseRepository, pg *repository.PostgresRepository) *UsageHandler {
	return &UsageHandler{
		clickhouseRepo: ch,
		postgresRepo:   pg,
	}
}

// GetOrganizationUsageSummary returns aggregated usage for an organization
// GET /api/v1/usage/organization/:orgId/summary
func (h *UsageHandler) GetOrganizationUsageSummary(c *gin.Context) {
	orgID := c.Param("orgId")
	if orgID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "organization id is required"})
		return
	}

	// Parse query parameters
	startDate, endDate, err := h.parseDateRange(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify organization exists
	org, err := h.postgresRepo.GetOrganization(c.Request.Context(), orgID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "organization not found"})
		return
	}

	// Get usage summary
	summary, err := h.clickhouseRepo.GetUsageSummary(c.Request.Context(), orgID, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get usage summary"})
		return
	}

	// Enrich with chain and method breakdowns if requested
	includeBreakdown := c.Query("include_breakdown") == "true"
	if includeBreakdown {
		chainUsage, err := h.clickhouseRepo.GetUsageByChain(c.Request.Context(), orgID, startDate, endDate)
		if err == nil {
			summary.ByChain = chainUsage
		}

		topMethods, err := h.clickhouseRepo.GetUsageByMethod(c.Request.Context(), orgID, startDate, endDate, 10)
		if err == nil {
			summary.TopMethods = topMethods
		}
	}

	// Add organization info to response
	response := gin.H{
		"organization": gin.H{
			"id":        org.ID,
			"name":      org.Name,
			"plan_slug": org.PlanSlug,
		},
		"usage": summary,
	}

	c.JSON(http.StatusOK, response)
}

// GetOrganizationDailyUsage returns daily breakdown
// GET /api/v1/usage/organization/:orgId/daily
func (h *UsageHandler) GetOrganizationDailyUsage(c *gin.Context) {
	orgID := c.Param("orgId")
	if orgID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "organization id is required"})
		return
	}

	startDate, endDate, err := h.parseDateRange(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	dailyUsage, err := h.clickhouseRepo.GetDailyUsage(c.Request.Context(), orgID, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get daily usage"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"organization_id": orgID,
		"period": gin.H{
			"start": startDate,
			"end":   endDate,
		},
		"daily_usage": dailyUsage,
	})
}

// GetOrganizationHourlyUsage returns hourly breakdown
// GET /api/v1/usage/organization/:orgId/hourly
func (h *UsageHandler) GetOrganizationHourlyUsage(c *gin.Context) {
	orgID := c.Param("orgId")
	if orgID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "organization id is required"})
		return
	}

	startDate, endDate, err := h.parseDateRange(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Limit hourly queries to max 7 days
	if endDate.Sub(startDate) > 7*24*time.Hour {
		c.JSON(http.StatusBadRequest, gin.H{"error": "hourly data limited to 7 days maximum"})
		return
	}

	chainSlug := c.Query("chain")

	hourlyUsage, err := h.clickhouseRepo.GetHourlyUsage(c.Request.Context(), orgID, startDate, endDate, chainSlug)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get hourly usage"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"organization_id": orgID,
		"chain_slug":      chainSlug,
		"period": gin.H{
			"start": startDate,
			"end":   endDate,
		},
		"hourly_usage": hourlyUsage,
	})
}

// GetOrganizationUsageByChain returns usage breakdown by chain
// GET /api/v1/usage/organization/:orgId/by-chain
func (h *UsageHandler) GetOrganizationUsageByChain(c *gin.Context) {
	orgID := c.Param("orgId")
	if orgID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "organization id is required"})
		return
	}

	startDate, endDate, err := h.parseDateRange(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	chainUsage, err := h.clickhouseRepo.GetUsageByChain(c.Request.Context(), orgID, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get usage by chain"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"organization_id": orgID,
		"period": gin.H{
			"start": startDate,
			"end":   endDate,
		},
		"by_chain": chainUsage,
	})
}

// GetAPIKeyUsage returns usage for a specific API key
// GET /api/v1/usage/key/:keyPrefix
func (h *UsageHandler) GetAPIKeyUsage(c *gin.Context) {
	keyPrefix := c.Param("keyPrefix")
	if keyPrefix == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "key prefix is required"})
		return
	}

	startDate, endDate, err := h.parseDateRange(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	keyUsage, err := h.clickhouseRepo.GetAPIKeyUsage(c.Request.Context(), keyPrefix, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get key usage"})
		return
	}

	c.JSON(http.StatusOK, keyUsage)
}

// Helper function to parse date range from query parameters
func (h *UsageHandler) parseDateRange(c *gin.Context) (time.Time, time.Time, error) {
	// Default to current month if not specified
	now := time.Now().UTC()
	defaultStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	defaultEnd := now

	startDateStr := c.Query("start_date")
	endDateStr := c.Query("end_date")

	var startDate, endDate time.Time
	var err error

	if startDateStr != "" {
		startDate, err = time.Parse("2006-01-02", startDateStr)
		if err != nil {
			return time.Time{}, time.Time{}, err
		}
	} else {
		startDate = defaultStart
	}

	if endDateStr != "" {
		endDate, err = time.Parse("2006-01-02", endDateStr)
		if err != nil {
			return time.Time{}, time.Time{}, err
		}
		// Set to end of day
		endDate = endDate.Add(23*time.Hour + 59*time.Minute + 59*time.Second)
	} else {
		endDate = defaultEnd
	}

	// Validate date range
	if endDate.Before(startDate) {
		return time.Time{}, time.Time{}, &InvalidDateRangeError{}
	}

	// Limit to max 1 year
	if endDate.Sub(startDate) > 365*24*time.Hour {
		return time.Time{}, time.Time{}, &DateRangeTooLargeError{}
	}

	return startDate, endDate, nil
}

type InvalidDateRangeError struct{}

func (e *InvalidDateRangeError) Error() string {
	return "end_date must be after start_date"
}

type DateRangeTooLargeError struct{}

func (e *DateRangeTooLargeError) Error() string {
	return "date range cannot exceed 1 year"
}

// parseLimit helper
func parseLimit(c *gin.Context, defaultLimit, maxLimit int) int {
	limitStr := c.Query("limit")
	if limitStr == "" {
		return defaultLimit
	}

	limit, err := strconv.Atoi(limitStr)
	if err != nil || limit <= 0 {
		return defaultLimit
	}

	if limit > maxLimit {
		return maxLimit
	}

	return limit
}
