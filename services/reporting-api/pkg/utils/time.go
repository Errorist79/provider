package utils

import "time"

// ParseDateRange parses start and end date strings
func ParseDateRange(startStr, endStr string) (time.Time, time.Time, error) {
	layout := "2006-01-02"

	var start, end time.Time
	var err error

	if startStr != "" {
		start, err = time.Parse(layout, startStr)
		if err != nil {
			return time.Time{}, time.Time{}, err
		}
	} else {
		// Default to start of current month
		now := time.Now().UTC()
		start = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	}

	if endStr != "" {
		end, err = time.Parse(layout, endStr)
		if err != nil {
			return time.Time{}, time.Time{}, err
		}
		// Set to end of day
		end = end.Add(23*time.Hour + 59*time.Minute + 59*time.Second)
	} else {
		end = time.Now().UTC()
	}

	return start, end, nil
}

// StartOfMonth returns the first moment of the month
func StartOfMonth(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), 1, 0, 0, 0, 0, t.Location())
}

// EndOfMonth returns the last moment of the month
func EndOfMonth(t time.Time) time.Time {
	return StartOfMonth(t).AddDate(0, 1, 0).Add(-time.Nanosecond)
}

// StartOfDay returns the first moment of the day
func StartOfDay(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}

// EndOfDay returns the last moment of the day
func EndOfDay(t time.Time) time.Time {
	return StartOfDay(t).Add(24*time.Hour - time.Nanosecond)
}

// DaysBetween returns the number of days between two dates
func DaysBetween(start, end time.Time) int {
	return int(end.Sub(start).Hours() / 24)
}

// FormatDateRange formats a date range for display
func FormatDateRange(start, end time.Time) string {
	return start.Format("2006-01-02") + " to " + end.Format("2006-01-02")
}
