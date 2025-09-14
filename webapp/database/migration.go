package database

import (
	"fmt"
	"log"
	"strings"

	"github.com/supermarket/models"
	"gorm.io/gorm"
)

// AutoMigrate runs auto migration for all models
func AutoMigrate(db *gorm.DB) error {
	log.Println("Starting GORM AutoMigrate...")

	// Set search path to supermarket schema
	if err := db.Exec("CREATE SCHEMA IF NOT EXISTS supermarket").Error; err != nil {
		log.Printf("Warning: Could not create schema: %v", err)
	}

	if err := db.Exec("SET search_path TO supermarket").Error; err != nil {
		return fmt.Errorf("failed to set search path: %w", err)
	}

	// Get all models in dependency order
	allModels := models.AllModels()

	// Use standard GORM AutoMigrate with proper configuration
	// Configure GORM to handle foreign keys properly
	db = db.Set("gorm:table_options", "")

	// Migrate each model individually in dependency order
	log.Println("Migrating tables in dependency order...")
	for i, model := range allModels {
		// Get table name using migrator
		stmt := &gorm.Statement{DB: db}
		if err := stmt.Parse(model); err != nil {
			log.Printf("  ⚠ Warning: Could not parse model %T: %v", model, err)
			continue
		}
		tableName := stmt.Schema.Table

		// Check if table exists
		var exists bool
		db.Raw("SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'supermarket' AND table_name = ?)", tableName).Scan(&exists)

		if !exists {
			// AutoMigrate will create the table with proper foreign keys
			// Since we're going in dependency order, referenced tables should exist
			if err := db.AutoMigrate(model); err != nil {
				// If foreign key error, try without associations
				if strings.Contains(err.Error(), "does not exist") || strings.Contains(err.Error(), "42P01") {
					log.Printf("  ⚠ Retrying without associations for %T", model)
					// Create basic table structure
					if err2 := db.Migrator().CreateTable(model); err2 != nil {
						log.Printf("  ⚠ Warning: Could not create table for %T: %v", model, err2)
						// Continue with other tables
						continue
					}
				} else {
					return fmt.Errorf("failed to migrate model %d (%T): %w", i+1, model, err)
				}
			}
			log.Printf("  ✓ Created table: %s", tableName)
		} else {
			// Table exists, update it
			if err := db.AutoMigrate(model); err != nil {
				log.Printf("  ⚠ Warning updating table %s: %v", tableName, err)
			} else {
				log.Printf("  ✓ Updated table: %s", tableName)
			}
		}
	}

	// Add custom constraints that GORM doesn't handle
	log.Println("Adding custom constraints...")
	if err := AddCustomConstraints(db); err != nil {
		log.Printf("Warning: Some custom constraints could not be added: %v", err)
	}

	// Create indexes
	log.Println("Creating indexes...")
	if err := CreateIndexes(db); err != nil {
		log.Printf("Warning: Some indexes could not be created: %v", err)
	}

	log.Println("GORM AutoMigrate completed successfully")
	return nil
}

// CheckConnection verifies the database connection and schema
func CheckConnection(db *gorm.DB) error {
	// Check if we can connect to the database
	sqlDB, err := db.DB()
	if err != nil {
		return fmt.Errorf("failed to get database instance: %w", err)
	}

	// Ping the database
	if err := sqlDB.Ping(); err != nil {
		return fmt.Errorf("failed to ping database: %w", err)
	}

	// Check if supermarket schema exists
	var schemaExists bool
	err = db.Raw("SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name = 'supermarket')").Scan(&schemaExists).Error
	if err != nil {
		return fmt.Errorf("failed to check schema: %w", err)
	}

	if !schemaExists {
		log.Println("Warning: 'supermarket' schema does not exist. Please run the SQL schema script first.")
		// You might want to create the schema here or return an error
		// For now, we'll try to create it
		if err := db.Exec("CREATE SCHEMA IF NOT EXISTS supermarket").Error; err != nil {
			return fmt.Errorf("failed to create schema: %w", err)
		}
		log.Println("Created 'supermarket' schema")
	}

	return nil
}

// AddCustomConstraints adds database constraints that GORM doesn't handle automatically
func AddCustomConstraints(db *gorm.DB) error {
	constraints := []struct {
		name  string
		query string
	}{
		// Check constraint for product prices
		{"check_price", "ALTER TABLE products ADD CONSTRAINT check_price CHECK (selling_price > import_price)"},

		// Unique constraints for compound keys
		{"unique_batch", "ALTER TABLE warehouse_inventory ADD CONSTRAINT unique_batch UNIQUE (warehouse_id, product_id, batch_code)"},
		{"unique_shelf_position", "ALTER TABLE shelf_layout ADD CONSTRAINT unique_shelf_position UNIQUE (shelf_id, position_code)"},
		{"unique_shelf_product", "ALTER TABLE shelf_layout ADD CONSTRAINT unique_shelf_product UNIQUE (shelf_id, product_id)"},
		{"unique_shelf_product_inv", "ALTER TABLE shelf_inventory ADD CONSTRAINT unique_shelf_product_inv UNIQUE (shelf_id, product_id)"},
		{"unique_employee_date", "ALTER TABLE employee_work_hours ADD CONSTRAINT unique_employee_date UNIQUE (employee_id, work_date)"},
		{"unique_category_days", "ALTER TABLE discount_rules ADD CONSTRAINT unique_category_days UNIQUE (category_id, days_before_expiry)"},
	}

	for _, c := range constraints {
		if err := db.Exec(c.query).Error; err != nil {
			// Check if constraint already exists (PostgreSQL error code 42710)
			if !strings.Contains(err.Error(), "already exists") && !strings.Contains(err.Error(), "42710") {
				log.Printf("  ⚠ Failed to add constraint %s: %v", c.name, err)
			}
		} else {
			log.Printf("  ✓ Added constraint: %s", c.name)
		}
	}

	return nil
}

// CreateIndexes creates performance indexes
func CreateIndexes(db *gorm.DB) error {
	indexes := []struct {
		name  string
		query string
	}{
		// Product indexes
		{"idx_products_category", "CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id)"},
		{"idx_products_supplier", "CREATE INDEX IF NOT EXISTS idx_products_supplier ON products(supplier_id)"},

		// Inventory indexes
		{"idx_warehouse_inv_product", "CREATE INDEX IF NOT EXISTS idx_warehouse_inv_product ON warehouse_inventory(product_id)"},
		{"idx_warehouse_inv_expiry", "CREATE INDEX IF NOT EXISTS idx_warehouse_inv_expiry ON warehouse_inventory(expiry_date)"},
		{"idx_shelf_inv_product", "CREATE INDEX IF NOT EXISTS idx_shelf_inv_product ON shelf_inventory(product_id)"},
		{"idx_shelf_inv_quantity", "CREATE INDEX IF NOT EXISTS idx_shelf_inv_quantity ON shelf_inventory(current_quantity)"},

		// Sales indexes
		{"idx_sales_invoice_date", "CREATE INDEX IF NOT EXISTS idx_sales_invoice_date ON sales_invoices(invoice_date)"},
		{"idx_sales_invoice_customer", "CREATE INDEX IF NOT EXISTS idx_sales_invoice_customer ON sales_invoices(customer_id)"},
		{"idx_sales_invoice_employee", "CREATE INDEX IF NOT EXISTS idx_sales_invoice_employee ON sales_invoices(employee_id)"},
		{"idx_sales_details_product", "CREATE INDEX IF NOT EXISTS idx_sales_details_product ON sales_invoice_details(product_id)"},

		// Employee and customer indexes
		{"idx_employee_position", "CREATE INDEX IF NOT EXISTS idx_employee_position ON employees(position_id)"},
		{"idx_customer_membership", "CREATE INDEX IF NOT EXISTS idx_customer_membership ON customers(membership_level_id)"},
		{"idx_customer_spending", "CREATE INDEX IF NOT EXISTS idx_customer_spending ON customers(total_spending)"},
	}

	successCount := 0
	for _, idx := range indexes {
		if err := db.Exec(idx.query).Error; err != nil {
			log.Printf("  ⚠ Failed to create index %s: %v", idx.name, err)
		} else {
			log.Printf("  ✓ Created index: %s", idx.name)
			successCount++
		}
	}

	if successCount > 0 {
		log.Printf("Successfully created %d indexes", successCount)
	}

	return nil
}

// SyncIndexes is now deprecated - use CreateIndexes instead
func SyncIndexes(db *gorm.DB) error {
	return CreateIndexes(db)
}
