package unkey

import (
	"net/http"

	"github.com/unkeyed/sdks/api/go/v2/models/components"
)

func StatusFromCode(code string) int {
	switch components.Code(code) {
	case components.CodeValid:
		return http.StatusOK
	case components.CodeNotFound:
		return http.StatusNotFound
	case components.CodeForbidden, components.CodeInsufficientPermissions:
		return http.StatusForbidden
	case components.CodeInsufficientCredits:
		return http.StatusPaymentRequired
	case components.CodeUsageExceeded, components.CodeRateLimited:
		return http.StatusTooManyRequests
	case components.CodeDisabled:
		return http.StatusForbidden
	case components.CodeExpired:
		return http.StatusUnauthorized
	default:
		if code == "" {
			return http.StatusOK
		}
		return http.StatusUnauthorized
	}
}
