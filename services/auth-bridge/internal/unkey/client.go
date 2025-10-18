package unkey

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/hoodrunio/rpc-gateway/auth-bridge/internal/config"
	"github.com/hoodrunio/rpc-gateway/auth-bridge/internal/models"
	v2 "github.com/unkeyed/sdks/api/go/v2"
	"github.com/unkeyed/sdks/api/go/v2/models/components"
)

type Client struct {
	sdk *v2.Unkey
}

func New(cfg config.UnkeyConfig) (*Client, error) {
	if cfg.APIKey == "" {
		return nil, fmt.Errorf("unkey api key is required")
	}

	timeout := cfg.RequestTimeout
	if timeout <= 0 {
		timeout = 3 * time.Second
	}

	httpClient := &http.Client{Timeout: timeout}

	opts := []v2.SDKOption{
		v2.WithSecurity(cfg.APIKey),
		v2.WithClient(httpClient),
	}

	if cfg.BaseURL != "" {
		opts = append(opts, v2.WithServerURL(cfg.BaseURL))
	}

	sdkClient := v2.New(opts...)

	return &Client{sdk: sdkClient}, nil
}

func (c *Client) VerifyKey(ctx context.Context, apiKey string) (*models.Verification, error) {
	req := components.V2KeysVerifyKeyRequestBody{
		Key: apiKey,
	}

	resp, err := c.sdk.Keys.VerifyKey(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("unkey verify request failed: %w", err)
	}

	body := resp.GetV2KeysVerifyKeyResponseBody()
	if body == nil {
		return nil, fmt.Errorf("unkey verify response missing body")
	}

	data := body.GetData()
	meta := body.GetMeta()

	verification := &models.Verification{
		Valid:       data.GetValid(),
		Code:        string(data.GetCode()),
		Meta:        data.GetMeta(),
		Permissions: data.GetPermissions(),
		Roles:       data.GetRoles(),
		Credits:     data.GetCredits(),
		Enabled:     data.GetEnabled(),
		Expires:     data.GetExpires(),
		RequestID:   meta.GetRequestID(),
	}

	if keyID := data.GetKeyID(); keyID != nil {
		verification.KeyID = *keyID
	}

	if name := data.GetName(); name != nil {
		verification.KeyName = *name
	}

	if identity := data.GetIdentity(); identity != nil {
		mapped := &models.Identity{
			ID:         identity.GetID(),
			ExternalID: identity.GetExternalID(),
			Meta:       identity.GetMeta(),
		}

		if rls := identity.GetRatelimits(); len(rls) > 0 {
			mapped.RateLimits = make([]models.IdentityRateLimit, 0, len(rls))
			for _, rl := range rls {
				mapped.RateLimits = append(mapped.RateLimits, models.IdentityRateLimit{
					ID:        rl.GetID(),
					Name:      rl.GetName(),
					Limit:     rl.GetLimit(),
					Duration:  rl.GetDuration(),
					AutoApply: rl.GetAutoApply(),
				})
			}
		}

		verification.Identity = mapped
		verification.OwnerID = mapped.ID
		if verification.OwnerID == "" {
			verification.OwnerID = mapped.ExternalID
		}
	}

	if rl := data.GetRatelimits(); len(rl) > 0 {
		verification.RateLimits = make([]models.RateLimit, 0, len(rl))
		for _, r := range rl {
			verification.RateLimits = append(verification.RateLimits, models.RateLimit{
				ID:        r.GetID(),
				Name:      r.GetName(),
				Limit:     r.GetLimit(),
				Duration:  r.GetDuration(),
				Reset:     r.GetReset(),
				Remaining: r.GetRemaining(),
				Exceeded:  r.GetExceeded(),
				AutoApply: r.GetAutoApply(),
			})
		}
	}

	verification.Normalize()

	if verification.Meta == nil {
		verification.Meta = map[string]interface{}{}
	}

	return verification, nil
}
