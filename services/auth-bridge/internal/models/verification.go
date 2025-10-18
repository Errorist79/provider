package models

type IdentityRateLimit struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Limit     int64  `json:"limit"`
	Duration  int64  `json:"duration"`
	AutoApply bool   `json:"auto_apply"`
}

type Identity struct {
	ID         string                 `json:"id"`
	ExternalID string                 `json:"external_id"`
	Meta       map[string]interface{} `json:"meta,omitempty"`
	RateLimits []IdentityRateLimit    `json:"rate_limits,omitempty"`
}

type RateLimit struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Limit     int64  `json:"limit"`
	Duration  int64  `json:"duration"`
	Reset     int64  `json:"reset"`
	Remaining int64  `json:"remaining"`
	Exceeded  bool   `json:"exceeded"`
	AutoApply bool   `json:"auto_apply"`
}

type Verification struct {
	Valid        bool                   `json:"valid"`
	Code         string                 `json:"code"`
	KeyID        string                 `json:"key_id"`
	KeyName      string                 `json:"key_name,omitempty"`
	OwnerID      string                 `json:"owner_id"`
	APIID        string                 `json:"api_id"`
	WorkspaceID  string                 `json:"workspace_id"`
	ProjectID    string                 `json:"project_id"`
	Meta         map[string]interface{} `json:"meta,omitempty"`
	Permissions  []string               `json:"permissions,omitempty"`
	Roles        []string               `json:"roles,omitempty"`
	Credits      *int                   `json:"credits,omitempty"`
	Enabled      *bool                  `json:"enabled,omitempty"`
	Expires      *int64                 `json:"expires,omitempty"`
	RateLimit    map[string]interface{} `json:"rate_limit,omitempty"`
	RateLimits   []RateLimit            `json:"rate_limits,omitempty"`
	Identity     *Identity              `json:"identity,omitempty"`
	Organization string                 `json:"organization_id,omitempty"`
	Plan         string                 `json:"plan,omitempty"`
	RequestID    string                 `json:"request_id,omitempty"`
}

func (v *Verification) Normalize() {
	if v == nil {
		return
	}

	if v.Identity != nil {
		if v.OwnerID == "" {
			v.OwnerID = v.Identity.ID
			if v.OwnerID == "" {
				v.OwnerID = v.Identity.ExternalID
			}
		}

		if v.Organization == "" && v.Identity.Meta != nil {
			if org, ok := v.Identity.Meta["organizationId"].(string); ok && org != "" {
				v.Organization = org
			}
		}
	}

	if v.Meta != nil {
		if org, ok := v.Meta["organizationId"].(string); ok && org != "" {
			v.Organization = org
		}
		if plan, ok := v.Meta["plan"].(string); ok && plan != "" {
			v.Plan = plan
		}
		if apiID, ok := v.Meta["apiId"].(string); ok && apiID != "" {
			v.APIID = apiID
		}
		if workspaceID, ok := v.Meta["workspaceId"].(string); ok && workspaceID != "" {
			v.WorkspaceID = workspaceID
		}
		if projectID, ok := v.Meta["projectId"].(string); ok && projectID != "" {
			v.ProjectID = projectID
		}
	}

	if v.OwnerID == "" {
		v.OwnerID = v.KeyID
	}

	if len(v.RateLimits) > 0 && v.RateLimit == nil {
		v.RateLimit = map[string]interface{}{
			"ratelimits": v.RateLimits,
		}
	}
}
