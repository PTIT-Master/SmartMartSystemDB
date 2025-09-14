package database

import (
	"fmt"
	"log"

	"github.com/supermarket/models"
	"gorm.io/gorm"
)

// cleanupPartialData removes all seeded data to ensure consistent state
func cleanupPartialData(db *gorm.DB) error {
	log.Println("Cleaning up partial data...")

	return db.Transaction(func(tx *gorm.DB) error {
		// Set search path
		if err := tx.Exec("SET search_path TO supermarket").Error; err != nil {
			return fmt.Errorf("failed to set search path: %w", err)
		}

		// Delete in reverse dependency order
		tables := []string{
			"shelf_layouts",
			"shelf_inventory",
			"warehouse_inventory",
			"stock_transfers",
			"sales_invoice_items",
			"sales_invoices",
			"purchase_order_items",
			"purchase_orders",
			"discount_rules",
			"display_shelves",
			"products",
			"customers",
			"employees",
			"membership_levels",
			"positions",
			"suppliers",
			"product_categories",
			"warehouses",
		}

		for _, table := range tables {
			if err := tx.Exec(fmt.Sprintf("TRUNCATE TABLE %s RESTART IDENTITY CASCADE", table)).Error; err != nil {
				log.Printf("Warning: Could not truncate table %s: %v", table, err)
				// Continue with other tables even if one fails
			}
		}

		log.Println("  ✓ Cleaned up partial data")
		return nil
	})
}

// SeedData seeds initial data into empty tables
func SeedData(db *gorm.DB) error {
	log.Println("Checking if database needs seeding...")

	// Check if data already exists - check multiple tables for consistency
	var productCount, categoryCount, shelfCount int64
	db.Model(&models.Product{}).Count(&productCount)
	db.Model(&models.ProductCategory{}).Count(&categoryCount)
	db.Model(&models.DisplayShelf{}).Count(&shelfCount)

	if productCount > 0 || categoryCount > 0 || shelfCount > 0 {
		// Check if partial seeding occurred
		if productCount > 0 && categoryCount > 0 && shelfCount > 0 {
			log.Println("Database already has complete data. Skipping seed.")
			return nil
		} else {
			log.Println("Database has partial data - cleaning up for consistent seeding...")
			// Clean up partial data to ensure consistency
			if err := cleanupPartialData(db); err != nil {
				return fmt.Errorf("failed to cleanup partial data: %w", err)
			}
		}
	}

	log.Println("Database is empty. Starting seed process...")

	// Use transaction for data integrity
	return db.Transaction(func(tx *gorm.DB) error {
		// Set search path
		if err := tx.Exec("SET search_path TO supermarket").Error; err != nil {
			return fmt.Errorf("failed to set search path: %w", err)
		}

		// 1. Seed Warehouses
		_, err := seedWarehouses(tx)
		if err != nil {
			return fmt.Errorf("failed to seed warehouses: %w", err)
		}

		// 2. Seed Product Categories
		categoryMap, err := seedProductCategories(tx)
		if err != nil {
			return fmt.Errorf("failed to seed product categories: %w", err)
		}

		// 3. Seed Positions
		positionMap, err := seedPositions(tx)
		if err != nil {
			return fmt.Errorf("failed to seed positions: %w", err)
		}

		// 4. Seed Membership Levels
		membershipMap, err := seedMembershipLevels(tx)
		if err != nil {
			return fmt.Errorf("failed to seed membership levels: %w", err)
		}

		// 5. Seed Suppliers
		supplierMap, err := seedSuppliers(tx)
		if err != nil {
			return fmt.Errorf("failed to seed suppliers: %w", err)
		}

		// 6. Seed Employees
		employeeMap, err := seedEmployees(tx, positionMap)
		if err != nil {
			return fmt.Errorf("failed to seed employees: %w", err)
		}

		// 7. Seed Products
		_, err = seedProducts(tx, categoryMap, supplierMap)
		if err != nil {
			return fmt.Errorf("failed to seed products: %w", err)
		}

		// 8. Seed Display Shelves
		_, err = seedDisplayShelves(tx, categoryMap)
		if err != nil {
			return fmt.Errorf("failed to seed display shelves: %w", err)
		}

		// 9. Seed Discount Rules
		if err := seedDiscountRules(tx, categoryMap); err != nil {
			return fmt.Errorf("failed to seed discount rules: %w", err)
		}

		// 10. Seed Customers
		_, err = seedCustomers(tx, membershipMap)
		if err != nil {
			return fmt.Errorf("failed to seed customers: %w", err)
		}

		// 13. Seed Employee Work Hours
		if err := seedEmployeeWorkHours(tx, employeeMap); err != nil {
			return fmt.Errorf("failed to seed employee work hours: %w", err)
		}

		log.Println("✅ Database seeded successfully!")
		return nil
	})
}
