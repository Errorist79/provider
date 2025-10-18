package main

import (
	"context"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/hoodrunio/rpc-gateway/auth-bridge/internal/cache"
	"github.com/hoodrunio/rpc-gateway/auth-bridge/internal/config"
	"github.com/hoodrunio/rpc-gateway/auth-bridge/internal/handlers"
	"github.com/hoodrunio/rpc-gateway/auth-bridge/internal/server"
	"github.com/hoodrunio/rpc-gateway/auth-bridge/internal/unkey"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	cacheStore, err := cache.New(cfg.Cache)
	if err != nil {
		log.Fatalf("failed to initialize cache: %v", err)
	}
	if cacheStore != nil {
		defer cacheStore.Close()
	}

	unkeyClient, err := unkey.New(cfg.Unkey)
	if err != nil {
		log.Fatalf("failed to initialize unkey client: %v", err)
	}

	handler := handlers.NewVerificationHandler(cacheStore, unkeyClient)
	router := server.New(handler)

	srv := &http.Server{
		Addr:         ":" + cfg.Server.Port,
		Handler:      router,
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
	}

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server failed: %v", err)
		}
	}()

	logger.Info("auth-bridge started", slog.String("port", cfg.Server.Port))

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), cfg.Server.ShutdownTimeout)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("server forced to shutdown: %v", err)
	}

	logger.Info("auth-bridge stopped")
}
