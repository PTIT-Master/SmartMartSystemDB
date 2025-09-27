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
	return InitializeWithOptions(cfg, false)
}

// InitializeWithOptions initializes the database connection with options
func InitializeWithOptions(cfg *config.DatabaseConfig, disableQueryLog bool) error {
	var err error

	// Configure GORM with custom logger
	var gormLogger logger.Interface
	if disableQueryLog {
		// Use default logger without query logging
		gormLogger = logger.Default.LogMode(logger.Silent)
	} else {
		// Use custom logger with query logging
		gormLogger = &CustomGormLogger{
			Interface: logger.Default.LogMode(logger.Info),
		}
	}

	gormConfig := &gorm.Config{
		Logger: gormLogger,
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
