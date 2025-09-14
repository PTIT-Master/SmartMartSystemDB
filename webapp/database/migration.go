package database

import (
	"fmt"
	"io/ioutil"
	"log"
	"path/filepath"
	"runtime"
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

	// First pass: Create all tables WITHOUT foreign keys
	log.Println("Creating tables without foreign keys...")
	migrator := db.Migrator()

	for _, model := range allModels {
		tableName := migrator.CurrentDatabase()
		stmt := &gorm.Statement{DB: db}
		if err := stmt.Parse(model); err == nil {
			tableName = stmt.Schema.Table
		}

		if !migrator.HasTable(model) {
			// Create table without foreign keys using raw SQL to avoid GORM's auto FK creation
			// We'll use GORM's CreateTable but without associations
			if err := migrator.CreateTable(model); err != nil {
				log.Printf("  ⚠ Warning: Could not create table %s: %v", tableName, err)
				continue
			}
			log.Printf("  ✓ Created table: %s", tableName)
		} else {
			log.Printf("  ✓ Table already exists: %s", tableName)
		}
	}

	// Second pass: Create foreign key constraints manually
	log.Println("Creating foreign key constraints...")
	if err := CreateForeignKeys(db); err != nil {
		log.Printf("Warning: Some foreign keys could not be created: %v", err)
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

	// Create triggers
	log.Println("Creating database triggers...")
	if err := CreateTriggers(db); err != nil {
		log.Printf("Warning: Some triggers could not be created: %v", err)
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

// CreateForeignKeys creates all foreign key constraints
func CreateForeignKeys(db *gorm.DB) error {
	foreignKeys := []struct {
		table     string
		name      string
		column    string
		refTable  string
		refColumn string
	}{
		// Product relationships
		{"products", "fk_products_category", "category_id", "product_categories", "category_id"},
		{"products", "fk_products_supplier", "supplier_id", "suppliers", "supplier_id"},

		// Discount rules
		{"discount_rules", "fk_discount_rules_category", "category_id", "product_categories", "category_id"},

		// Display shelves
		{"display_shelves", "fk_display_shelves_category", "category_id", "product_categories", "category_id"},

		// Shelf layout
		{"shelf_layout", "fk_shelf_layout_shelf", "shelf_id", "display_shelves", "shelf_id"},
		{"shelf_layout", "fk_shelf_layout_product", "product_id", "products", "product_id"},

		// Shelf inventory
		{"shelf_inventory", "fk_shelf_inventory_shelf", "shelf_id", "display_shelves", "shelf_id"},
		{"shelf_inventory", "fk_shelf_inventory_product", "product_id", "products", "product_id"},

		// Warehouse inventory
		{"warehouse_inventory", "fk_warehouse_inventory_warehouse", "warehouse_id", "warehouse", "warehouse_id"},
		{"warehouse_inventory", "fk_warehouse_inventory_product", "product_id", "products", "product_id"},

		// Employees
		{"employees", "fk_employees_position", "position_id", "positions", "position_id"},

		// Employee work hours
		{"employee_work_hours", "fk_employee_work_hours_employee", "employee_id", "employees", "employee_id"},

		// Customers
		{"customers", "fk_customers_membership_level", "membership_level_id", "membership_levels", "level_id"},

		// Sales invoices
		{"sales_invoices", "fk_sales_invoices_customer", "customer_id", "customers", "customer_id"},
		{"sales_invoices", "fk_sales_invoices_employee", "employee_id", "employees", "employee_id"},

		// Sales invoice details
		{"sales_invoice_details", "fk_sales_invoice_details_invoice", "invoice_id", "sales_invoices", "invoice_id"},
		{"sales_invoice_details", "fk_sales_invoice_details_product", "product_id", "products", "product_id"},

		// Purchase orders
		{"purchase_orders", "fk_purchase_orders_supplier", "supplier_id", "suppliers", "supplier_id"},
		{"purchase_orders", "fk_purchase_orders_employee", "employee_id", "employees", "employee_id"},

		// Purchase order details
		{"purchase_order_details", "fk_purchase_order_details_order", "order_id", "purchase_orders", "order_id"},
		{"purchase_order_details", "fk_purchase_order_details_product", "product_id", "products", "product_id"},

		// Stock transfers
		{"stock_transfers", "fk_stock_transfers_product", "product_id", "products", "product_id"},
		{"stock_transfers", "fk_stock_transfers_from_warehouse", "from_warehouse_id", "warehouse", "warehouse_id"},
		{"stock_transfers", "fk_stock_transfers_to_shelf", "to_shelf_id", "display_shelves", "shelf_id"},
		{"stock_transfers", "fk_stock_transfers_employee", "employee_id", "employees", "employee_id"},
	}

	for _, fk := range foreignKeys {
		// Check if foreign key already exists
		var count int64
		db.Raw(`
			SELECT COUNT(*) FROM information_schema.table_constraints 
			WHERE constraint_type = 'FOREIGN KEY' 
			AND table_schema = 'supermarket' 
			AND table_name = ? 
			AND constraint_name = ?
		`, fk.table, fk.name).Scan(&count)

		if count > 0 {
			log.Printf("  ✓ Foreign key already exists: %s", fk.name)
			continue
		}

		// Create foreign key
		query := fmt.Sprintf(
			"ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s(%s)",
			fk.table, fk.name, fk.column, fk.refTable, fk.refColumn,
		)

		if err := db.Exec(query).Error; err != nil {
			// Allow null references for optional foreign keys
			if strings.Contains(fk.name, "customer") || strings.Contains(fk.name, "membership") {
				query = fmt.Sprintf(
					"ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s(%s) ON DELETE SET NULL",
					fk.table, fk.name, fk.column, fk.refTable, fk.refColumn,
				)
				if err := db.Exec(query).Error; err != nil {
					log.Printf("  ⚠ Failed to create foreign key %s: %v", fk.name, err)
				}
			} else {
				log.Printf("  ⚠ Failed to create foreign key %s: %v", fk.name, err)
			}
		} else {
			log.Printf("  ✓ Created foreign key: %s", fk.name)
		}
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

// CreateTriggers creates all database triggers for the supermarket system
func CreateTriggers(db *gorm.DB) error {
	triggerFiles := []string{
		"triggers.sql",
		"create_triggers.sql",
	}

	successCount := 0
	for _, filename := range triggerFiles {
		if err := executeSQLFile(db, filename); err != nil {
			log.Printf("  ⚠ Failed to execute %s: %v", filename, err)
		} else {
			log.Printf("  ✓ Executed trigger file: %s", filename)
			successCount++
		}
	}

	if successCount > 0 {
		log.Printf("Successfully created triggers from %d files", successCount)
	}

	return nil
}

// executeSQLFile executes a SQL file in the database directory
func executeSQLFile(db *gorm.DB, filename string) error {
	// Get the directory of the current file (migration.go)
	_, currentFile, _, _ := runtime.Caller(0)
	dbDir := filepath.Dir(currentFile)
	sqlFilePath := filepath.Join(dbDir, filename)

	// Read the SQL file
	sqlBytes, err := ioutil.ReadFile(sqlFilePath)
	if err != nil {
		return fmt.Errorf("failed to read SQL file %s: %w", filename, err)
	}

	sqlContent := string(sqlBytes)

	// For PostgreSQL files with functions/triggers, execute the entire content at once
	// This avoids issues with dollar-quoted strings being split incorrectly
	if err := db.Exec(sqlContent).Error; err != nil {
		return fmt.Errorf("failed to execute SQL file %s: %w", filename, err)
	}

	return nil
}
