package database

import (
	"fmt"
	"log"
	"time"

	"github.com/supermarket/config"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var DB *gorm.DB

// Initialize initializes the database connection
func Initialize(cfg *config.DatabaseConfig) error {
	var err error

	// Configure GORM
	gormConfig := &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
		NowFunc: func() time.Time {
			return time.Now().Local()
		},
		QueryFields: true,
	}

	// Open database connection
	DB, err = gorm.Open(postgres.Open(cfg.GetDSN()), gormConfig)
	if err != nil {
		return fmt.Errorf("failed to connect to database: %w", err)
	}

	// Get underlying SQL database
	sqlDB, err := DB.DB()
	if err != nil {
		return fmt.Errorf("failed to get database instance: %w", err)
	}

	// Set connection pool settings
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(100)
	sqlDB.SetConnMaxLifetime(time.Hour)

	// Set search path to supermarket schema
	if err := DB.Exec("SET search_path TO supermarket").Error; err != nil {
		log.Printf("Warning: Could not set search_path to supermarket: %v", err)
	}

	log.Println("Database connection established successfully")
	return nil
}

// GetDB returns the database instance
func GetDB() *gorm.DB {
	return DB
}

// Close closes the database connection
func Close() error {
	sqlDB, err := DB.DB()
	if err != nil {
		return err
	}
	return sqlDB.Close()
}
