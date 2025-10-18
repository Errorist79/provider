package cache

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"

	"github.com/hoodrunio/rpc-gateway/auth-bridge/internal/config"
	"github.com/redis/go-redis/v9"
)

type Cache struct {
	enabled bool
	ttl     time.Duration
	client  *redis.Client
}

func New(cfg config.CacheConfig) (*Cache, error) {
	c := &Cache{
		enabled: cfg.Enabled,
		ttl:     cfg.TTL,
	}

	if !cfg.Enabled {
		return c, nil
	}

	if cfg.Redis.Addr == "" {
		return nil, errors.New("redis address is required when cache is enabled")
	}

	c.client = redis.NewClient(&redis.Options{
		Addr:     cfg.Redis.Addr,
		Password: cfg.Redis.Password,
		DB:       cfg.Redis.DB,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if err := c.client.Ping(ctx).Err(); err != nil {
		return nil, err
	}

	return c, nil
}

func (c *Cache) Close() error {
	if !c.enabled || c.client == nil {
		return nil
	}
	return c.client.Close()
}

func (c *Cache) Enabled() bool {
	return c != nil && c.enabled
}

func (c *Cache) HashKey(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func (c *Cache) Get(ctx context.Context, key string) ([]byte, error) {
	if !c.Enabled() {
		return nil, redis.Nil
	}
	return c.client.Get(ctx, key).Bytes()
}

func (c *Cache) Set(ctx context.Context, key string, value []byte) error {
	if !c.Enabled() {
		return nil
	}
	return c.client.Set(ctx, key, value, c.ttl).Err()
}

func (c *Cache) Delete(ctx context.Context, key string) error {
	if !c.Enabled() {
		return nil
	}
	return c.client.Del(ctx, key).Err()
}
