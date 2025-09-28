package handlers

import (
	"github.com/gofiber/fiber/v2"
	"github.com/supermarket/database"
)

// HomePage handles the home page
func HomePage(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get statistics using raw SQL for better learning
	var stats struct {
		TotalProducts  int64
		TotalEmployees int64
		TotalCustomers int64
		TodayRevenue   float64
	}

	// Count products
	db.Raw("SELECT COUNT(*) FROM supermarket.products").Scan(&stats.TotalProducts)

	// Count employees
	db.Raw("SELECT COUNT(*) FROM supermarket.employees").Scan(&stats.TotalEmployees)

	// Count customers
	db.Raw("SELECT COUNT(*) FROM supermarket.customers WHERE customer_id IS NOT NULL").Scan(&stats.TotalCustomers)

	// Today's revenue
	db.Raw(`
		SELECT COALESCE(SUM(total_amount), 0) 
		FROM supermarket.sales_invoices 
		WHERE DATE(invoice_date) = CURRENT_DATE
	`).Scan(&stats.TodayRevenue)

	// Get low stock products using VIEW
	var lowStockProducts []struct {
		Code         string
		Name         string
		ID           uint
		WarehouseQty int64
		ShelfQty     int64
	}

	db.Raw(`
		SELECT 
			product_code as code, 
			product_name as name,
			product_id as id,
			warehouse_quantity as warehouse_qty,
			shelf_quantity as shelf_qty
		FROM supermarket.v_low_stock_products
		ORDER BY total_quantity ASC
	`).Scan(&lowStockProducts)

	// Get low shelf products using NEW VIEW (shelf quantity < threshold but warehouse has stock)
	var lowShelfProducts []struct {
		Code           string
		Name           string
		ID             uint
		ShelfQty       int64
		WarehouseQty   int64
		FillPercentage float64
	}

	db.Raw(`
		SELECT 
			product_code as code, 
			product_name as name,
			product_id as id,
			shelf_quantity as shelf_qty,
			warehouse_quantity as warehouse_qty,
			shelf_fill_percentage as fill_percentage
		FROM supermarket.v_low_shelf_products
		ORDER BY shelf_fill_percentage ASC
	`).Scan(&lowShelfProducts)

	// Get warehouse empty products using VIEW (empty warehouse but still on shelf)
	var warehouseEmptyProducts []struct {
		Code         string
		Name         string
		ID           uint
		ShelfQty     int64
		CategoryName string
	}

	db.Raw(`
		SELECT 
			product_code as code, 
			product_name as name,
			product_id as id,
			shelf_quantity as shelf_qty,
			category_name
		FROM supermarket.v_warehouse_empty_products
		ORDER BY shelf_quantity DESC
	`).Scan(&warehouseEmptyProducts)

	// Get expiring products using VIEW
	var expiringProducts []struct {
		Code          string
		Name          string
		ID            uint
		ExpiryDate    string
		DaysRemaining int
	}

	db.Raw(`
		SELECT 
			product_code as code,
			product_name as name,
			product_id as id,
			expiry_date::text as expiry_date,
			days_remaining
		FROM supermarket.v_expiring_products
		WHERE days_remaining > 0
		ORDER BY days_remaining ASC
	`).Scan(&expiringProducts)

	// Get recent activities from database
	var recentActivities []struct {
		Timestamp   string
		Type        string
		Description string
		User        string
	}

	db.Raw(`
		SELECT 
			TO_CHAR(created_at, 'DD/MM/YYYY HH24:MI') as timestamp,
			CASE 
				WHEN activity_type = 'PRODUCT_CREATED' THEN 'Sản phẩm'
				WHEN activity_type = 'PRODUCT_UPDATED' THEN 'Sản phẩm'
				WHEN activity_type = 'STOCK_TRANSFER' THEN 'Kho hàng'
				WHEN activity_type = 'SALE_COMPLETED' THEN 'Bán hàng'
				WHEN activity_type = 'LOW_STOCK_ALERT' THEN 'Cảnh báo'
				WHEN activity_type = 'EXPIRY_ALERT' THEN 'Cảnh báo'
				ELSE 'Khác'
			END as type,
			description,
			COALESCE(user_name, 'Hệ thống') as user
		FROM supermarket.activity_logs
		ORDER BY created_at DESC
		LIMIT 10
	`).Scan(&recentActivities)

	return c.Render("pages/home", fiber.Map{
		"Title":                  "Trang chủ",
		"Active":                 "home",
		"TotalProducts":          stats.TotalProducts,
		"TotalEmployees":         stats.TotalEmployees,
		"TotalCustomers":         stats.TotalCustomers,
		"TodayRevenue":           stats.TodayRevenue,
		"LowStockProducts":       lowStockProducts,
		"LowShelfProducts":       lowShelfProducts,       // Products needing shelf restock
		"WarehouseEmptyProducts": warehouseEmptyProducts, // Products with empty warehouse
		"ExpiringProducts":       expiringProducts,
		"RecentActivities":       recentActivities,
		"SQLQueries":             c.Locals("SQLQueries"),
		"TotalSQLQueries":        c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// GetSQLLogs returns SQL logs as JSON
func GetSQLLogs(c *fiber.Ctx) error {
	queries := database.SQLLogger.GetRecentQueries(20)
	return c.JSON(queries)
}

// ClearSQLLogs clears all SQL logs
func ClearSQLLogs(c *fiber.Ctx) error {
	database.SQLLogger.Clear()
	return c.SendStatus(fiber.StatusOK)
}
