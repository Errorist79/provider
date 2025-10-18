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
	Error     string `json:"error"`
	Code      string `json:"code,omitempty"`
	RequestID string `json:"request_id,omitempty"`
}

var ErrMissingOrganization = errors.New("organizationId missing from key metadata")

func NewVerificationHandler(cache *cache.Cache, unkey *unkey.Client) *VerificationHandler {
	return &VerificationHandler{cache: cache, unkey: unkey}
}

func requestIDFrom(v *models.Verification) string {
	if v == nil {
		return ""
	}
	return v.RequestID
}

func setRequestIDHeader(c *gin.Context, v *models.Verification) {
	if id := requestIDFrom(v); id != "" {
		c.Header("X-Unkey-Request-Id", id)
	}
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
				setRequestIDHeader(c, &cached)
				status := http.StatusOK
				if !cached.Valid {
					status = unkey.StatusFromCode(cached.Code)
				}
				c.JSON(status, cached)
				return
			}
		}
	}

	verification, err := h.verifyWithUnkey(ctx, key)
	if err != nil {
		setRequestIDHeader(c, verification)
		errResp := errorResponse{
			Error:     err.Error(),
			RequestID: requestIDFrom(verification),
		}

		switch {
		case errors.Is(err, context.DeadlineExceeded):
			errResp.Error = "upstream verification timeout"
			c.JSON(http.StatusGatewayTimeout, errResp)
		case errors.Is(err, ErrMissingOrganization):
			c.JSON(http.StatusUnprocessableEntity, errResp)
		default:
			c.JSON(http.StatusInternalServerError, errResp)
		}
		return
	}

	if verification == nil {
		c.JSON(http.StatusInternalServerError, errorResponse{Error: "verification response missing"})
		return
	}

	setRequestIDHeader(c, verification)

	if !verification.Valid {
		status := unkey.StatusFromCode(verification.Code)
		if status == http.StatusOK {
			status = http.StatusUnauthorized
		}
		c.JSON(status, verification)
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
		return verification, err
	}

	if verification == nil {
		return nil, errors.New("unkey verification response missing")
	}

	if verification.Valid && verification.Organization == "" {
		return verification, ErrMissingOrganization
	}

	return verification, nil
}
