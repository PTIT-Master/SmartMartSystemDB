package handlers

import (
	"fmt"
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/supermarket/database"
	"github.com/supermarket/models"
)

// Employee handlers (stub)
func EmployeeList(c *fiber.Ctx) error {
	return c.Render("pages/under_construction", fiber.Map{
		"Title":           "Quản lý nhân viên",
		"Active":          "employees",
		"Module":          "Quản lý nhân viên",
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func EmployeeNew(c *fiber.Ctx) error {
	return EmployeeList(c)
}

func EmployeeCreate(c *fiber.Ctx) error {
	return c.Redirect("/employees")
}

func EmployeeView(c *fiber.Ctx) error {
	return EmployeeList(c)
}

func EmployeeEdit(c *fiber.Ctx) error {
	return EmployeeList(c)
}

func EmployeeUpdate(c *fiber.Ctx) error {
	return c.Redirect("/employees")
}

func EmployeeDelete(c *fiber.Ctx) error {
	return c.SendStatus(fiber.StatusOK)
}

// Customer handlers (stub)
func CustomerList(c *fiber.Ctx) error {
	return c.Render("pages/under_construction", fiber.Map{
		"Title":           "Quản lý khách hàng",
		"Active":          "customers",
		"Module":          "Quản lý khách hàng",
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func CustomerNew(c *fiber.Ctx) error {
	return CustomerList(c)
}

func CustomerCreate(c *fiber.Ctx) error {
	return c.Redirect("/customers")
}

func CustomerView(c *fiber.Ctx) error {
	return CustomerList(c)
}

func CustomerEdit(c *fiber.Ctx) error {
	return CustomerList(c)
}

func CustomerUpdate(c *fiber.Ctx) error {
	return c.Redirect("/customers")
}

func CustomerDelete(c *fiber.Ctx) error {
	return c.SendStatus(fiber.StatusOK)
}

// Inventory handlers moved to inventory.go

// StockTransferForm displays the stock transfer form
func StockTransferForm(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get product ID from query parameter if provided
	productID := c.Query("product")

	// Get all warehouses
	var warehouses []models.Warehouse
	err := db.Raw("SELECT * FROM supermarket.warehouse ORDER BY warehouse_name").Scan(&warehouses).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải danh sách kho hàng: " + err.Error(),
			"Code":  500,
		})
	}

	// Get all display shelves with their categories
	var shelves []struct {
		ShelfID      uint   `json:"shelf_id"`
		ShelfCode    string `json:"shelf_code"`
		ShelfName    string `json:"shelf_name"`
		CategoryName string `json:"category_name"`
	}
	err = db.Raw(`
		SELECT ds.shelf_id, ds.shelf_code, ds.shelf_name, pc.category_name
		FROM supermarket.display_shelves ds
		LEFT JOIN supermarket.product_categories pc ON ds.category_id = pc.category_id
		ORDER BY ds.shelf_name
	`).Scan(&shelves).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải danh sách quầy hàng: " + err.Error(),
			"Code":  500,
		})
	}

	// Get all employees
	var employees []models.Employee
	err = db.Raw("SELECT * FROM supermarket.employees ORDER BY full_name").Scan(&employees).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải danh sách nhân viên: " + err.Error(),
			"Code":  500,
		})
	}

	// Get all products for the dropdown
	var products []struct {
		ProductID    uint   `json:"product_id"`
		ProductCode  string `json:"product_code"`
		ProductName  string `json:"product_name"`
		CategoryName string `json:"category_name"`
	}
	err = db.Raw(`
		SELECT p.product_id, p.product_code, p.product_name, pc.category_name
		FROM supermarket.products p
		LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
		ORDER BY p.product_name
	`).Scan(&products).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải danh sách sản phẩm: " + err.Error(),
			"Code":  500,
		})
	}

	// If product ID is provided, get product details and warehouse inventory
	var selectedProduct *struct {
		models.Product
		CategoryName      string `json:"category_name"`
		WarehouseQuantity int64  `json:"warehouse_quantity"`
	}
	var warehouseInventory []struct {
		WarehouseID   uint       `json:"warehouse_id"`
		WarehouseName string     `json:"warehouse_name"`
		Quantity      int64      `json:"quantity"`
		BatchCode     string     `json:"batch_code"`
		ExpiryDate    *time.Time `json:"expiry_date"`
	}

	if productID != "" {
		selectedProduct = &struct {
			models.Product
			CategoryName      string `json:"category_name"`
			WarehouseQuantity int64  `json:"warehouse_quantity"`
		}{}

		err = db.Raw(`
			SELECT p.*, pc.category_name,
				COALESCE(SUM(wi.quantity), 0) as warehouse_quantity
			FROM supermarket.products p
			LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
			LEFT JOIN supermarket.warehouse_inventory wi ON p.product_id = wi.product_id
			WHERE p.product_id = $1
			GROUP BY p.product_id, pc.category_name
		`, productID).Scan(selectedProduct).Error

		if err != nil {
			return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{
				"Title": "Lỗi",
				"Error": "Không tìm thấy sản phẩm",
				"Code":  404,
			})
		}

		// Get warehouse inventory details
		err = db.Raw(`
			SELECT wi.warehouse_id, w.warehouse_name, wi.quantity, 
				wi.batch_code, wi.expiry_date
			FROM supermarket.warehouse_inventory wi
			JOIN supermarket.warehouse w ON wi.warehouse_id = w.warehouse_id
			WHERE wi.product_id = $1 AND wi.quantity > 0
			ORDER BY wi.expiry_date NULLS LAST, wi.import_date
		`, productID).Scan(&warehouseInventory).Error

		if err != nil {
			return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
				"Title": "Lỗi",
				"Error": "Không thể tải thông tin tồn kho: " + err.Error(),
				"Code":  500,
			})
		}
	}

	return c.Render("pages/inventory/transfer", fiber.Map{
		"Title":              "Chuyển hàng từ kho lên quầy",
		"Active":             "inventory",
		"Products":           products,
		"Warehouses":         warehouses,
		"Shelves":            shelves,
		"Employees":          employees,
		"SelectedProduct":    selectedProduct,
		"WarehouseInventory": warehouseInventory,
		"ProductID":          productID,
		"SQLQueries":         c.Locals("SQLQueries"),
		"TotalSQLQueries":    c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// StockTransfer processes stock transfer from warehouse to shelf
func StockTransfer(c *fiber.Ctx) error {
	db := database.GetDB()

	// Parse form data
	productIDStr := c.FormValue("product_id")
	if productIDStr == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Vui lòng chọn sản phẩm",
		})
	}

	productID, err := strconv.ParseUint(productIDStr, 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "ID sản phẩm không hợp lệ: " + productIDStr,
		})
	}

	fromWarehouseID, err := strconv.ParseUint(c.FormValue("from_warehouse_id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "ID kho nguồn không hợp lệ",
		})
	}

	toShelfID, err := strconv.ParseUint(c.FormValue("to_shelf_id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "ID quầy đích không hợp lệ",
		})
	}

	quantity, err := strconv.ParseInt(c.FormValue("quantity"), 10, 64)
	if err != nil || quantity <= 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Số lượng không hợp lệ",
		})
	}

	employeeID, err := strconv.ParseUint(c.FormValue("employee_id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "ID nhân viên không hợp lệ",
		})
	}

	// Get batch information from warehouse inventory
	var warehouseInventory struct {
		BatchCode   string     `json:"batch_code"`
		ExpiryDate  *time.Time `json:"expiry_date"`
		ImportPrice float64    `json:"import_price"`
		Available   int64      `json:"available"`
	}

	err = db.Raw(`
		SELECT wi.batch_code, wi.expiry_date, wi.import_price, wi.quantity as available
		FROM supermarket.warehouse_inventory wi
		WHERE wi.warehouse_id = $1 AND wi.product_id = $2 AND wi.quantity >= $3
		ORDER BY wi.expiry_date NULLS LAST, wi.import_date
		LIMIT 1
	`, fromWarehouseID, productID, quantity).Scan(&warehouseInventory).Error

	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Không tìm thấy batch phù hợp trong kho hoặc không đủ số lượng",
		})
	}

	// Get product selling price
	var sellingPrice float64
	err = db.Raw("SELECT selling_price FROM supermarket.products WHERE product_id = $1", productID).Scan(&sellingPrice).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể lấy giá bán sản phẩm: " + err.Error(),
		})
	}

	// Generate transfer code
	transferCode := fmt.Sprintf("TR%s%03d", time.Now().Format("20060102"), time.Now().Nanosecond()%1000)

	// Insert stock transfer record - Let database triggers handle the inventory updates
	query := `
		INSERT INTO supermarket.stock_transfers 
		(transfer_code, product_id, from_warehouse_id, to_shelf_id, quantity, 
		 employee_id, batch_code, expiry_date, import_price, selling_price, notes)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		RETURNING transfer_id
	`

	var transferID uint
	err = db.Raw(query,
		transferCode,
		productID,
		fromWarehouseID,
		toShelfID,
		quantity,
		employeeID,
		warehouseInventory.BatchCode,
		warehouseInventory.ExpiryDate,
		warehouseInventory.ImportPrice,
		sellingPrice,
		c.FormValue("notes"),
	).Scan(&transferID).Error

	if err != nil {
		// Database triggers will provide detailed error messages
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Không thể thực hiện chuyển hàng: " + err.Error(),
		})
	}

	// Return success response
	if c.Get("Content-Type") == "application/json" {
		return c.JSON(fiber.Map{
			"success":     true,
			"transfer_id": transferID,
			"message":     fmt.Sprintf("Chuyển hàng thành công %d sản phẩm", quantity),
		})
	}

	// Redirect to inventory page
	return c.Redirect("/inventory")
}

// Sales handlers moved to sales.go

// Report handlers moved to reports.go

// GetCategories returns all product categories
func GetCategories(c *fiber.Ctx) error {
	db := database.GetDB()

	var categories []struct {
		CategoryID   uint   `json:"category_id"`
		CategoryName string `json:"category_name"`
		Description  string `json:"description"`
		ProductCount int64  `json:"product_count"`
	}

	err := db.Raw(`
		SELECT 
			pc.category_id,
			pc.category_name,
			pc.description,
			COUNT(p.product_id) as product_count
		FROM supermarket.product_categories pc
		LEFT JOIN supermarket.products p ON pc.category_id = p.category_id
		GROUP BY pc.category_id, pc.category_name, pc.description
		ORDER BY pc.category_name
	`).Scan(&categories).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể tải danh mục: " + err.Error(),
		})
	}

	return c.JSON(categories)
}

// GetCategoryProducts returns products in a specific category
func GetCategoryProducts(c *fiber.Ctx) error {
	db := database.GetDB()

	categoryIDStr := c.Params("id")
	categoryID, err := strconv.ParseUint(categoryIDStr, 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "ID danh mục không hợp lệ",
		})
	}

	var products []struct {
		ProductID     uint     `json:"product_id"`
		ProductCode   string   `json:"product_code"`
		ProductName   string   `json:"product_name"`
		SellingPrice  float64  `json:"selling_price"`
		ShelfQuantity int64    `json:"shelf_quantity"`
		ShelfName     string   `json:"shelf_name"`
		ExpiryDate    *string  `json:"expiry_date"`
		DaysToExpiry  *int     `json:"days_to_expiry"`
		DiscountPrice *float64 `json:"discount_price"`
	}

	err = db.Raw(`
		SELECT DISTINCT
			p.product_id,
			p.product_code,
			p.product_name,
			p.selling_price,
			COALESCE(si.current_quantity, 0) as shelf_quantity,
			ds.shelf_name,
			sbi.expiry_date::text,
			CASE 
				WHEN sbi.expiry_date IS NOT NULL 
				THEN (sbi.expiry_date - CURRENT_DATE)::int
				ELSE NULL 
			END as days_to_expiry,
			CASE 
				WHEN sbi.expiry_date IS NOT NULL 
				THEN supermarket.calculate_discount_price(p.product_id, sbi.expiry_date)
				ELSE NULL 
			END as discount_price
		FROM supermarket.products p
		LEFT JOIN supermarket.shelf_inventory si ON p.product_id = si.product_id
		LEFT JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
		LEFT JOIN supermarket.shelf_batch_inventory sbi ON si.shelf_id = sbi.shelf_id AND p.product_id = sbi.product_id AND sbi.quantity > 0
		WHERE p.category_id = $1 AND si.current_quantity > 0
		ORDER BY p.product_name
	`, categoryID).Scan(&products).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể tải sản phẩm: " + err.Error(),
		})
	}

	return c.JSON(products)
}

// GetShelves returns all display shelves
func GetShelves(c *fiber.Ctx) error {
	db := database.GetDB()

	var shelves []struct {
		ShelfID      uint   `json:"shelf_id"`
		ShelfCode    string `json:"shelf_code"`
		ShelfName    string `json:"shelf_name"`
		CategoryName string `json:"category_name"`
		ProductCount int64  `json:"product_count"`
	}

	err := db.Raw(`
		SELECT 
			ds.shelf_id,
			ds.shelf_code,
			ds.shelf_name,
			pc.category_name,
			COUNT(si.product_id) as product_count
		FROM supermarket.display_shelves ds
		LEFT JOIN supermarket.product_categories pc ON ds.category_id = pc.category_id
		LEFT JOIN supermarket.shelf_inventory si ON ds.shelf_id = si.shelf_id
		GROUP BY ds.shelf_id, ds.shelf_code, ds.shelf_name, pc.category_name
		ORDER BY ds.shelf_name
	`).Scan(&shelves).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể tải quầy hàng: " + err.Error(),
		})
	}

	return c.JSON(shelves)
}

// GetShelfProducts returns products on a specific shelf
func GetShelfProducts(c *fiber.Ctx) error {
	db := database.GetDB()

	shelfIDStr := c.Params("id")
	shelfID, err := strconv.ParseUint(shelfIDStr, 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "ID quầy hàng không hợp lệ",
		})
	}

	var products []struct {
		ProductID     uint     `json:"product_id"`
		ProductCode   string   `json:"product_code"`
		ProductName   string   `json:"product_name"`
		SellingPrice  float64  `json:"selling_price"`
		ShelfQuantity int64    `json:"shelf_quantity"`
		ExpiryDate    *string  `json:"expiry_date"`
		DaysToExpiry  *int     `json:"days_to_expiry"`
		DiscountPrice *float64 `json:"discount_price"`
	}

	err = db.Raw(`
		SELECT DISTINCT
			p.product_id,
			p.product_code,
			p.product_name,
			p.selling_price,
			si.current_quantity as shelf_quantity,
			sbi.expiry_date::text,
			CASE 
				WHEN sbi.expiry_date IS NOT NULL 
				THEN (sbi.expiry_date - CURRENT_DATE)::int
				ELSE NULL 
			END as days_to_expiry,
			CASE 
				WHEN sbi.expiry_date IS NOT NULL 
				THEN supermarket.calculate_discount_price(p.product_id, sbi.expiry_date)
				ELSE NULL 
			END as discount_price
		FROM supermarket.shelf_inventory si
		JOIN supermarket.products p ON si.product_id = p.product_id
		LEFT JOIN supermarket.shelf_batch_inventory sbi ON si.shelf_id = sbi.shelf_id AND p.product_id = sbi.product_id AND sbi.quantity > 0
		WHERE si.shelf_id = $1 AND si.current_quantity > 0
		ORDER BY p.product_name
	`, shelfID).Scan(&products).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể tải sản phẩm: " + err.Error(),
		})
	}

	return c.JSON(products)
}

// CheckInventory checks real-time inventory for a product
func CheckInventory(c *fiber.Ctx) error {
	db := database.GetDB()

	productIDStr := c.Params("productId")
	productID, err := strconv.ParseUint(productIDStr, 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "ID sản phẩm không hợp lệ",
		})
	}

	var inventory struct {
		ShelfQuantity     int64    `json:"shelf_quantity"`
		WarehouseQuantity int64    `json:"warehouse_quantity"`
		SellingPrice      float64  `json:"selling_price"`
		DiscountPrice     *float64 `json:"discount_price"`
		ExpiryDate        *string  `json:"expiry_date"`
		DaysToExpiry      *int     `json:"days_to_expiry"`
	}

	err = db.Raw(`
		SELECT 
			COALESCE(si.current_quantity, 0) as shelf_quantity,
			COALESCE(SUM(wi.quantity), 0) as warehouse_quantity,
			p.selling_price,
			CASE 
				WHEN sbi.expiry_date IS NOT NULL 
				THEN supermarket.calculate_discount_price(p.product_id, sbi.expiry_date)
				ELSE NULL 
			END as discount_price,
			sbi.expiry_date::text,
			CASE 
				WHEN sbi.expiry_date IS NOT NULL 
				THEN (sbi.expiry_date - CURRENT_DATE)::int
				ELSE NULL 
			END as days_to_expiry
		FROM supermarket.products p
		LEFT JOIN supermarket.shelf_inventory si ON p.product_id = si.product_id
		LEFT JOIN supermarket.warehouse_inventory wi ON p.product_id = wi.product_id
		LEFT JOIN supermarket.shelf_batch_inventory sbi ON si.shelf_id = sbi.shelf_id AND p.product_id = sbi.product_id AND sbi.quantity > 0
		WHERE p.product_id = $1
		GROUP BY p.product_id, si.current_quantity, p.selling_price, sbi.expiry_date
	`, productID).Scan(&inventory).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể kiểm tra tồn kho: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"available":      inventory.ShelfQuantity,
		"warehouse":      inventory.WarehouseQuantity,
		"selling_price":  inventory.SellingPrice,
		"discount_price": inventory.DiscountPrice,
		"expiry_date":    inventory.ExpiryDate,
		"days_to_expiry": inventory.DaysToExpiry,
	})
}

// CalculateDiscount calculates discount for a product based on expiry date
func CalculateDiscount(c *fiber.Ctx) error {
	db := database.GetDB()

	var request struct {
		ProductID  uint   `json:"product_id"`
		ExpiryDate string `json:"expiry_date"`
	}

	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Dữ liệu không hợp lệ",
		})
	}

	var discountPrice *float64
	err := db.Raw(`
		SELECT supermarket.calculate_discount_price($1, $2::date)
	`, request.ProductID, request.ExpiryDate).Scan(&discountPrice).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể tính giảm giá: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"discount_price": discountPrice,
	})
}
