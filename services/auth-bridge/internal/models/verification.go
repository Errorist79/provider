package models

type Verification struct {
	Valid        bool                   `json:"valid"`
	KeyID        string                 `json:"key_id"`
	OwnerID      string                 `json:"owner_id"`
	APIID        string                 `json:"api_id"`
	WorkspaceID  string                 `json:"workspace_id"`
	ProjectID    string                 `json:"project_id"`
	Meta         map[string]interface{} `json:"meta"`
	RateLimit    map[string]interface{} `json:"rate_limit,omitempty"`
	Organization string                 `json:"organization_id,omitempty"`
	Plan         string                 `json:"plan,omitempty"`
}

func (v *Verification) Normalize() {
	if v.Meta == nil {
		return
	}

	if org, ok := v.Meta["organizationId"].(string); ok {
		v.Organization = org
	}
	if plan, ok := v.Meta["plan"].(string); ok {
		v.Plan = plan
	}
}
