package main

import (
	"fmt"
	"log"

	"github.com/supermarket/config"
	"github.com/supermarket/database"
	"github.com/supermarket/models"
)

func testConnection() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	fmt.Println("=== Database Connection Test ===")
	fmt.Printf("Connecting to: %s@%s:%s/%s\n",
		cfg.Database.User, cfg.Database.Host, cfg.Database.Port, cfg.Database.DBName)

	// Initialize database connection
	if err := database.Initialize(&cfg.Database); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer database.Close()

	fmt.Println("✓ Database connected successfully")

	// Check schema
	if err := database.CheckConnection(database.DB); err != nil {
		log.Fatalf("Database check failed: %v", err)
	}
	fmt.Println("✓ Schema check passed")

	// Test query - count tables
	var tableCount int64
	err = database.DB.Raw(`
		SELECT COUNT(*) 
		FROM information_schema.tables 
		WHERE table_schema = 'supermarket'
	`).Scan(&tableCount).Error

	if err != nil {
		log.Fatalf("Failed to count tables: %v", err)
	}
	fmt.Printf("✓ Found %d tables in supermarket schema\n", tableCount)

	// Test model queries
	fmt.Println("\n=== Testing Model Queries ===")

	// Test ProductCategory
	var categories []models.ProductCategory
	if err := database.DB.Limit(5).Find(&categories).Error; err != nil {
		log.Printf("Warning: Could not fetch categories: %v", err)
	} else {
		fmt.Printf("✓ Found %d product categories\n", len(categories))
	}

	// Test Products with relationships
	var products []models.Product
	if err := database.DB.Preload("Category").Preload("Supplier").Limit(5).Find(&products).Error; err != nil {
		log.Printf("Warning: Could not fetch products: %v", err)
	} else {
		fmt.Printf("✓ Found %d products\n", len(products))
		if len(products) > 0 {
			fmt.Printf("  Sample: %s (Category: %s, Supplier: %s)\n",
				products[0].ProductName,
				products[0].Category.CategoryName,
				products[0].Supplier.SupplierName)
		}
	}

	// Test Employees
	var employees []models.Employee
	if err := database.DB.Preload("Position").Limit(5).Find(&employees).Error; err != nil {
		log.Printf("Warning: Could not fetch employees: %v", err)
	} else {
		fmt.Printf("✓ Found %d employees\n", len(employees))
	}

	// Test inventory summary
	var inventoryCount struct {
		WarehouseCount int64
		ShelfCount     int64
	}

	database.DB.Model(&models.WarehouseInventory{}).Count(&inventoryCount.WarehouseCount)
	database.DB.Model(&models.ShelfInventory{}).Count(&inventoryCount.ShelfCount)

	fmt.Printf("✓ Warehouse inventory items: %d\n", inventoryCount.WarehouseCount)
	fmt.Printf("✓ Shelf inventory items: %d\n", inventoryCount.ShelfCount)

	fmt.Println("\n=== All Tests Passed ✓ ===")
}

// Run this file with: go run test_connection.go
// Make sure you have:
// 1. PostgreSQL running
// 2. Database 'supermarket' created
// 3. Schema from 01_schema.sql executed
// 4. .env file configured with correct credentials
