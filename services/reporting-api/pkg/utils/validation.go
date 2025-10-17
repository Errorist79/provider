package utils

import (
	"errors"
	"time"
)

var (
	ErrInvalidDateRange   = errors.New("end_date must be after start_date")
	ErrDateRangeTooLarge  = errors.New("date range cannot exceed 1 year")
	ErrInvalidDateFormat  = errors.New("invalid date format, use YYYY-MM-DD")
	ErrMissingParameter   = errors.New("required parameter is missing")
	ErrInvalidParameter   = errors.New("invalid parameter value")
)

// ValidateDateRange validates that end date is after start date
func ValidateDateRange(start, end time.Time) error {
	if end.Before(start) {
		return ErrInvalidDateRange
	}

	// Check if range is too large (max 1 year)
	if end.Sub(start) > 365*24*time.Hour {
		return ErrDateRangeTooLarge
	}

	return nil
}

// ValidateHourlyDateRange validates date range for hourly queries (max 7 days)
func ValidateHourlyDateRange(start, end time.Time) error {
	if err := ValidateDateRange(start, end); err != nil {
		return err
	}

	// Hourly data limited to 7 days
	if end.Sub(start) > 7*24*time.Hour {
		return errors.New("hourly data limited to 7 days maximum")
	}

	return nil
}

// ValidatePagination validates pagination parameters
func ValidatePagination(limit, offset int, maxLimit int) (int, int, error) {
	if limit <= 0 {
		limit = 50 // default
	}

	if limit > maxLimit {
		limit = maxLimit
	}

	if offset < 0 {
		offset = 0
	}

	return limit, offset, nil
}

// ValidateUUID checks if a string is a valid UUID (basic check)
func ValidateUUID(s string) bool {
	// Basic UUID format check (8-4-4-4-12)
	if len(s) != 36 {
		return false
	}

	for i, c := range s {
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if c != '-' {
				return false
			}
		} else if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
			return false
		}
	}

	return true
}

// ValidateChainSlug validates a chain slug format
func ValidateChainSlug(slug string) bool {
	if slug == "" {
		return false
	}

	// Chain slugs should be lowercase alphanumeric with hyphens
	for _, c := range slug {
		if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') {
			return false
		}
	}

	return true
}
