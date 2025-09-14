package config

import (
	"fmt"
	"os"

	"github.com/joho/godotenv"
)

// Config holds all configuration for the application
type Config struct {
	Database DatabaseConfig
	App      AppConfig
}

// DatabaseConfig holds database configuration
type DatabaseConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	DBName   string
	SSLMode  string
}

// AppConfig holds application configuration
type AppConfig struct {
	Environment string
	Port        string
}

// Load loads configuration from environment variables
func Load() (*Config, error) {
	// Load .env file if it exists
	if err := godotenv.Load(); err != nil {
		// It's okay if .env doesn't exist in production
		fmt.Println("No .env file found")
	}

	config := &Config{
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getEnv("DB_PORT", "5432"),
			User:     getEnv("DB_USER", "postgres"),
			Password: getEnv("DB_PASSWORD", ""),
			DBName:   getEnv("DB_NAME", "supermarket"),
			SSLMode:  getEnv("DB_SSLMODE", "disable"),
		},
		App: AppConfig{
			Environment: getEnv("APP_ENV", "development"),
			Port:        getEnv("APP_PORT", "8080"),
		},
	}

	return config, nil
}

// GetDSN returns the database connection string
func (c *DatabaseConfig) GetDSN() string {
	return fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		c.Host, c.Port, c.User, c.Password, c.DBName, c.SSLMode)
}

// getEnv gets an environment variable with a fallback value
func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}
