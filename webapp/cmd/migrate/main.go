package main

import (
	"flag"
	"fmt"
	"log"

	"github.com/supermarket/config"
	"github.com/supermarket/database"
)

func main() {
	// Command line flags
	var (
		drop   = flag.Bool("drop", false, "Drop all tables before migration")
		schema = flag.Bool("schema", false, "Create schema only (no migration)")
		help   = flag.Bool("help", false, "Show help")
	)

	flag.Parse()

	if *help {
		showHelp()
		return
	}

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	fmt.Println("🚀 Starting Database Migration Tool")
	fmt.Printf("📊 Database: %s@%s:%s/%s\n",
		cfg.Database.User, cfg.Database.Host, cfg.Database.Port, cfg.Database.DBName)

	// Initialize database connection
	if err := database.Initialize(&cfg.Database); err != nil {
		log.Fatalf("❌ Failed to initialize database: %v", err)
	}
	defer database.Close()

	// Check connection
	if err := database.CheckConnection(database.DB); err != nil {
		log.Printf("⚠️  Warning: %v", err)
	}

	// Drop tables if requested
	if *drop {
		fmt.Println("⚠️  Dropping all tables in supermarket schema...")
		if err := dropAllTables(); err != nil {
			log.Fatalf("❌ Failed to drop tables: %v", err)
		}
		fmt.Println("✅ All tables dropped")
	}

	// Create schema only if requested
	if *schema {
		fmt.Println("📁 Creating schema only...")
		if err := database.DB.Exec("CREATE SCHEMA IF NOT EXISTS supermarket").Error; err != nil {
			log.Fatalf("❌ Failed to create schema: %v", err)
		}
		if err := database.DB.Exec("SET search_path TO supermarket").Error; err != nil {
			log.Fatalf("❌ Failed to set search path: %v", err)
		}
		fmt.Println("✅ Schema created successfully")
		return
	}

	// Run AutoMigrate
	fmt.Println("🔄 Running GORM AutoMigrate...")
	if err := database.AutoMigrate(database.DB); err != nil {
		log.Fatalf("❌ Failed to run migration: %v", err)
	}

	fmt.Println("✅ Migration completed successfully!")

	// Show table count
	var tableCount int64
	err = database.DB.Raw(`
		SELECT COUNT(*) 
		FROM information_schema.tables 
		WHERE table_schema = 'supermarket' 
		AND table_type = 'BASE TABLE'
	`).Scan(&tableCount).Error

	if err == nil {
		fmt.Printf("📊 Total tables created: %d\n", tableCount)
	}

	showPostMigrationInfo()
}

func dropAllTables() error {
	// Get all table names in supermarket schema
	var tables []string
	err := database.DB.Raw(`
		SELECT table_name 
		FROM information_schema.tables 
		WHERE table_schema = 'supermarket' 
		AND table_type = 'BASE TABLE'
	`).Scan(&tables).Error

	if err != nil {
		return err
	}

	// Disable foreign key checks temporarily
	if err := database.DB.Exec("SET session_replication_role = 'replica'").Error; err != nil {
		log.Printf("Warning: Could not disable FK checks: %v", err)
	}

	// Drop each table
	for _, table := range tables {
		fmt.Printf("  Dropping table: %s\n", table)
		if err := database.DB.Exec(fmt.Sprintf("DROP TABLE IF EXISTS supermarket.%s CASCADE", table)).Error; err != nil {
			log.Printf("  Warning: Failed to drop %s: %v", table, err)
		}
	}

	// Re-enable foreign key checks
	if err := database.DB.Exec("SET session_replication_role = 'origin'").Error; err != nil {
		log.Printf("Warning: Could not re-enable FK checks: %v", err)
	}

	return nil
}

func showHelp() {
	fmt.Println(`
Database Migration Tool for Supermarket Management System

Usage:
  go run cmd/migrate/main.go [options]

Options:
  -drop     Drop all tables before migration (WARNING: Data loss!)
  -schema   Create schema only, no table migration
  -help     Show this help message

Examples:
  # Run migration (create/update tables)
  go run cmd/migrate/main.go

  # Drop all tables and recreate
  go run cmd/migrate/main.go -drop

  # Create schema only
  go run cmd/migrate/main.go -schema

Environment:
  Requires .env file or environment variables for database configuration:
  - DB_HOST
  - DB_PORT
  - DB_USER
  - DB_PASSWORD
  - DB_NAME
`)
}

func showPostMigrationInfo() {
	fmt.Println(`
📝 Next Steps:
1. Insert sample data:
   psql -U postgres -d supermarket -f ../sql/04_insert_sample_data.sql

2. Or use the application to add data through API

3. Test the connection:
   go run test_connection.go

Note: Database triggers for validation and data processing are 
automatically created during migration. These triggers handle:
- Price validation, inventory management, customer metrics
- Invoice calculations, work hours, expiry discounts
- Audit trails and timestamp management

For additional SQL functions, consider running scripts in ../sql/ directory.
`)
}
