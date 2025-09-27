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

		// Clear data using DELETE statements for better control
		// Clear in reverse dependency order
		clearStatements := []string{
			"DELETE FROM employee_work_hours",
			"DELETE FROM shelf_batch_inventory",
			"DELETE FROM shelf_layout",
			"DELETE FROM warehouse_inventory",
			"DELETE FROM stock_transfers",
			"DELETE FROM sales_invoice_details",
			"DELETE FROM sales_invoices",
			"DELETE FROM purchase_order_details",
			"DELETE FROM purchase_orders",
			"DELETE FROM discount_rules",
			"DELETE FROM customers",
			"DELETE FROM employees",
			// Only clear master data if we're doing full reseed
			"TRUNCATE TABLE display_shelves RESTART IDENTITY CASCADE",
			"TRUNCATE TABLE products RESTART IDENTITY CASCADE",
			"TRUNCATE TABLE membership_levels RESTART IDENTITY CASCADE",
			"TRUNCATE TABLE positions RESTART IDENTITY CASCADE",
			"TRUNCATE TABLE suppliers RESTART IDENTITY CASCADE",
			"TRUNCATE TABLE product_categories RESTART IDENTITY CASCADE",
			"TRUNCATE TABLE warehouse RESTART IDENTITY CASCADE",
		}

		for _, stmt := range clearStatements {
			if err := tx.Exec(stmt).Error; err != nil {
				log.Printf("Warning: Could not execute %s: %v", stmt, err)
				// Continue with other statements even if one fails
			} else {
				log.Printf("  ✓ Executed: %s", stmt)
			}
		}

		log.Println("  ✓ Cleaned up partial data")
		return nil
	})
}

// SeedData seeds initial data into empty tables
func SeedData(db *gorm.DB) error {
	log.Println("Checking if database needs seeding...")

	// Check if data already exists - check multiple essential tables for consistency
	var productCount, categoryCount, shelfCount, employeeCount, customerCount int64
	db.Model(&models.Product{}).Count(&productCount)
	db.Model(&models.ProductCategory{}).Count(&categoryCount)
	db.Model(&models.DisplayShelf{}).Count(&shelfCount)
	db.Model(&models.Employee{}).Count(&employeeCount)
	db.Model(&models.Customer{}).Count(&customerCount)

	if productCount > 0 || categoryCount > 0 || shelfCount > 0 || employeeCount > 0 || customerCount > 0 {
		// Check if complete seeding occurred - all essential tables should have data
		if productCount > 0 && categoryCount > 0 && shelfCount > 0 && employeeCount > 0 && customerCount > 0 {
			log.Printf("Database already has complete data (Products: %d, Categories: %d, Shelves: %d, Employees: %d, Customers: %d). Skipping seed.",
				productCount, categoryCount, shelfCount, employeeCount, customerCount)
			return nil
		} else {
			log.Printf("Database has incomplete data (Products: %d, Categories: %d, Shelves: %d, Employees: %d, Customers: %d) - cleaning up for consistent seeding...",
				productCount, categoryCount, shelfCount, employeeCount, customerCount)
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

		// 14. Seed Dashboard Test Data
		if err := seedDashboardTestData(tx); err != nil {
			return fmt.Errorf("failed to seed dashboard test data: %w", err)
		}

		log.Println("✅ Database seeded successfully!")
		return nil
	})
}
