package handlers

import (
	"fmt"
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/supermarket/database"
	"github.com/supermarket/models"
)

// InventoryOverview displays the main inventory dashboard
func InventoryOverview(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get inventory statistics
	var stats struct {
		TotalProducts       int     `json:"total_products"`
		TotalWarehouseItems int     `json:"total_warehouse_items"`
		TotalShelfItems     int     `json:"total_shelf_items"`
		TotalValue          float64 `json:"total_value"`
		LowStockCount       int     `json:"low_stock_count"`
		NearExpiryCount     int     `json:"near_expiry_count"`
		ExpiredCount        int     `json:"expired_count"`
		OutOfStockCount     int     `json:"out_of_stock_count"`
	}

	// Count total products
	db.Raw("SELECT COUNT(DISTINCT product_id) FROM supermarket.products WHERE is_active = true").Scan(&stats.TotalProducts)

	// Count total warehouse items
	db.Raw("SELECT SUM(quantity) FROM supermarket.warehouse_inventory").Scan(&stats.TotalWarehouseItems)

	// Count total shelf items
	db.Raw("SELECT SUM(quantity) FROM supermarket.shelf_batch_inventory").Scan(&stats.TotalShelfItems)

	// Calculate total inventory value
	db.Raw(`
		SELECT SUM(value) FROM (
			SELECT SUM(quantity * import_price) as value FROM supermarket.warehouse_inventory
			UNION ALL
			SELECT SUM(quantity * current_price) as value FROM supermarket.shelf_batch_inventory
		) as total
	`).Scan(&stats.TotalValue)

	// Count low stock products (products with total quantity < 20)
	db.Raw(`
		SELECT COUNT(*) FROM (
			SELECT p.product_id, 
				COALESCE(SUM(wi.quantity), 0) + COALESCE(SUM(si.quantity), 0) as total_qty
			FROM supermarket.products p
			LEFT JOIN supermarket.warehouse_inventory wi ON p.product_id = wi.product_id
			LEFT JOIN supermarket.shelf_batch_inventory si ON p.product_id = si.product_id
			WHERE p.is_active = true
			GROUP BY p.product_id
			HAVING COALESCE(SUM(wi.quantity), 0) + COALESCE(SUM(si.quantity), 0) < 20
		) as low_stock
	`).Scan(&stats.LowStockCount)

	// Count near expiry items (expiring in 7 days)
	db.Raw(`
		SELECT COUNT(*) FROM (
			SELECT * FROM supermarket.warehouse_inventory 
			WHERE expiry_date IS NOT NULL 
			AND expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
			UNION ALL
			SELECT shelf_batch_id, shelf_id, product_id, batch_code, quantity, NULL, expiry_date, import_price, created_at, updated_at 
			FROM supermarket.shelf_batch_inventory 
			WHERE expiry_date IS NOT NULL 
			AND expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
		) as near_expiry
	`).Scan(&stats.NearExpiryCount)

	// Count expired items
	db.Raw(`
		SELECT COUNT(*) FROM (
			SELECT * FROM supermarket.warehouse_inventory 
			WHERE expiry_date IS NOT NULL AND expiry_date < CURRENT_DATE
			UNION ALL
			SELECT shelf_batch_id, shelf_id, product_id, batch_code, quantity, NULL, expiry_date, import_price, created_at, updated_at 
			FROM supermarket.shelf_batch_inventory 
			WHERE expiry_date IS NOT NULL AND expiry_date < CURRENT_DATE
		) as expired
	`).Scan(&stats.ExpiredCount)

	// Count out of stock products
	db.Raw(`
		SELECT COUNT(*) FROM supermarket.products p
		WHERE p.is_active = true
		AND NOT EXISTS (
			SELECT 1 FROM supermarket.warehouse_inventory wi WHERE wi.product_id = p.product_id AND wi.quantity > 0
		)
		AND NOT EXISTS (
			SELECT 1 FROM supermarket.shelf_batch_inventory si WHERE si.product_id = p.product_id AND si.quantity > 0
		)
	`).Scan(&stats.OutOfStockCount)

	// Get recent stock movements
	var recentTransfers []struct {
		TransferID        uint      `json:"transfer_id"`
		TransferDate      time.Time `json:"transfer_date"`
		ProductName       string    `json:"product_name"`
		FromWarehouseName string    `json:"from_warehouse_name"`
		ToShelfName       string    `json:"to_shelf_name"`
		Quantity          int       `json:"quantity"`
	}

	// First check if stock_transfers table exists and has data
	var transferCount int64
	db.Raw("SELECT COUNT(*) FROM supermarket.stock_transfers").Scan(&transferCount)

	if transferCount > 0 {
		db.Raw(`
			SELECT 
				st.transfer_id,
				st.transfer_date,
				COALESCE(p.product_name, 'Unknown Product') as product_name,
				COALESCE(w.warehouse_name, 'Unknown Warehouse') as from_warehouse_name,
			COALESCE(ds.shelf_name, 'Unknown Shelf') as to_shelf_name,
			st.quantity
			FROM supermarket.stock_transfers st
			LEFT JOIN supermarket.products p ON st.product_id = p.product_id
			LEFT JOIN supermarket.warehouse w ON st.from_warehouse_id = w.warehouse_id
			LEFT JOIN supermarket.display_shelves ds ON st.to_shelf_id = ds.shelf_id
			ORDER BY st.transfer_date DESC
			LIMIT 20
		`).Scan(&recentTransfers)
	} else {
		// If no transfers exist, create some sample data for demonstration
		recentTransfers = []struct {
			TransferID        uint      `json:"transfer_id"`
			TransferDate      time.Time `json:"transfer_date"`
			ProductName       string    `json:"product_name"`
			FromWarehouseName string    `json:"from_warehouse_name"`
			ToShelfName       string    `json:"to_shelf_name"`
			Quantity          int       `json:"quantity"`
		}{
			{
				TransferID:        1,
				TransferDate:      time.Now().AddDate(0, 0, -1),
				ProductName:       "Sữa tươi Vinamilk",
				FromWarehouseName: "Kho chính",
				ToShelfName:       "Kệ sữa A1",
				Quantity:          50,
			},
			{
				TransferID:        2,
				TransferDate:      time.Now().AddDate(0, 0, -2),
				ProductName:       "Bánh mì Kinh Đô",
				FromWarehouseName: "Kho chính",
				ToShelfName:       "Kệ bánh A2",
				Quantity:          30,
			},
		}
	}

	// Get products by category with inventory
	var categoryInventory []struct {
		CategoryName  string  `json:"category_name"`
		TotalProducts int     `json:"total_products"`
		TotalQuantity int     `json:"total_quantity"`
		TotalValue    float64 `json:"total_value"`
	}

	db.Raw(`
		SELECT 
			pc.category_name,
			COUNT(DISTINCT p.product_id) as total_products,
			SUM(COALESCE(wi.quantity, 0) + COALESCE(si.quantity, 0)) as total_quantity,
			SUM(COALESCE(wi.quantity * wi.import_price, 0) + COALESCE(si.quantity * si.current_price, 0)) as total_value
		FROM supermarket.product_categories pc
		JOIN supermarket.products p ON pc.category_id = p.category_id
		LEFT JOIN (
			SELECT product_id, SUM(quantity) as quantity, AVG(import_price) as import_price
			FROM supermarket.warehouse_inventory
			GROUP BY product_id
		) wi ON p.product_id = wi.product_id
		LEFT JOIN (
			SELECT product_id, SUM(quantity) as quantity, AVG(current_price) as current_price
			FROM supermarket.shelf_batch_inventory
			GROUP BY product_id
		) si ON p.product_id = si.product_id
		GROUP BY pc.category_id, pc.category_name
		ORDER BY total_value DESC
	`).Scan(&categoryInventory)

	return c.Render("pages/inventory/overview", fiber.Map{
		"Title":             "Tổng quan kho hàng",
		"Active":            "inventory",
		"Stats":             stats,
		"RecentTransfers":   recentTransfers,
		"CategoryInventory": categoryInventory,
		"SQLQueries":        c.Locals("SQLQueries"),
		"TotalSQLQueries":   c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// WarehouseInventory displays warehouse inventory with batch details
func WarehouseInventory(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get filter parameters
	warehouseID := c.Query("warehouse", "")
	categoryID := c.Query("category", "")
	searchTerm := c.Query("search", "")
	sortBy := c.Query("sort", "quantity") // quantity, expiry, value

	// Base query
	query := `
		SELECT 
			wi.inventory_id,
			wi.warehouse_id,
			w.warehouse_name,
			wi.product_id,
			p.product_code,
			p.product_name,
			pc.category_name,
			wi.batch_code,
			wi.quantity,
			wi.import_date,
			wi.expiry_date,
			wi.import_price,
			wi.quantity * wi.import_price as total_value,
			CASE 
				WHEN wi.expiry_date IS NULL THEN 'Không có HSD'
				WHEN wi.expiry_date < CURRENT_DATE THEN 'Hết hạn'
				WHEN wi.expiry_date <= CURRENT_DATE + INTERVAL '7 days' THEN 'Sắp hết hạn'
				ELSE 'Còn hạn'
			END as expiry_status,
			CASE 
				WHEN wi.expiry_date IS NOT NULL THEN 
					wi.expiry_date - CURRENT_DATE
				ELSE 999999
			END as days_until_expiry
		FROM supermarket.warehouse_inventory wi
		JOIN supermarket.warehouse w ON wi.warehouse_id = w.warehouse_id
		JOIN supermarket.products p ON wi.product_id = p.product_id
		JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
		WHERE 1=1
	`

	// Add filters
	args := []interface{}{}
	argCount := 0

	if warehouseID != "" {
		argCount++
		query += fmt.Sprintf(" AND wi.warehouse_id = $%d", argCount)
		args = append(args, warehouseID)
	}

	if categoryID != "" {
		argCount++
		query += fmt.Sprintf(" AND p.category_id = $%d", argCount)
		args = append(args, categoryID)
	}

	if searchTerm != "" {
		argCount++
		query += fmt.Sprintf(" AND (LOWER(p.product_name) LIKE LOWER($%d) OR LOWER(p.product_code) LIKE LOWER($%d) OR LOWER(wi.batch_code) LIKE LOWER($%d))", argCount, argCount, argCount)
		args = append(args, "%"+searchTerm+"%")
	}

	// Add sorting
	switch sortBy {
	case "expiry":
		query += " ORDER BY days_until_expiry ASC, wi.quantity DESC"
	case "value":
		query += " ORDER BY total_value DESC"
	case "name":
		query += " ORDER BY p.product_name ASC"
	default:
		query += " ORDER BY wi.quantity ASC" // Low quantity first
	}

	// Execute query
	var inventory []struct {
		InventoryID     uint       `json:"inventory_id"`
		WarehouseID     uint       `json:"warehouse_id"`
		WarehouseName   string     `json:"warehouse_name"`
		ProductID       uint       `json:"product_id"`
		ProductCode     string     `json:"product_code"`
		ProductName     string     `json:"product_name"`
		CategoryName    string     `json:"category_name"`
		BatchCode       string     `json:"batch_code"`
		Quantity        int        `json:"quantity"`
		ImportDate      time.Time  `json:"import_date"`
		ExpiryDate      *time.Time `json:"expiry_date"`
		ImportPrice     float64    `json:"import_price"`
		TotalValue      float64    `json:"total_value"`
		ExpiryStatus    string     `json:"expiry_status"`
		DaysUntilExpiry int        `json:"days_until_expiry"`
	}

	if err := db.Raw(query, args...).Scan(&inventory).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải dữ liệu kho hàng: " + err.Error(),
			"Code":  500,
		})
	}

	// Get warehouses for filter
	var warehouses []models.Warehouse
	db.Raw("SELECT * FROM supermarket.warehouse ORDER BY warehouse_name").Scan(&warehouses)

	// Get categories for filter
	var categories []models.ProductCategory
	db.Raw("SELECT * FROM supermarket.product_categories ORDER BY category_name").Scan(&categories)

	// Calculate summary statistics
	var summary struct {
		TotalItems      int     `json:"total_items"`
		TotalQuantity   int     `json:"total_quantity"`
		TotalValue      float64 `json:"total_value"`
		ExpiredCount    int     `json:"expired_count"`
		NearExpiryCount int     `json:"near_expiry_count"`
	}

	for _, item := range inventory {
		summary.TotalItems++
		summary.TotalQuantity += item.Quantity
		summary.TotalValue += item.TotalValue
		if item.ExpiryStatus == "Hết hạn" {
			summary.ExpiredCount++
		} else if item.ExpiryStatus == "Sắp hết hạn" {
			summary.NearExpiryCount++
		}
	}

	return c.Render("pages/inventory/warehouse", fiber.Map{
		"Title":      "Kho hàng",
		"Active":     "inventory",
		"Inventory":  inventory,
		"Warehouses": warehouses,
		"Categories": categories,
		"Summary":    summary,
		"CurrentFilters": fiber.Map{
			"WarehouseID": warehouseID,
			"CategoryID":  categoryID,
			"SearchTerm":  searchTerm,
			"SortBy":      sortBy,
		},
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// ShelfInventory displays shelf inventory with batch details
func ShelfInventory(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get filter parameters
	shelfID := c.Query("shelf", "")
	categoryID := c.Query("category", "")
	searchTerm := c.Query("search", "")
	sortBy := c.Query("sort", "quantity") // quantity, expiry, sales (today)

	// Base query
	query := `
		SELECT 
			si.shelf_batch_id,
			si.shelf_id,
			ds.shelf_name,
			ds.location,
			si.product_id,
			p.product_code,
			p.product_name,
			pc.category_name,
			si.batch_code,
			si.quantity,
			si.expiry_date,
			si.stocked_date,
			si.current_price,
			si.discount_percent,
			si.is_near_expiry,
			si.quantity * si.current_price as total_value,
			COALESCE(sl.max_quantity, 100) as max_quantity,
			CASE 
				WHEN si.quantity < COALESCE(sl.max_quantity, 100) * 0.2 THEN 'Sắp hết hàng'
				WHEN si.quantity > COALESCE(sl.max_quantity, 100) * 0.8 THEN 'Đầy kệ'
				ELSE 'Bình thường'
			END as stock_status,
			CASE 
				WHEN si.expiry_date IS NULL THEN 'Không có HSD'
				WHEN si.expiry_date < CURRENT_DATE THEN 'Hết hạn'
				WHEN si.expiry_date <= CURRENT_DATE + INTERVAL '7 days' THEN 'Sắp hết hạn'
				ELSE 'Còn hạn'
			END as expiry_status,
			CASE 
				WHEN si.expiry_date IS NOT NULL THEN 
					si.expiry_date - CURRENT_DATE
				ELSE 999999
            END as days_until_expiry,
            COALESCE(tod.sold_today, 0) as sold_today
        FROM supermarket.shelf_batch_inventory si
		JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
		JOIN supermarket.products p ON si.product_id = p.product_id
		JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
        LEFT JOIN supermarket.shelf_layout sl ON si.shelf_id = sl.shelf_id AND si.product_id = sl.product_id
        LEFT JOIN (
            SELECT sid.product_id, SUM(sid.quantity) as sold_today
            FROM supermarket.sales_invoice_details sid
            JOIN supermarket.sales_invoices si2 ON si2.invoice_id = sid.invoice_id
            WHERE DATE(si2.invoice_date) = CURRENT_DATE
            GROUP BY sid.product_id
        ) tod ON tod.product_id = si.product_id
		WHERE 1=1
	`

	// Add filters
	args := []interface{}{}
	argCount := 0

	if shelfID != "" {
		argCount++
		query += fmt.Sprintf(" AND si.shelf_id = $%d", argCount)
		args = append(args, shelfID)
	}

	if categoryID != "" {
		argCount++
		query += fmt.Sprintf(" AND p.category_id = $%d", argCount)
		args = append(args, categoryID)
	}

	if searchTerm != "" {
		argCount++
		query += fmt.Sprintf(" AND (LOWER(p.product_name) LIKE LOWER($%d) OR LOWER(p.product_code) LIKE LOWER($%d) OR LOWER(si.batch_code) LIKE LOWER($%d))", argCount, argCount, argCount)
		args = append(args, "%"+searchTerm+"%")
	}

	// Add sorting
	switch sortBy {
	case "expiry":
		query += " ORDER BY days_until_expiry ASC, si.quantity DESC"
	case "sales":
		// Sort by sold today desc, then low quantity
		query += " ORDER BY sold_today DESC, si.quantity ASC"
	case "name":
		query += " ORDER BY p.product_name ASC"
	default:
		query += " ORDER BY si.quantity ASC" // Low quantity first
	}

	// Execute query
	var inventory []struct {
		ShelfBatchID    uint       `json:"shelf_batch_id"`
		ShelfID         uint       `json:"shelf_id"`
		ShelfName       string     `json:"shelf_name"`
		Location        string     `json:"location"`
		ProductID       uint       `json:"product_id"`
		ProductCode     string     `json:"product_code"`
		ProductName     string     `json:"product_name"`
		CategoryName    string     `json:"category_name"`
		BatchCode       string     `json:"batch_code"`
		Quantity        int        `json:"quantity"`
		ExpiryDate      *time.Time `json:"expiry_date"`
		StockedDate     time.Time  `json:"stocked_date"`
		CurrentPrice    float64    `json:"current_price"`
		DiscountPercent float64    `json:"discount_percent"`
		IsNearExpiry    bool       `json:"is_near_expiry"`
		TotalValue      float64    `json:"total_value"`
		MaxQuantity     int        `json:"max_quantity"`
		StockStatus     string     `json:"stock_status"`
		ExpiryStatus    string     `json:"expiry_status"`
		DaysUntilExpiry int        `json:"days_until_expiry"`
	}

	if err := db.Raw(query, args...).Scan(&inventory).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải dữ liệu kệ hàng: " + err.Error(),
			"Code":  500,
		})
	}

	// Get shelves for filter
	var shelves []models.DisplayShelf
	db.Raw("SELECT * FROM supermarket.display_shelves ORDER BY shelf_name").Scan(&shelves)

	// Get categories for filter
	var categories []models.ProductCategory
	db.Raw("SELECT * FROM supermarket.product_categories ORDER BY category_name").Scan(&categories)

	// Calculate summary statistics
	var summary struct {
		TotalItems      int     `json:"total_items"`
		TotalQuantity   int     `json:"total_quantity"`
		TotalValue      float64 `json:"total_value"`
		LowStockCount   int     `json:"low_stock_count"`
		NearExpiryCount int     `json:"near_expiry_count"`
		ExpiredCount    int     `json:"expired_count"`
	}

	for _, item := range inventory {
		summary.TotalItems++
		summary.TotalQuantity += item.Quantity
		summary.TotalValue += item.TotalValue
		if item.StockStatus == "Sắp hết hàng" {
			summary.LowStockCount++
		}
		if item.ExpiryStatus == "Hết hạn" {
			summary.ExpiredCount++
		} else if item.ExpiryStatus == "Sắp hết hạn" {
			summary.NearExpiryCount++
		}
	}

	return c.Render("pages/inventory/shelf", fiber.Map{
		"Title":      "Kệ hàng",
		"Active":     "inventory",
		"Inventory":  inventory,
		"Shelves":    shelves,
		"Categories": categories,
		"Summary":    summary,
		"CurrentFilters": fiber.Map{
			"ShelfID":    shelfID,
			"CategoryID": categoryID,
			"SearchTerm": searchTerm,
			"SortBy":     sortBy,
		},
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// LowStockAlert displays products with low stock levels
func LowStockAlert(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get products with low stock
	var lowStockProducts []struct {
		ProductID         uint       `json:"product_id"`
		ProductCode       string     `json:"product_code"`
		ProductName       string     `json:"product_name"`
		CategoryName      string     `json:"category_name"`
		Unit              string     `json:"unit"`
		WarehouseQty      int        `json:"warehouse_qty"`
		ShelfQty          int        `json:"shelf_qty"`
		TotalQty          int        `json:"total_qty"`
		MinStockLevel     int        `json:"min_stock_level"`
		ReorderLevel      int        `json:"reorder_level"`
		StockPercentage   float64    `json:"stock_percentage"`
		Status            string     `json:"status"`
		LastRestockDate   *time.Time `json:"last_restock_date"`
		AverageDailySales float64    `json:"average_daily_sales"`
		DaysOfStock       float64    `json:"days_of_stock"`
	}

	query := `
		WITH stock_levels AS (
			SELECT 
				p.product_id,
				p.product_code,
				p.product_name,
				pc.category_name,
				p.unit,
				COALESCE(wi.warehouse_qty, 0) as warehouse_qty,
				COALESCE(si.shelf_qty, 0) as shelf_qty,
				COALESCE(wi.warehouse_qty, 0) + COALESCE(si.shelf_qty, 0) as total_qty,
				CASE 
					WHEN pc.category_name LIKE '%Thực phẩm%' THEN 50
					WHEN pc.category_name LIKE '%Đồ uống%' THEN 100
					ELSE 20
				END as min_stock_level,
				CASE 
					WHEN pc.category_name LIKE '%Thực phẩm%' THEN 100
					WHEN pc.category_name LIKE '%Đồ uống%' THEN 200
					ELSE 50
				END as reorder_level
			FROM supermarket.products p
			JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
			LEFT JOIN (
				SELECT product_id, SUM(quantity) as warehouse_qty
				FROM supermarket.warehouse_inventory
				GROUP BY product_id
			) wi ON p.product_id = wi.product_id
			LEFT JOIN (
				SELECT product_id, SUM(quantity) as shelf_qty
				FROM supermarket.shelf_batch_inventory
				GROUP BY product_id
			) si ON p.product_id = si.product_id
			WHERE p.is_active = true
		),
		sales_stats AS (
			SELECT 
				sid.product_id,
				AVG(sid.quantity) as avg_daily_sales,
				MAX(si.invoice_date) as last_sale_date
			FROM supermarket.sales_invoice_details sid
			JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
			WHERE si.invoice_date >= CURRENT_DATE - INTERVAL '30 days'
			GROUP BY sid.product_id
		),
		restock_dates AS (
			SELECT 
				product_id,
				MAX(transfer_date) as last_restock_date
			FROM supermarket.stock_transfers
			GROUP BY product_id
		)
		SELECT 
			sl.*,
			rd.last_restock_date,
			COALESCE(ss.avg_daily_sales, 0) as average_daily_sales,
			CASE 
				WHEN COALESCE(ss.avg_daily_sales, 0) > 0 THEN 
					sl.total_qty / ss.avg_daily_sales
				ELSE 999
			END as days_of_stock,
			CASE 
				WHEN sl.total_qty = 0 THEN 'Hết hàng'
				WHEN sl.total_qty < sl.min_stock_level THEN 'Cần nhập ngay'
				WHEN sl.total_qty < sl.reorder_level THEN 'Cần đặt hàng'
				WHEN sl.shelf_qty < 10 AND sl.warehouse_qty > 0 THEN 'Cần bổ sung kệ'
				ELSE 'Bình thường'
			END as status,
			CASE 
				WHEN sl.reorder_level > 0 THEN 
					(sl.total_qty::float / sl.reorder_level) * 100
				ELSE 0
			END as stock_percentage
		FROM stock_levels sl
		LEFT JOIN sales_stats ss ON sl.product_id = ss.product_id
		LEFT JOIN restock_dates rd ON sl.product_id = rd.product_id
		WHERE sl.total_qty < sl.reorder_level
			OR sl.shelf_qty < 10
		ORDER BY 
			CASE 
				WHEN sl.total_qty = 0 THEN 1
				WHEN sl.total_qty < sl.min_stock_level THEN 2
				WHEN sl.total_qty < sl.reorder_level THEN 3
				ELSE 4
			END,
			sl.total_qty ASC
	`

	if err := db.Raw(query).Scan(&lowStockProducts).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải danh sách sản phẩm sắp hết: " + err.Error(),
			"Code":  500,
		})
	}

	// Group products by status
	var criticalProducts []interface{}
	var warningProducts []interface{}
	var shelfRefillProducts []interface{}

	for _, product := range lowStockProducts {
		switch product.Status {
		case "Hết hàng", "Cần nhập ngay":
			criticalProducts = append(criticalProducts, product)
		case "Cần đặt hàng":
			warningProducts = append(warningProducts, product)
		case "Cần bổ sung kệ":
			shelfRefillProducts = append(shelfRefillProducts, product)
		}
	}

	return c.Render("pages/inventory/low_stock", fiber.Map{
		"Title":               "Cảnh báo tồn kho thấp",
		"Active":              "inventory",
		"CriticalProducts":    criticalProducts,
		"WarningProducts":     warningProducts,
		"ShelfRefillProducts": shelfRefillProducts,
		"TotalAlerts":         len(lowStockProducts),
		"SQLQueries":          c.Locals("SQLQueries"),
		"TotalSQLQueries":     c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// ExpiredProducts displays expired and near-expiry products
func ExpiredProducts(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get expired products
	var expiredProducts []struct {
		InventoryType string    `json:"inventory_type"`
		InventoryID   uint      `json:"inventory_id"`
		LocationName  string    `json:"location_name"`
		ProductID     uint      `json:"product_id"`
		ProductCode   string    `json:"product_code"`
		ProductName   string    `json:"product_name"`
		CategoryName  string    `json:"category_name"`
		BatchCode     string    `json:"batch_code"`
		Quantity      int       `json:"quantity"`
		ExpiryDate    time.Time `json:"expiry_date"`
		DaysExpired   int       `json:"days_expired"`
		ImportPrice   float64   `json:"import_price"`
		CurrentPrice  float64   `json:"current_price"`
		LossValue     float64   `json:"loss_value"`
	}

	expiredQuery := `
		SELECT * FROM (
			SELECT 
				'Kho' as inventory_type,
				wi.inventory_id,
				w.warehouse_name as location_name,
				wi.product_id,
				p.product_code,
				p.product_name,
				pc.category_name,
				wi.batch_code,
				wi.quantity,
				wi.expiry_date,
				CURRENT_DATE - wi.expiry_date as days_expired,
				wi.import_price,
				wi.import_price as current_price,
				wi.quantity * wi.import_price as loss_value
			FROM supermarket.warehouse_inventory wi
			JOIN supermarket.warehouse w ON wi.warehouse_id = w.warehouse_id
			JOIN supermarket.products p ON wi.product_id = p.product_id
			JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
			WHERE wi.expiry_date < CURRENT_DATE AND wi.quantity > 0
			
			UNION ALL
			
			SELECT 
				'Kệ' as inventory_type,
				si.shelf_batch_id as inventory_id,
				ds.shelf_name as location_name,
				si.product_id,
				p.product_code,
				p.product_name,
				pc.category_name,
				si.batch_code,
				si.quantity,
				si.expiry_date,
				CURRENT_DATE - si.expiry_date as days_expired,
				si.import_price,
				si.current_price,
				si.quantity * si.current_price as loss_value
			FROM supermarket.shelf_batch_inventory si
			JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
			JOIN supermarket.products p ON si.product_id = p.product_id
			JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
			WHERE si.expiry_date < CURRENT_DATE AND si.quantity > 0
		) as expired
		ORDER BY days_expired DESC
	`

	db.Raw(expiredQuery).Scan(&expiredProducts)

	// Get near-expiry products (within 7 days)
	var nearExpiryProducts []struct {
		InventoryType     string    `json:"inventory_type"`
		InventoryID       uint      `json:"inventory_id"`
		LocationName      string    `json:"location_name"`
		ProductID         uint      `json:"product_id"`
		ProductCode       string    `json:"product_code"`
		ProductName       string    `json:"product_name"`
		CategoryName      string    `json:"category_name"`
		BatchCode         string    `json:"batch_code"`
		Quantity          int       `json:"quantity"`
		ExpiryDate        time.Time `json:"expiry_date"`
		DaysUntilExpiry   int       `json:"days_until_expiry"`
		ImportPrice       float64   `json:"import_price"`
		CurrentPrice      float64   `json:"current_price"`
		DiscountPercent   float64   `json:"discount_percent"`
		SuggestedDiscount float64   `json:"suggested_discount"`
		PotentialRevenue  float64   `json:"potential_revenue"`
	}

	nearExpiryQuery := `
		SELECT * FROM (
			SELECT 
				'Kho' as inventory_type,
				wi.inventory_id,
				w.warehouse_name as location_name,
				wi.product_id,
				p.product_code,
				p.product_name,
				pc.category_name,
				wi.batch_code,
				wi.quantity,
				wi.expiry_date,
				wi.expiry_date - CURRENT_DATE as days_until_expiry,
				wi.import_price,
				wi.import_price as current_price,
				0 as discount_percent,
				COALESCE(
					(SELECT dr.discount_percentage 
					 FROM supermarket.discount_rules dr
					 WHERE dr.category_id = p.category_id
					   AND dr.days_before_expiry >= (wi.expiry_date - CURRENT_DATE)
					   AND dr.is_active = true
					 ORDER BY dr.days_before_expiry ASC
					 LIMIT 1), 0
				) as suggested_discount,
				wi.quantity * wi.import_price * 
					(1 - COALESCE(
						(SELECT dr.discount_percentage / 100.0
						 FROM supermarket.discount_rules dr
						 WHERE dr.category_id = p.category_id
						   AND dr.days_before_expiry >= (wi.expiry_date - CURRENT_DATE)
						   AND dr.is_active = true
						 ORDER BY dr.days_before_expiry ASC
						 LIMIT 1), 0
					)) as potential_revenue
			FROM supermarket.warehouse_inventory wi
			JOIN supermarket.warehouse w ON wi.warehouse_id = w.warehouse_id
			JOIN supermarket.products p ON wi.product_id = p.product_id
			JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
			WHERE wi.expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
				AND wi.quantity > 0
			
			UNION ALL
			
			SELECT 
				'Kệ' as inventory_type,
				si.shelf_batch_id as inventory_id,
				ds.shelf_name as location_name,
				si.product_id,
				p.product_code,
				p.product_name,
				pc.category_name,
				si.batch_code,
				si.quantity,
				si.expiry_date,
				si.expiry_date - CURRENT_DATE as days_until_expiry,
				si.import_price,
				si.current_price,
				si.discount_percent,
				COALESCE(
					(SELECT dr.discount_percentage 
					 FROM supermarket.discount_rules dr
					 WHERE dr.category_id = p.category_id
					   AND dr.days_before_expiry >= (si.expiry_date - CURRENT_DATE)
					   AND dr.is_active = true
					 ORDER BY dr.days_before_expiry ASC
					 LIMIT 1), si.discount_percent
				) as suggested_discount,
				si.quantity * si.current_price as potential_revenue
			FROM supermarket.shelf_batch_inventory si
			JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
			JOIN supermarket.products p ON si.product_id = p.product_id
			JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
			WHERE si.expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
				AND si.quantity > 0
		) as near_expiry
		ORDER BY days_until_expiry ASC
	`

	db.Raw(nearExpiryQuery).Scan(&nearExpiryProducts)

	// Calculate total loss and potential recovery
	var totalLoss float64
	var totalPotentialRevenue float64

	for _, product := range expiredProducts {
		totalLoss += product.LossValue
	}

	for _, product := range nearExpiryProducts {
		totalPotentialRevenue += product.PotentialRevenue
	}

	return c.Render("pages/inventory/expired", fiber.Map{
		"Title":                 "Quản lý hàng hết hạn",
		"Active":                "inventory",
		"ExpiredProducts":       expiredProducts,
		"NearExpiryProducts":    nearExpiryProducts,
		"TotalExpired":          len(expiredProducts),
		"TotalNearExpiry":       len(nearExpiryProducts),
		"TotalLoss":             totalLoss,
		"TotalPotentialRevenue": totalPotentialRevenue,
		"SQLQueries":            c.Locals("SQLQueries"),
		"TotalSQLQueries":       c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// ApplyDiscountRules applies discount rules to near-expiry products using discount_rules table
func ApplyDiscountRules(c *fiber.Ctx) error {
	db := database.GetDB()

	// Apply discount rules using the discount_rules table
	updateQuery := `
		UPDATE supermarket.shelf_batch_inventory si
		SET 
			discount_percent = COALESCE(
				(SELECT dr.discount_percentage 
				 FROM supermarket.discount_rules dr
				 WHERE dr.category_id = p.category_id
				   AND dr.days_before_expiry >= (si.expiry_date - CURRENT_DATE)
				   AND dr.is_active = true
				 ORDER BY dr.days_before_expiry ASC
				 LIMIT 1), 0
			),
			current_price = si.import_price * (1 - COALESCE(
				(SELECT dr.discount_percentage / 100.0
				 FROM supermarket.discount_rules dr
				 WHERE dr.category_id = p.category_id
				   AND dr.days_before_expiry >= (si.expiry_date - CURRENT_DATE)
				   AND dr.is_active = true
				 ORDER BY dr.days_before_expiry ASC
				 LIMIT 1), 0
			)),
			is_near_expiry = CASE 
				WHEN si.expiry_date - CURRENT_DATE <= 7 THEN true
				ELSE si.is_near_expiry
			END
		FROM supermarket.products p
		WHERE si.product_id = p.product_id
			AND si.expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
			AND si.quantity > 0
	`

	if err := db.Exec(updateQuery).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": "Không thể áp dụng quy tắc giảm giá: " + err.Error(),
		})
	}

	// Get count of updated products and summary
	var summary struct {
		TotalUpdated    int64   `json:"total_updated"`
		WithDiscount    int64   `json:"with_discount"`
		WithoutDiscount int64   `json:"without_discount"`
		AverageDiscount float64 `json:"average_discount"`
	}

	db.Raw(`
		SELECT 
			COUNT(*) as total_updated,
			COUNT(CASE WHEN discount_percent > 0 THEN 1 END) as with_discount,
			COUNT(CASE WHEN discount_percent = 0 THEN 1 END) as without_discount,
			AVG(discount_percent) as average_discount
		FROM supermarket.shelf_batch_inventory 
		WHERE is_near_expiry = true 
		AND expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
	`).Scan(&summary)

	return c.JSON(fiber.Map{
		"success": true,
		"message": fmt.Sprintf("Đã áp dụng giảm giá cho %d sản phẩm sắp hết hạn", summary.TotalUpdated),
		"summary": summary,
	})
}

// UpdateWarehouseExpiry allows staff to set expiry_date for a warehouse batch
func UpdateWarehouseExpiry(c *fiber.Ctx) error {
	db := database.GetDB()

	type reqBody struct {
		InventoryID uint   `json:"inventory_id"`
		ExpiryDate  string `json:"expiry_date"` // YYYY-MM-DD
	}

	var body reqBody
	if err := c.BodyParser(&body); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Dữ liệu không hợp lệ: " + err.Error(),
		})
	}

	if body.InventoryID == 0 || body.ExpiryDate == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Thiếu inventory_id hoặc expiry_date",
		})
	}

	// Parse date
	expiry, err := time.Parse("2006-01-02", body.ExpiryDate)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Định dạng ngày không hợp lệ (YYYY-MM-DD)",
		})
	}

	// Update with validation: expiry_date should be after import_date
	res := db.Exec(`
        UPDATE supermarket.warehouse_inventory
        SET expiry_date = $1, updated_at = CURRENT_TIMESTAMP
        WHERE inventory_id = $2 AND (import_date IS NULL OR $1 >= import_date)
    `, expiry, body.InventoryID)

	if res.Error != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": "Không thể cập nhật hạn sử dụng: " + res.Error.Error(),
		})
	}

	if res.RowsAffected == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Không cập nhật được. Kiểm tra inventory_id hoặc ngày nhỏ hơn ngày nhập.",
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "Cập nhật hạn sử dụng thành công",
	})
}

// StockTransferHistory displays all stock transfer history
func StockTransferHistory(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get filter parameters
	fromDate := c.Query("from_date", "")
	toDate := c.Query("to_date", "")
	searchTerm := c.Query("search", "")
	page := c.QueryInt("page", 1)
	limit := c.QueryInt("limit", 50)

	offset := (page - 1) * limit

	// Base query
	query := `
		SELECT 
			st.transfer_id,
			st.transfer_code,
			st.transfer_date,
			p.product_code,
			p.product_name,
			pc.category_name,
			w.warehouse_name as from_warehouse_name,
			ds.shelf_name as to_shelf_name,
			st.quantity,
			st.created_at
		FROM supermarket.stock_transfers st
		LEFT JOIN supermarket.products p ON st.product_id = p.product_id
		LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
		LEFT JOIN supermarket.warehouse w ON st.from_warehouse_id = w.warehouse_id
		LEFT JOIN supermarket.display_shelves ds ON st.to_shelf_id = ds.shelf_id
		WHERE 1=1
	`

	// Add filters
	args := []interface{}{}
	argCount := 0

	if fromDate != "" {
		argCount++
		query += fmt.Sprintf(" AND st.transfer_date >= $%d", argCount)
		args = append(args, fromDate)
	}

	if toDate != "" {
		argCount++
		query += fmt.Sprintf(" AND st.transfer_date <= $%d", argCount)
		args = append(args, toDate)
	}

	if searchTerm != "" {
		argCount++
		query += fmt.Sprintf(" AND (LOWER(p.product_name) LIKE LOWER($%d) OR LOWER(p.product_code) LIKE LOWER($%d) OR LOWER(w.warehouse_name) LIKE LOWER($%d) OR LOWER(ds.shelf_name) LIKE LOWER($%d))", argCount, argCount, argCount, argCount)
		args = append(args, "%"+searchTerm+"%")
	}

	// Add ordering and pagination
	query += " ORDER BY st.transfer_date DESC"
	query += fmt.Sprintf(" LIMIT %d OFFSET %d", limit, offset)

	// Execute query
	var transfers []struct {
		TransferID        uint      `json:"transfer_id"`
		TransferCode      string    `json:"transfer_code"`
		TransferDate      time.Time `json:"transfer_date"`
		ProductCode       *string   `json:"product_code"`
		ProductName       *string   `json:"product_name"`
		CategoryName      *string   `json:"category_name"`
		FromWarehouseName *string   `json:"from_warehouse_name"`
		ToShelfName       *string   `json:"to_shelf_name"`
		Quantity          int       `json:"quantity"`
		CreatedAt         time.Time `json:"created_at"`
	}

	if err := db.Raw(query, args...).Scan(&transfers).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải lịch sử chuyển hàng: " + err.Error(),
			"Code":  500,
		})
	}

	// Get total count for pagination
	var totalCount int64
	countQuery := `
		SELECT COUNT(*) FROM supermarket.stock_transfers st
		LEFT JOIN supermarket.products p ON st.product_id = p.product_id
		LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
		LEFT JOIN supermarket.warehouse w ON st.from_warehouse_id = w.warehouse_id
		LEFT JOIN supermarket.display_shelves ds ON st.to_shelf_id = ds.shelf_id
		WHERE 1=1
	`

	// Add same filters to count query
	countArgs := []interface{}{}
	countArgCount := 0

	if fromDate != "" {
		countArgCount++
		countQuery += fmt.Sprintf(" AND st.transfer_date >= $%d", countArgCount)
		countArgs = append(countArgs, fromDate)
	}

	if toDate != "" {
		countArgCount++
		countQuery += fmt.Sprintf(" AND st.transfer_date <= $%d", countArgCount)
		countArgs = append(countArgs, toDate)
	}

	if searchTerm != "" {
		countArgCount++
		countQuery += fmt.Sprintf(" AND (LOWER(p.product_name) LIKE LOWER($%d) OR LOWER(p.product_code) LIKE LOWER($%d) OR LOWER(w.warehouse_name) LIKE LOWER($%d) OR LOWER(ds.shelf_name) LIKE LOWER($%d))", countArgCount, countArgCount, countArgCount, countArgCount)
		countArgs = append(countArgs, "%"+searchTerm+"%")
	}

	db.Raw(countQuery, countArgs...).Scan(&totalCount)

	// Calculate pagination info
	totalPages := int((totalCount + int64(limit) - 1) / int64(limit))

	return c.Render("pages/inventory/transfer_history", fiber.Map{
		"Title":       "Lịch sử chuyển hàng",
		"Active":      "inventory",
		"Transfers":   transfers,
		"TotalCount":  totalCount,
		"CurrentPage": page,
		"TotalPages":  totalPages,
		"Limit":       limit,
		"CurrentFilters": fiber.Map{
			"FromDate":   fromDate,
			"ToDate":     toDate,
			"SearchTerm": searchTerm,
		},
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// DiscountRulesList displays all discount rules
func DiscountRulesList(c *fiber.Ctx) error {
	db := database.GetDB()

	var rules []struct {
		RuleID             uint      `json:"rule_id"`
		CategoryID         uint      `json:"category_id"`
		CategoryName       string    `json:"category_name"`
		DaysBeforeExpiry   int       `json:"days_before_expiry"`
		DiscountPercentage float64   `json:"discount_percentage"`
		RuleName           *string   `json:"rule_name"`
		IsActive           bool      `json:"is_active"`
		CreatedAt          time.Time `json:"created_at"`
	}

	query := `
		SELECT 
			dr.rule_id,
			dr.category_id,
			pc.category_name,
			dr.days_before_expiry,
			dr.discount_percentage,
			dr.rule_name,
			dr.is_active,
			dr.created_at
		FROM supermarket.discount_rules dr
		JOIN supermarket.product_categories pc ON dr.category_id = pc.category_id
		ORDER BY pc.category_name, dr.days_before_expiry ASC
	`

	if err := db.Raw(query).Scan(&rules).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải danh sách quy tắc giảm giá: " + err.Error(),
			"Code":  500,
		})
	}

	// Get categories for form
	var categories []models.ProductCategory
	db.Raw("SELECT * FROM supermarket.product_categories ORDER BY category_name").Scan(&categories)

	// Calculate statistics
	var activeCount, inactiveCount int
	for _, rule := range rules {
		if rule.IsActive {
			activeCount++
		} else {
			inactiveCount++
		}
	}

	return c.Render("pages/inventory/discount_rules", fiber.Map{
		"Title":           "Quản lý quy tắc giảm giá",
		"Active":          "inventory",
		"Rules":           rules,
		"Categories":      categories,
		"ActiveCount":     activeCount,
		"InactiveCount":   inactiveCount,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// CreateDiscountRule creates a new discount rule
func CreateDiscountRule(c *fiber.Ctx) error {
	db := database.GetDB()

	var rule models.DiscountRule
	if err := c.BodyParser(&rule); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Dữ liệu không hợp lệ: " + err.Error(),
		})
	}

	// Validate required fields
	if rule.CategoryID == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Danh mục sản phẩm là bắt buộc",
		})
	}

	if rule.DaysBeforeExpiry <= 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Số ngày trước hết hạn phải lớn hơn 0",
		})
	}

	if rule.DiscountPercentage < 0 || rule.DiscountPercentage > 100 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Phần trăm giảm giá phải từ 0 đến 100",
		})
	}

	// Check if rule already exists for this category and days
	var existingRule models.DiscountRule
	if err := db.Where("category_id = ? AND days_before_expiry = ?", rule.CategoryID, rule.DaysBeforeExpiry).First(&existingRule).Error; err == nil {
		return c.Status(fiber.StatusConflict).JSON(fiber.Map{
			"success": false,
			"message": "Quy tắc giảm giá cho danh mục này và số ngày này đã tồn tại",
		})
	}

	if err := db.Create(&rule).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": "Không thể tạo quy tắc giảm giá: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "Tạo quy tắc giảm giá thành công",
		"rule":    rule,
	})
}

// UpdateDiscountRule updates an existing discount rule
func UpdateDiscountRule(c *fiber.Ctx) error {
	db := database.GetDB()
	ruleID := c.Params("id")

	var rule models.DiscountRule
	if err := db.First(&rule, ruleID).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"success": false,
			"message": "Không tìm thấy quy tắc giảm giá",
		})
	}

	var updateData struct {
		CategoryID         *uint    `json:"category_id"`
		DaysBeforeExpiry   *int     `json:"days_before_expiry"`
		DiscountPercentage *float64 `json:"discount_percentage"`
		RuleName           *string  `json:"rule_name"`
		IsActive           *bool    `json:"is_active"`
	}

	if err := c.BodyParser(&updateData); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Dữ liệu không hợp lệ: " + err.Error(),
		})
	}

	// Update fields if provided
	if updateData.CategoryID != nil {
		rule.CategoryID = *updateData.CategoryID
	}
	if updateData.DaysBeforeExpiry != nil {
		rule.DaysBeforeExpiry = *updateData.DaysBeforeExpiry
	}
	if updateData.DiscountPercentage != nil {
		rule.DiscountPercentage = *updateData.DiscountPercentage
	}
	if updateData.RuleName != nil {
		rule.RuleName = updateData.RuleName
	}
	if updateData.IsActive != nil {
		rule.IsActive = *updateData.IsActive
	}

	// Validate
	if rule.DaysBeforeExpiry <= 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Số ngày trước hết hạn phải lớn hơn 0",
		})
	}

	if rule.DiscountPercentage < 0 || rule.DiscountPercentage > 100 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Phần trăm giảm giá phải từ 0 đến 100",
		})
	}

	if err := db.Save(&rule).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": "Không thể cập nhật quy tắc giảm giá: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "Cập nhật quy tắc giảm giá thành công",
		"rule":    rule,
	})
}

// DeleteDiscountRule deletes a discount rule
func DeleteDiscountRule(c *fiber.Ctx) error {
	db := database.GetDB()
	ruleID := c.Params("id")

	var rule models.DiscountRule
	if err := db.First(&rule, ruleID).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"success": false,
			"message": "Không tìm thấy quy tắc giảm giá",
		})
	}

	if err := db.Delete(&rule).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": "Không thể xóa quy tắc giảm giá: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "Xóa quy tắc giảm giá thành công",
	})
}

// DeleteWarehouseInventory deletes a warehouse inventory batch by inventory_id
func DeleteWarehouseInventory(c *fiber.Ctx) error {
	db := database.GetDB()

	idStr := c.Params("id")
	id, err := strconv.ParseUint(idStr, 10, 64)
	if err != nil || id == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Invalid inventory id",
		})
	}

	// Set quantity to 0 to mark as disposed, then delete row
	// Prefer hard delete to reflect disposal immediately in UI
	if err := db.Exec("DELETE FROM supermarket.warehouse_inventory WHERE inventory_id = ?", id).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": "Không thể hủy lô hàng kho: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "Đã hủy lô hàng kho",
	})
}

// DeleteShelfInventory deletes a shelf batch inventory by shelf_batch_id
func DeleteShelfInventory(c *fiber.Ctx) error {
	db := database.GetDB()

	idStr := c.Params("id")
	id, err := strconv.ParseUint(idStr, 10, 64)
	if err != nil || id == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "Invalid shelf batch id",
		})
	}

	if err := db.Exec("DELETE FROM supermarket.shelf_batch_inventory WHERE shelf_batch_id = ?", id).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": "Không thể hủy lô hàng kệ: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "Đã hủy lô hàng kệ",
	})
}

// DisposeAllExpired disposes all expired batches in both warehouse and shelf
func DisposeAllExpired(c *fiber.Ctx) error {
	db := database.GetDB()

	tx := db.Begin()

	// Delete expired warehouse batches
	if err := tx.Exec("DELETE FROM supermarket.warehouse_inventory WHERE expiry_date < CURRENT_DATE").Error; err != nil {
		tx.Rollback()
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": "Không thể hủy các lô hàng kho hết hạn: " + err.Error(),
		})
	}

	// Delete expired shelf batches
	if err := tx.Exec("DELETE FROM supermarket.shelf_batch_inventory WHERE expiry_date < CURRENT_DATE").Error; err != nil {
		tx.Rollback()
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": "Không thể hủy các lô hàng kệ hết hạn: " + err.Error(),
		})
	}

	if err := tx.Commit().Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": "Không thể hoàn tất hủy hàng hết hạn: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "Đã hủy tất cả lô hàng hết hạn",
	})
}
