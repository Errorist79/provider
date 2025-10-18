package unkey

import (
	"context"
	"errors"
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

var ErrInvalidKey = errors.New("unkey: invalid api key")

func New(cfg config.UnkeyConfig) (*Client, error) {
	if cfg.BaseURL == "" {
		return nil, fmt.Errorf("unkey base url is required")
	}
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
		v2.WithServerURL(cfg.BaseURL),
		v2.WithClient(httpClient),
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
	if !data.GetValid() {
		return nil, ErrInvalidKey
	}

	verification := &models.Verification{
		Valid: data.GetValid(),
		Meta:  data.GetMeta(),
	}

	if keyID := data.GetKeyID(); keyID != nil {
		verification.KeyID = *keyID
	}

	if identity := data.GetIdentity(); identity != nil {
		verification.OwnerID = identity.GetID()
		if verification.OwnerID == "" {
			verification.OwnerID = identity.GetExternalID()
		}
	}

	if verification.OwnerID == "" {
		verification.OwnerID = verification.KeyID
	}

	if rl := data.GetRatelimits(); len(rl) > 0 {
		verification.RateLimit = map[string]interface{}{
			"ratelimits": rl,
		}
	}

	verification.Normalize()

	return verification, nil
}
