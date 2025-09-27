package main

import (
	"flag"
	"fmt"
	"log"
	"math/rand"
	"strings"
	"time"

	"github.com/supermarket/config"
	"github.com/supermarket/database"
	"github.com/supermarket/models"
	"gorm.io/gorm"
)

func main() {
	// Parse command line flags
	var (
		startDate  = flag.String("start", "2025-09-01", "Simulation start date (YYYY-MM-DD)")
		endDate    = flag.String("end", "2025-09-24", "Simulation end date (YYYY-MM-DD)")
		clear      = flag.Bool("clear", false, "Clear existing simulation data before running")
		seed       = flag.Bool("seed", false, "Run initial seed if database is empty")
		noQueryLog = flag.Bool("no-query-log", false, "Disable query logging during simulation")
	)
	flag.Parse()

	// Seed random number generator
	rand.Seed(time.Now().UnixNano())

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Connect to database
	if err := database.InitializeWithOptions(&cfg.Database, *noQueryLog); err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	db := database.GetDB()

	sqlDB, err := db.DB()
	if err != nil {
		log.Fatalf("Failed to get sql.DB: %v", err)
	}
	defer sqlDB.Close()

	log.Println("✅ Connected to database successfully")

	// Set search path
	if err := db.Exec("SET search_path TO supermarket").Error; err != nil {
		log.Printf("Warning: Could not set search path: %v", err)
	}

	// Check if initial seed is needed
	if *seed {
		var productCount int64
		db.Model(&models.Product{}).Count(&productCount)

		if productCount == 0 {
			log.Println("Database is empty, running initial seed...")
			if err := database.SeedData(db); err != nil {
				log.Fatalf("Failed to seed initial data: %v", err)
			}
			log.Println("✅ Initial seed completed")
		} else {
			log.Printf("Database already has %d products, skipping seed", productCount)
		}
	}

	// Clear existing simulation data if requested
	if *clear {
		if err := clearSimulationData(db, *startDate, *endDate); err != nil {
			log.Fatalf("Failed to clear simulation data: %v", err)
		}
		log.Println("✅ Cleared existing simulation data")
	}

	// Parse dates
	start, err := time.Parse("2006-01-02", *startDate)
	if err != nil {
		log.Fatalf("Invalid start date: %v", err)
	}

	end, err := time.Parse("2006-01-02", *endDate)
	if err != nil {
		log.Fatalf("Invalid end date: %v", err)
	}

	// Validate date range
	if end.Before(start) {
		log.Fatalf("End date must be after start date")
	}

	// Check if data already exists
	if !*clear {
		if hasExistingData(db, start, end) {
			log.Println("⚠️  Warning: Simulation data already exists for this period.")
			log.Println("   Use -clear flag to remove existing data before running.")
		}
	}

	// Run simulation
	log.Printf("Starting simulation from %s to %s", start.Format("2006-01-02"), end.Format("2006-01-02"))

	if err := database.RunSimulation(db, start, end); err != nil {
		log.Fatalf("Simulation failed: %v", err)
	}

	log.Println("✅ Simulation completed successfully!")
	printStatistics(db, start, end)
}

// clearSimulationData removes all simulation-generated data for the specified period
func clearSimulationData(db *gorm.DB, startDate, endDate string) error {
	return db.Transaction(func(tx *gorm.DB) error {
		// Set search path
		if err := tx.Exec("SET search_path TO supermarket").Error; err != nil {
			return fmt.Errorf("failed to set search path: %w", err)
		}

		// Clear ALL simulation-generated transactional data
		// This preserves master data (suppliers, warehouses, products, etc.)

		// 1. Clear sales data
		if err := tx.Exec(`TRUNCATE TABLE sales_invoice_details RESTART IDENTITY`).Error; err != nil {
			log.Printf("Warning: Could not truncate invoice details: %v", err)
		}
		if err := tx.Exec(`TRUNCATE TABLE sales_invoices RESTART IDENTITY CASCADE`).Error; err != nil {
			log.Printf("Warning: Could not truncate invoices: %v", err)
		}

		// 2. Clear stock transfers
		if err := tx.Exec(`TRUNCATE TABLE stock_transfers RESTART IDENTITY CASCADE`).Error; err != nil {
			log.Printf("Warning: Could not truncate transfers: %v", err)
		}

		// 3. Clear purchase orders
		if err := tx.Exec(`TRUNCATE TABLE purchase_order_details RESTART IDENTITY`).Error; err != nil {
			log.Printf("Warning: Could not truncate order details: %v", err)
		}
		if err := tx.Exec(`TRUNCATE TABLE purchase_orders RESTART IDENTITY CASCADE`).Error; err != nil {
			log.Printf("Warning: Could not truncate orders: %v", err)
		}

		// 4. Clear inventory data
		if err := tx.Exec(`TRUNCATE TABLE warehouse_inventory RESTART IDENTITY CASCADE`).Error; err != nil {
			log.Printf("Warning: Could not truncate warehouse inventory: %v", err)
		}
		if err := tx.Exec(`TRUNCATE TABLE shelf_batch_inventory RESTART IDENTITY CASCADE`).Error; err != nil {
			log.Printf("Warning: Could not truncate shelf inventory: %v", err)
		}
		if err := tx.Exec(`TRUNCATE TABLE shelf_layout RESTART IDENTITY CASCADE`).Error; err != nil {
			log.Printf("Warning: Could not truncate shelf layouts: %v", err)
		}

		// Reset customer spending to 0 for fresh simulation
		if err := tx.Model(&models.Customer{}).Updates(map[string]interface{}{
			"total_spending": 0,
			"loyalty_points": 0,
		}).Error; err != nil {
			log.Printf("Warning: Could not reset customer spending: %v", err)
		}

		return nil
	})
}

// hasExistingData checks if simulation data already exists for the period
func hasExistingData(db *gorm.DB, start, end time.Time) bool {
	var count int64

	// Check for existing purchase orders
	db.Model(&models.PurchaseOrder{}).
		Where("order_date BETWEEN ? AND ?", start, end).
		Count(&count)
	if count > 0 {
		return true
	}

	// Check for existing invoices
	db.Model(&models.SalesInvoice{}).
		Where("invoice_date BETWEEN ? AND ?", start, end).
		Count(&count)
	if count > 0 {
		return true
	}

	// Check for existing transfers
	db.Model(&models.StockTransfer{}).
		Where("transfer_date BETWEEN ? AND ?", start, end).
		Count(&count)
	if count > 0 {
		return true
	}

	return false
}

// printStatistics prints simulation statistics
func printStatistics(db *gorm.DB, start, end time.Time) {
	fmt.Println("\n╔══════════════════════════════════════════════╗")
	fmt.Println("║          SIMULATION STATISTICS               ║")
	fmt.Println("╚══════════════════════════════════════════════╝")

	// Purchase Orders
	var orderStats struct {
		Count int64
		Total float64
	}
	db.Model(&models.PurchaseOrder{}).
		Select("COUNT(*) as count, COALESCE(SUM(total_amount), 0) as total").
		Where("order_date BETWEEN ? AND ?", start, end).
		Scan(&orderStats)

	fmt.Printf("\n📦 PURCHASE ORDERS\n")
	fmt.Printf("   Total Orders:  %d\n", orderStats.Count)
	fmt.Printf("   Total Value:   %,.0f VND\n", orderStats.Total)

	// Sales Invoices
	var invoiceStats struct {
		Count         int64
		Total         float64
		AvgValue      float64
		TotalDiscount float64
	}
	db.Model(&models.SalesInvoice{}).
		Select(`
			COUNT(*) as count, 
			COALESCE(SUM(total_amount), 0) as total,
			COALESCE(AVG(total_amount), 0) as avg_value,
			COALESCE(SUM(discount_amount), 0) as total_discount
		`).
		Where("invoice_date BETWEEN ? AND ?", start, end).
		Scan(&invoiceStats)

	fmt.Printf("\n💰 SALES INVOICES\n")
	fmt.Printf("   Total Invoices:    %d\n", invoiceStats.Count)
	fmt.Printf("   Total Revenue:     %,.0f VND\n", invoiceStats.Total)
	fmt.Printf("   Average Invoice:   %,.0f VND\n", invoiceStats.AvgValue)
	fmt.Printf("   Total Discounts:   %,.0f VND\n", invoiceStats.TotalDiscount)

	// Stock Transfers
	var transferCount int64
	db.Model(&models.StockTransfer{}).
		Where("transfer_date BETWEEN ? AND ?", start, end).
		Count(&transferCount)

	fmt.Printf("\n📤 STOCK TRANSFERS\n")
	fmt.Printf("   Total Transfers:   %d\n", transferCount)

	// Top Selling Products
	type TopProduct struct {
		ProductName string
		TotalQty    int64
		TotalValue  float64
	}
	var topProducts []TopProduct

	db.Table("sales_invoice_details sid").
		Select(`
			p.product_name,
			SUM(sid.quantity) as total_qty,
			SUM(sid.subtotal) as total_value
		`).
		Joins("JOIN sales_invoices si ON sid.invoice_id = si.invoice_id").
		Joins("JOIN products p ON sid.product_id = p.product_id").
		Where("si.invoice_date BETWEEN ? AND ?", start, end).
		Group("p.product_id, p.product_name").
		Order("total_value DESC").
		Limit(5).
		Scan(&topProducts)

	fmt.Printf("\n🏆 TOP 5 BEST SELLING PRODUCTS\n")
	for i, p := range topProducts {
		fmt.Printf("   %d. %-30s Qty: %4d  Revenue: %,.0f VND\n",
			i+1, p.ProductName, p.TotalQty, p.TotalValue)
	}

	// Current Inventory Status
	var warehouseStock struct {
		TotalProducts int64
		TotalValue    float64
	}
	db.Table("warehouse_inventory").
		Select(`
			COUNT(DISTINCT product_id) as total_products,
			SUM(quantity * import_price) as total_value
		`).
		Where("quantity > 0").
		Scan(&warehouseStock)

	var shelfStock struct {
		TotalProducts int64
		TotalValue    float64
	}
	db.Table("shelf_batch_inventory").
		Select(`
			COUNT(DISTINCT product_id) as total_products,
			SUM(quantity * current_price) as total_value
		`).
		Where("quantity > 0").
		Scan(&shelfStock)

	fmt.Printf("\n📊 CURRENT INVENTORY STATUS\n")
	fmt.Printf("   Warehouse Products:  %d products worth %,.0f VND\n",
		warehouseStock.TotalProducts, warehouseStock.TotalValue)
	fmt.Printf("   Shelf Products:      %d products worth %,.0f VND\n",
		shelfStock.TotalProducts, shelfStock.TotalValue)

	// Daily average
	days := int(end.Sub(start).Hours()/24) + 1
	if days > 0 {
		fmt.Printf("\n📈 DAILY AVERAGES\n")
		fmt.Printf("   Sales per day:       %,.0f VND\n", invoiceStats.Total/float64(days))
		fmt.Printf("   Transactions/day:    %.1f\n", float64(invoiceStats.Count)/float64(days))
	}

	fmt.Println("\n" + strings.Repeat("═", 50))
}
