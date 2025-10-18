package server

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/hoodrunio/rpc-gateway/auth-bridge/internal/handlers"
)

func New(handler *handlers.VerificationHandler) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)

	router := gin.New()
	router.Use(gin.Recovery())

	router.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	v1 := router.Group("/api/v1")
	{
		v1.POST("/verify", handler.Verify)
	}

	return router
}
