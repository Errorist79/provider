package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/hoodrunio/rpc-gateway/auth-bridge/internal/cache"
	"github.com/hoodrunio/rpc-gateway/auth-bridge/internal/models"
	"github.com/hoodrunio/rpc-gateway/auth-bridge/internal/unkey"
)

type VerificationHandler struct {
	cache *cache.Cache
	unkey *unkey.Client
}

type verifyRequest struct {
	APIKey string `json:"api_key"`
	Key    string `json:"key"`
}

type errorResponse struct {
	Error string `json:"error"`
}

var ErrMissingOrganization = errors.New("organizationId missing from key metadata")

func NewVerificationHandler(cache *cache.Cache, unkey *unkey.Client) *VerificationHandler {
	return &VerificationHandler{cache: cache, unkey: unkey}
}

func (h *VerificationHandler) Verify(c *gin.Context) {
	var req verifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, errorResponse{Error: "invalid request payload"})
		return
	}

	key := req.APIKey
	if key == "" {
		key = req.Key
	}

	if key == "" {
		c.JSON(http.StatusBadRequest, errorResponse{Error: "api_key is required"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	cacheKey := ""
	if h.cache != nil {
		cacheKey = h.cache.HashKey(key)
		if data, err := h.cache.Get(ctx, cacheKey); err == nil && len(data) > 0 {
			var cached models.Verification
			if err := json.Unmarshal(data, &cached); err == nil {
				c.JSON(http.StatusOK, cached)
				return
			}
		}
	}

	verification, err := h.verifyWithUnkey(ctx, key)
	if err != nil {
		switch {
		case errors.Is(err, context.DeadlineExceeded):
			c.JSON(http.StatusGatewayTimeout, errorResponse{Error: "upstream verification timeout"})
		case errors.Is(err, unkey.ErrInvalidKey):
			c.JSON(http.StatusUnauthorized, errorResponse{Error: "invalid api key"})
		case errors.Is(err, ErrMissingOrganization):
			c.JSON(http.StatusUnprocessableEntity, errorResponse{Error: err.Error()})
		default:
			c.JSON(http.StatusInternalServerError, errorResponse{Error: err.Error()})
		}
		return
	}

	if h.cache != nil && cacheKey != "" {
		if payload, err := json.Marshal(verification); err == nil {
			cacheCtx, cancel := context.WithTimeout(context.Background(), time.Second)
			_ = h.cache.Set(cacheCtx, cacheKey, payload)
			cancel()
		}
	}

	c.JSON(http.StatusOK, verification)
}

func (h *VerificationHandler) verifyWithUnkey(ctx context.Context, key string) (*models.Verification, error) {
	verification, err := h.unkey.VerifyKey(ctx, key)
	if err != nil {
		return nil, err
	}

	if verification.Organization == "" {
		return nil, ErrMissingOrganization
	}

	return verification, nil
}
