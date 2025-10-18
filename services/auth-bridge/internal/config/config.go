package config

import (
	"fmt"
	"strings"
	"time"

	"github.com/spf13/viper"
)

type Config struct {
	Server ServerConfig
	Unkey  UnkeyConfig
	Cache  CacheConfig
}

type ServerConfig struct {
	Port            string
	ReadTimeout     time.Duration
	WriteTimeout    time.Duration
	ShutdownTimeout time.Duration
}

type UnkeyConfig struct {
	BaseURL        string
	APIKey         string
	RequestTimeout time.Duration
}

type CacheConfig struct {
	Enabled bool
	TTL     time.Duration
	Redis   RedisConfig
}

type RedisConfig struct {
	Addr     string
	Password string
	DB       int
}

func Load() (*Config, error) {
	viper.SetConfigName("config")
	viper.SetConfigType("yaml")
	viper.AddConfigPath(".")
	viper.AddConfigPath("./config")

	viper.SetEnvPrefix("AUTH_BRIDGE")
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	viper.AutomaticEnv()

	setDefaults()

	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, fmt.Errorf("failed to read config file: %w", err)
		}
	}

	cfg := &Config{}
	if err := viper.Unmarshal(cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	if cfg.Unkey.APIKey == "" {
		return nil, fmt.Errorf("AUTH_BRIDGE_UNKEY_API_KEY is required")
	}

	return cfg, nil
}

func setDefaults() {
	viper.SetDefault("server.port", "8081")
	viper.SetDefault("server.readtimeout", 5*time.Second)
	viper.SetDefault("server.writetimeout", 5*time.Second)
	viper.SetDefault("server.shutdowntimeout", 10*time.Second)

	viper.SetDefault("unkey.baseurl", "http://unkey:8080")
	viper.SetDefault("unkey.requesttimeout", 3*time.Second)

	viper.SetDefault("cache.enabled", true)
	viper.SetDefault("cache.ttl", 60*time.Second)
	viper.SetDefault("cache.redis.addr", "redis:6379")
	viper.SetDefault("cache.redis.db", 0)
}
