package main

import (
	"flag"
	"fmt"
	"log"

	"github.com/supermarket/config"
	"github.com/supermarket/database"
	"gorm.io/gorm"
)

func main() {
	// Define flags
	force := flag.Bool("force", false, "Force re-seed even if data exists")
	help := flag.Bool("help", false, "Show help message")
	flag.Parse()

	if *help {
		showHelp()
		return
	}

	fmt.Println("🌱 Starting Database Seeding Tool")

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatal("Failed to load configuration:", err)
	}
	fmt.Printf("📊 Database: %s@%s:%s/%s\n\n", cfg.Database.User, cfg.Database.Host, cfg.Database.Port, cfg.Database.DBName)

	// Initialize database connection
	if err := database.Initialize(&cfg.Database); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.Close()

	// Check connection
	if err := database.CheckConnection(database.DB); err != nil {
		log.Fatal("Database connection check failed:", err)
	}

	// Run seed
	if *force {
		fmt.Println("⚠️  Force flag enabled. Clearing existing data...")
		// Clear data in reverse dependency order
		tables := []string{
			"stock_transfers",
			"purchase_order_details",
			"sales_invoice_details",
			"purchase_orders",
			"sales_invoices",
			"employee_work_hours",
			"shelf_inventory",
			"shelf_layout",
			"warehouse_inventory",
			"customers",
			"employees",
			"display_shelves",
			"discount_rules",
			"products",
			"suppliers",
			"membership_levels",
			"positions",
			"product_categories",
			"warehouse",
		}

		for _, table := range tables {
			if err := database.DB.Exec(fmt.Sprintf("DELETE FROM %s", table)).Error; err != nil {
				log.Printf("Warning: Could not clear table %s: %v", table, err)
			} else {
				log.Printf("  Cleared table: %s", table)
			}
		}
		fmt.Println()
	}

	// Seed data
	if err := database.SeedData(database.DB); err != nil {
		log.Fatal("Failed to seed database:", err)
	}

	// Show statistics
	fmt.Println("\n📊 Database Statistics:")
	showTableStats(database.DB)

	fmt.Println("\n✨ Seeding completed successfully!")
	fmt.Println("\n📝 Next Steps:")
	fmt.Println("1. Run the application:")
	fmt.Println("   go run main.go")
	fmt.Println("\n2. Test the connection:")
	fmt.Println("   go run test_connection.go")
}

func showHelp() {
	fmt.Println("Database Seeding Tool")
	fmt.Println("====================")
	fmt.Println("\nUsage:")
	fmt.Println("  go run cmd/seed/main.go [flags]")
	fmt.Println("\nFlags:")
	fmt.Println("  -force    Force re-seed by clearing existing data")
	fmt.Println("  -help     Show this help message")
	fmt.Println("\nExamples:")
	fmt.Println("  # Seed empty database")
	fmt.Println("  go run cmd/seed/main.go")
	fmt.Println("\n  # Force re-seed (clear and re-insert data)")
	fmt.Println("  go run cmd/seed/main.go -force")
}

func showTableStats(db *gorm.DB) {
	type TableStat struct {
		Table string
		Count int64
	}

	tables := []string{
		"warehouse", "product_categories", "positions", "membership_levels",
		"suppliers", "employees", "customers", "products", "display_shelves",
		"discount_rules", "warehouse_inventory", "shelf_layout", "shelf_inventory",
	}

	for _, table := range tables {
		var count int64
		db.Table(table).Count(&count)
		fmt.Printf("  %-25s: %d rows\n", table, count)
	}
}
