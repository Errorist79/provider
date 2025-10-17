package config

import (
	"fmt"
	"log"
	"strings"

	"github.com/spf13/viper"
)

type Config struct {
	Server     ServerConfig
	ClickHouse ClickHouseConfig
	PostgreSQL PostgreSQLConfig
	Redis      RedisConfig
	Auth       AuthConfig
	Logging    LoggingConfig
}

type ServerConfig struct {
	Port            string
	Environment     string
	ReadTimeout     int
	WriteTimeout    int
	ShutdownTimeout int
}

type ClickHouseConfig struct {
	Host     string
	Port     int
	Database string
	Username string
	Password string
	Debug    bool
}

type PostgreSQLConfig struct {
	Host     string
	Port     int
	Database string
	Username string
	Password string
	SSLMode  string
	MaxConns int32
	MinConns int32
}

type RedisConfig struct {
	Host     string
	Port     int
	Password string
	DB       int
	Enabled  bool
}

type AuthConfig struct {
	Enabled bool
	// Simple API key auth for Phase 6
	AdminAPIKey string
}

type LoggingConfig struct {
	Level      string
	Format     string // json or console
	OutputPath string
}

func Load() (*Config, error) {
	viper.SetConfigName("config")
	viper.SetConfigType("yaml")
	viper.AddConfigPath(".")
	viper.AddConfigPath("./config")
	viper.AddConfigPath("/etc/reporting-api")

	// Environment variables override
	viper.SetEnvPrefix("REPORTING_API")
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	viper.AutomaticEnv()

	// Default values
	setDefaults()

	// Read config file (optional)
	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, fmt.Errorf("failed to read config file: %w", err)
		}
		log.Println("No config file found, using environment variables and defaults")
	}

	var config Config
	if err := viper.Unmarshal(&config); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	return &config, nil
}

func setDefaults() {
	// Server defaults
	viper.SetDefault("server.port", "8080")
	viper.SetDefault("server.environment", "development")
	viper.SetDefault("server.readtimeout", 30)
	viper.SetDefault("server.writetimeout", 30)
	viper.SetDefault("server.shutdowntimeout", 10)

	// ClickHouse defaults
	viper.SetDefault("clickhouse.host", "localhost")
	viper.SetDefault("clickhouse.port", 9000)
	viper.SetDefault("clickhouse.database", "telemetry")
	viper.SetDefault("clickhouse.username", "default")
	viper.SetDefault("clickhouse.password", "")
	viper.SetDefault("clickhouse.debug", false)

	// PostgreSQL defaults
	viper.SetDefault("postgresql.host", "localhost")
	viper.SetDefault("postgresql.port", 5432)
	viper.SetDefault("postgresql.database", "rpc_gateway")
	viper.SetDefault("postgresql.username", "rpcuser")
	viper.SetDefault("postgresql.password", "rpcpass")
	viper.SetDefault("postgresql.sslmode", "disable")
	viper.SetDefault("postgresql.maxconns", 10)
	viper.SetDefault("postgresql.minconns", 2)

	// Redis defaults
	viper.SetDefault("redis.host", "localhost")
	viper.SetDefault("redis.port", 6379)
	viper.SetDefault("redis.password", "")
	viper.SetDefault("redis.db", 0)
	viper.SetDefault("redis.enabled", false)

	// Auth defaults
	viper.SetDefault("auth.enabled", false)
	viper.SetDefault("auth.adminapikey", "")

	// Logging defaults
	viper.SetDefault("logging.level", "info")
	viper.SetDefault("logging.format", "json")
	viper.SetDefault("logging.outputpath", "stdout")
}

func (c *Config) Validate() error {
	if c.Server.Port == "" {
		return fmt.Errorf("server port is required")
	}

	if c.ClickHouse.Host == "" {
		return fmt.Errorf("clickhouse host is required")
	}

	if c.PostgreSQL.Host == "" {
		return fmt.Errorf("postgresql host is required")
	}

	return nil
}
