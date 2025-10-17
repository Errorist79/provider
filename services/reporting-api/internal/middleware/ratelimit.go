package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// RateLimiter implements a simple in-memory token bucket rate limiter
type RateLimiter struct {
	tokens    map[string]*tokenBucket
	mu        sync.RWMutex
	rate      int           // tokens per window
	window    time.Duration // time window
	maxTokens int           // bucket size
}

type tokenBucket struct {
	tokens     int
	lastRefill time.Time
	mu         sync.Mutex
}

// NewRateLimiter creates a new rate limiter
// rate: number of requests allowed per window
// window: time window (e.g., 1 minute)
func NewRateLimiter(rate int, window time.Duration) *RateLimiter {
	rl := &RateLimiter{
		tokens:    make(map[string]*tokenBucket),
		rate:      rate,
		window:    window,
		maxTokens: rate,
	}

	// Start cleanup goroutine
	go rl.cleanup()

	return rl
}

// Allow checks if a request is allowed for the given key (IP, API key, etc.)
func (rl *RateLimiter) Allow(key string) bool {
	rl.mu.RLock()
	bucket, exists := rl.tokens[key]
	rl.mu.RUnlock()

	if !exists {
		// Create new bucket
		bucket = &tokenBucket{
			tokens:     rl.maxTokens,
			lastRefill: time.Now(),
		}
		rl.mu.Lock()
		rl.tokens[key] = bucket
		rl.mu.Unlock()
	}

	bucket.mu.Lock()
	defer bucket.mu.Unlock()

	// Refill tokens based on time passed
	now := time.Now()
	elapsed := now.Sub(bucket.lastRefill)
	refillTokens := int(elapsed / rl.window * time.Duration(rl.rate))

	if refillTokens > 0 {
		bucket.tokens = min(bucket.tokens+refillTokens, rl.maxTokens)
		bucket.lastRefill = now
	}

	// Check if tokens available
	if bucket.tokens > 0 {
		bucket.tokens--
		return true
	}

	return false
}

// RateLimitMiddleware creates a rate limiting middleware
func RateLimitMiddleware(limiter *RateLimiter) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Use IP as key (in production, use API key or user ID)
		key := c.ClientIP()

		if !limiter.Allow(key) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "rate limit exceeded",
				"retry_after": limiter.window.Seconds(),
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// RateLimitByAPIKeyMiddleware creates a rate limiting middleware using API key
func RateLimitByAPIKeyMiddleware(limiter *RateLimiter) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Extract API key from Authorization header
		apiKey := c.GetHeader("Authorization")
		if apiKey == "" {
			// Fall back to IP-based limiting
			apiKey = c.ClientIP()
		}

		if !limiter.Allow(apiKey) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "rate limit exceeded",
				"retry_after": limiter.window.Seconds(),
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// cleanup removes old entries periodically
func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(rl.window * 10)
	defer ticker.Stop()

	for range ticker.C {
		rl.mu.Lock()
		now := time.Now()
		for key, bucket := range rl.tokens {
			bucket.mu.Lock()
			if now.Sub(bucket.lastRefill) > rl.window*2 {
				delete(rl.tokens, key)
			}
			bucket.mu.Unlock()
		}
		rl.mu.Unlock()
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
