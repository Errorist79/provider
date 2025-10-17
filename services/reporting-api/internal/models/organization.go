package models

import "time"

// Organization represents a customer organization
type Organization struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Slug      string    `json:"slug"`
	Email     string    `json:"email"`
	Status    string    `json:"status"` // active, suspended, deleted
	PlanSlug  string    `json:"plan_slug,omitempty"`
	PlanName  string    `json:"plan_name,omitempty"`
	Metadata  Metadata  `json:"metadata,omitempty"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at,omitempty"`
}

// User represents a user within an organization
type User struct {
	ID             string    `json:"id"`
	OrganizationID string    `json:"organization_id"`
	Email          string    `json:"email"`
	Name           string    `json:"name"`
	Role           string    `json:"role"`   // owner, admin, member
	Status         string    `json:"status"` // active, inactive, suspended
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at,omitempty"`
}

// Plan represents a subscription plan
type Plan struct {
	ID                 string   `json:"id"`
	Name               string   `json:"name"`
	Slug               string   `json:"slug"`
	Description        string   `json:"description,omitempty"`
	RateLimitPerMinute int      `json:"rate_limit_per_minute"`
	RateLimitPerHour   int      `json:"rate_limit_per_hour"`
	RateLimitPerDay    int      `json:"rate_limit_per_day"`
	PriceMonthly       float64  `json:"price_monthly"`
	PriceYearly        float64  `json:"price_yearly"`
	Currency           string   `json:"currency"`
	AllowedChains      []string `json:"allowed_chains,omitempty"`
	ArchiveAccess      bool     `json:"archive_access"`
	TraceAccess        bool     `json:"trace_access"`
	WebsocketAccess    bool     `json:"websocket_access"`
	IsActive           bool     `json:"is_active"`
	IsPublic           bool     `json:"is_public"`
}

// Subscription represents an active subscription
type Subscription struct {
	ID                 string     `json:"id"`
	OrganizationID     string     `json:"organization_id"`
	PlanID             string     `json:"plan_id"`
	Status             string     `json:"status"`         // active, past_due, canceled, suspended
	BillingPeriod      string     `json:"billing_period"` // monthly, yearly
	CurrentPeriodStart time.Time  `json:"current_period_start"`
	CurrentPeriodEnd   time.Time  `json:"current_period_end"`
	TrialStart         *time.Time `json:"trial_start,omitempty"`
	TrialEnd           *time.Time `json:"trial_end,omitempty"`
	CancelAtPeriodEnd  bool       `json:"cancel_at_period_end"`
	CanceledAt         *time.Time `json:"canceled_at,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at,omitempty"`
}

// APIKey represents API key metadata (secrets stored in Unkey)
type APIKey struct {
	ID                string     `json:"id"`
	OrganizationID    string     `json:"organization_id"`
	ConsumerID        string     `json:"consumer_id"`
	UnkeyKeyID        string     `json:"unkey_key_id"`
	KeyPrefix         string     `json:"key_prefix"`
	Name              string     `json:"name"`
	Description       string     `json:"description,omitempty"`
	Status            string     `json:"status"` // active, revoked, expired
	LastUsedAt        *time.Time `json:"last_used_at,omitempty"`
	UsageCount        int64      `json:"usage_count"`
	ExpiresAt         *time.Time `json:"expires_at,omitempty"`
	AllowedChains     []string   `json:"allowed_chains,omitempty"`
	RestrictedMethods []string   `json:"restricted_methods,omitempty"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at,omitempty"`
	RevokedAt         *time.Time `json:"revoked_at,omitempty"`
}

// Consumer represents a Kong consumer linked to Unkey identity
type Consumer struct {
	ID              string    `json:"id"`
	OrganizationID  string    `json:"organization_id"`
	KongConsumerID  string    `json:"kong_consumer_id"`
	UnkeyIdentityID string    `json:"unkey_identity_id"`
	Status          string    `json:"status"` // active, inactive, suspended
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at,omitempty"`
}

// Metadata is a generic key-value map for extensibility
type Metadata map[string]interface{}

// OrganizationListResponse represents paginated organization list
type OrganizationListResponse struct {
	Organizations []Organization `json:"organizations"`
	Total         int            `json:"total"`
	Page          int            `json:"page"`
	PageSize      int            `json:"page_size"`
}

// OrganizationDetailResponse represents full organization details
type OrganizationDetailResponse struct {
	Organization Organization  `json:"organization"`
	Plan         *Plan         `json:"plan,omitempty"`
	Subscription *Subscription `json:"subscription,omitempty"`
	Users        []User        `json:"users,omitempty"`
	APIKeys      []APIKey      `json:"api_keys,omitempty"`
}
