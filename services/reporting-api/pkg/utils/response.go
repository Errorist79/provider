package utils

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// APIError represents a standard API error response
type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Details string `json:"details,omitempty"`
}

// SuccessResponse sends a successful JSON response
func SuccessResponse(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, data)
}

// ErrorResponse sends an error JSON response
func ErrorResponse(c *gin.Context, statusCode int, message string) {
	c.JSON(statusCode, gin.H{
		"error": message,
	})
}

// ErrorResponseWithCode sends an error with a custom error code
func ErrorResponseWithCode(c *gin.Context, statusCode int, code, message string) {
	c.JSON(statusCode, APIError{
		Code:    code,
		Message: message,
	})
}

// ErrorResponseWithDetails sends a detailed error response
func ErrorResponseWithDetails(c *gin.Context, statusCode int, code, message, details string) {
	c.JSON(statusCode, APIError{
		Code:    code,
		Message: message,
		Details: details,
	})
}

// BadRequestError sends a 400 Bad Request error
func BadRequestError(c *gin.Context, message string) {
	ErrorResponse(c, http.StatusBadRequest, message)
}

// UnauthorizedError sends a 401 Unauthorized error
func UnauthorizedError(c *gin.Context, message string) {
	ErrorResponse(c, http.StatusUnauthorized, message)
}

// ForbiddenError sends a 403 Forbidden error
func ForbiddenError(c *gin.Context, message string) {
	ErrorResponse(c, http.StatusForbidden, message)
}

// NotFoundError sends a 404 Not Found error
func NotFoundError(c *gin.Context, message string) {
	ErrorResponse(c, http.StatusNotFound, message)
}

// InternalServerError sends a 500 Internal Server Error
func InternalServerError(c *gin.Context, message string) {
	ErrorResponse(c, http.StatusInternalServerError, message)
}

// ServiceUnavailableError sends a 503 Service Unavailable error
func ServiceUnavailableError(c *gin.Context, message string) {
	ErrorResponse(c, http.StatusServiceUnavailable, message)
}
