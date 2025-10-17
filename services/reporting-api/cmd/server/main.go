package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/hoodrun/rpc-gateway/reporting-api/internal/config"
	"github.com/hoodrun/rpc-gateway/reporting-api/internal/handlers"
	"github.com/hoodrun/rpc-gateway/reporting-api/internal/middleware"
	"github.com/hoodrun/rpc-gateway/reporting-api/internal/repository"
	"go.uber.org/zap"
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	if err := cfg.Validate(); err != nil {
		log.Fatalf("Invalid config: %v", err)
	}

	// Initialize logger
	logger, err := initLogger(cfg.Logging)
	if err != nil {
		log.Fatalf("Failed to initialize logger: %v", err)
	}
	defer logger.Sync()

	logger.Info("Starting Reporting API",
		zap.String("environment", cfg.Server.Environment),
		zap.String("port", cfg.Server.Port),
	)

	// Initialize database connections
	chRepo, err := repository.NewClickHouseRepository(&cfg.ClickHouse)
	if err != nil {
		logger.Fatal("Failed to connect to ClickHouse", zap.Error(err))
	}
	defer chRepo.Close()
	logger.Info("Connected to ClickHouse", zap.String("host", cfg.ClickHouse.Host))

	pgRepo, err := repository.NewPostgresRepository(&cfg.PostgreSQL)
	if err != nil {
		logger.Fatal("Failed to connect to PostgreSQL", zap.Error(err))
	}
	defer pgRepo.Close()
	logger.Info("Connected to PostgreSQL", zap.String("host", cfg.PostgreSQL.Host))

	// Initialize handlers
	healthHandler := handlers.NewHealthHandler(chRepo, pgRepo)
	usageHandler := handlers.NewUsageHandler(chRepo, pgRepo)

	// Setup Gin router
	if cfg.Server.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(middleware.CORSMiddleware())

	// Request logging middleware
	router.Use(gin.LoggerWithConfig(gin.LoggerConfig{
		Formatter: func(param gin.LogFormatterParams) string {
			return fmt.Sprintf("[%s] %s %s %d %s %s\n",
				param.TimeStamp.Format(time.RFC3339),
				param.Method,
				param.Path,
				param.StatusCode,
				param.Latency,
				param.ErrorMessage,
			)
		},
	}))

	// Health check endpoints (no auth required)
	router.GET("/health", healthHandler.HealthCheck)
	router.GET("/health/live", healthHandler.LivenessProbe)
	router.GET("/health/ready", healthHandler.ReadinessProbe)
	router.GET("/metrics", handlers.PrometheusHandler())

	// API v1 routes (with optional auth)
	v1 := router.Group("/api/v1")
	if cfg.Auth.Enabled {
		v1.Use(middleware.AuthMiddleware(&cfg.Auth))
		logger.Info("Authentication enabled", zap.Bool("auth_enabled", true))
	} else {
		logger.Warn("Authentication DISABLED - not suitable for production!")
	}

	// Usage endpoints
	v1.GET("/usage/organization/:orgId/summary", usageHandler.GetOrganizationUsageSummary)
	v1.GET("/usage/organization/:orgId/daily", usageHandler.GetOrganizationDailyUsage)
	v1.GET("/usage/organization/:orgId/hourly", usageHandler.GetOrganizationHourlyUsage)
	v1.GET("/usage/organization/:orgId/by-chain", usageHandler.GetOrganizationUsageByChain)
	v1.GET("/usage/key/:keyPrefix", usageHandler.GetAPIKeyUsage)

	// Create HTTP server
	srv := &http.Server{
		Addr:         ":" + cfg.Server.Port,
		Handler:      router,
		ReadTimeout:  time.Duration(cfg.Server.ReadTimeout) * time.Second,
		WriteTimeout: time.Duration(cfg.Server.WriteTimeout) * time.Second,
	}

	// Start server in a goroutine
	go func() {
		logger.Info("Server listening", zap.String("addr", srv.Addr))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("Failed to start server", zap.Error(err))
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("Shutting down server...")

	// Graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(cfg.Server.ShutdownTimeout)*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		logger.Fatal("Server forced to shutdown", zap.Error(err))
	}

	logger.Info("Server exited gracefully")
}

func initLogger(cfg config.LoggingConfig) (*zap.Logger, error) {
	var zapConfig zap.Config

	if cfg.Format == "json" {
		zapConfig = zap.NewProductionConfig()
	} else {
		zapConfig = zap.NewDevelopmentConfig()
	}

	// Set log level
	switch cfg.Level {
	case "debug":
		zapConfig.Level = zap.NewAtomicLevelAt(zap.DebugLevel)
	case "info":
		zapConfig.Level = zap.NewAtomicLevelAt(zap.InfoLevel)
	case "warn":
		zapConfig.Level = zap.NewAtomicLevelAt(zap.WarnLevel)
	case "error":
		zapConfig.Level = zap.NewAtomicLevelAt(zap.ErrorLevel)
	default:
		zapConfig.Level = zap.NewAtomicLevelAt(zap.InfoLevel)
	}

	// Set output path
	if cfg.OutputPath != "" && cfg.OutputPath != "stdout" {
		zapConfig.OutputPaths = []string{cfg.OutputPath}
	}

	return zapConfig.Build()
}
