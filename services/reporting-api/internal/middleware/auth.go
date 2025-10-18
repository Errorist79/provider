package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/hoodrunio/rpc-gateway/reporting-api/internal/config"
)

// AuthMiddleware provides simple API key authentication for Phase 6
// In Phase 7-8, this will be replaced with Unkey integration and JWT tokens
func AuthMiddleware(cfg *config.AuthConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip auth if disabled (development mode)
		if !cfg.Enabled {
			c.Next()
			return
		}

		// Extract token from Authorization header
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "authorization header required",
			})
			c.Abort()
			return
		}

		// Expected format: "Bearer <token>"
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "invalid authorization header format, expected: Bearer <token>",
			})
			c.Abort()
			return
		}

		token := parts[1]

		// Simple token validation for Phase 6
		// TODO Phase 7: Replace with Unkey API key verification
		if token != cfg.AdminAPIKey {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "invalid api key",
			})
			c.Abort()
			return
		}

		// Token is valid, continue
		c.Next()
	}
}

// CORSMiddleware handles CORS for browser-based clients
func CORSMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}
