package handlers

import (
	"strconv"

	"github.com/gofiber/fiber/v2"
	"github.com/supermarket/database"
	"github.com/supermarket/models"
)

// ProductList displays all products using VIEW
func ProductList(c *fiber.Ctx) error {
	db := database.GetDB()

	var products []struct {
		ProductID         uint
		ProductCode       string
		ProductName       string
		CategoryName      string
		SupplierName      string
		SellingPrice      float64
		ImportPrice       float64
		WarehouseQuantity int64
		ShelfQuantity     int64
		TotalQuantity     int64
	}

	// Use VIEW for better database learning
	query := `
		SELECT 
			product_id, product_code, product_name, category_name,
			supplier_name, selling_price, import_price,
			warehouse_quantity, shelf_quantity, total_quantity
		FROM supermarket.v_product_overview
		ORDER BY product_name
	`

	db.Raw(query).Scan(&products)

	return c.Render("pages/products/list", fiber.Map{
		"Title":           "Quản lý sản phẩm",
		"Active":          "products",
		"Products":        products,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	})
}

// ProductNew shows form to create new product
func ProductNew(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get categories
	var categories []models.ProductCategory
	db.Raw("SELECT * FROM supermarket.product_categories ORDER BY category_name").Scan(&categories)

	// Get suppliers
	var suppliers []models.Supplier
	db.Raw("SELECT * FROM supermarket.suppliers ORDER BY company_name").Scan(&suppliers)

	return c.Render("pages/products/form", fiber.Map{
		"Title":           "Thêm sản phẩm mới",
		"Active":          "products",
		"Categories":      categories,
		"Suppliers":       suppliers,
		"IsNew":           true,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	})
}

// ProductCreate creates a new product
func ProductCreate(c *fiber.Ctx) error {
	db := database.GetDB()

	// Parse form data
	importPrice, _ := strconv.ParseFloat(c.FormValue("import_price"), 64)
	sellingPrice, _ := strconv.ParseFloat(c.FormValue("selling_price"), 64)
	categoryID, _ := strconv.ParseUint(c.FormValue("category_id"), 10, 64)
	supplierID, _ := strconv.ParseUint(c.FormValue("supplier_id"), 10, 64)
	minStock, _ := strconv.ParseInt(c.FormValue("min_stock_level"), 10, 64)
	shelfLife, _ := strconv.ParseInt(c.FormValue("shelf_life_days"), 10, 64)

	// Validate price constraint
	if sellingPrice <= importPrice {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Giá bán phải lớn hơn giá nhập",
		})
	}

	// Use raw SQL for learning
	query := `
		INSERT INTO supermarket.products 
		(product_code, product_name, category_id, supplier_id, 
		 import_price, selling_price, min_stock_level, shelf_life_days)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING product_id
	`

	var productID uint
	err := db.Raw(query,
		c.FormValue("product_code"),
		c.FormValue("product_name"),
		categoryID,
		supplierID,
		importPrice,
		sellingPrice,
		minStock,
		shelfLife,
	).Scan(&productID).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể tạo sản phẩm: " + err.Error(),
		})
	}

	return c.Redirect("/products")
}

// ProductView displays single product details
func ProductView(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	var product struct {
		models.Product
		CategoryName string
		SupplierName string
	}

	query := `
		SELECT p.*, c.category_name, s.supplier_name as supplier_name
		FROM supermarket.products p
		LEFT JOIN supermarket.product_categories c ON p.category_id = c.category_id
		LEFT JOIN supermarket.suppliers s ON p.supplier_id = s.supplier_id
		WHERE p.product_id = $1
	`

	err := db.Raw(query, id).Scan(&product).Error
	if err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không tìm thấy sản phẩm",
			"Code":  404,
		})
	}

	// Get inventory info
	var inventory struct {
		WarehouseQty int64
		ShelfQty     int64
	}

	db.Raw(`
		SELECT 
			COALESCE(SUM(wi.quantity), 0) as warehouse_qty,
			COALESCE(SUM(si.current_quantity), 0) as shelf_qty
		FROM supermarket.products p
		LEFT JOIN supermarket.warehouse_inventory wi ON p.product_id = wi.product_id
		LEFT JOIN supermarket.shelf_inventory si ON p.product_id = si.product_id
		WHERE p.product_id = $1
		GROUP BY p.product_id
	`, id).Scan(&inventory)

	return c.Render("pages/products/view", fiber.Map{
		"Title":           "Chi tiết sản phẩm",
		"Active":          "products",
		"Product":         product,
		"Inventory":       inventory,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	})
}

// ProductEdit shows form to edit product
func ProductEdit(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	var product models.Product
	err := db.Raw("SELECT * FROM supermarket.products WHERE product_id = $1", id).Scan(&product).Error
	if err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không tìm thấy sản phẩm",
			"Code":  404,
		})
	}

	// Get categories
	var categories []models.ProductCategory
	db.Raw("SELECT * FROM supermarket.product_categories ORDER BY category_name").Scan(&categories)

	// Get suppliers
	var suppliers []models.Supplier
	db.Raw("SELECT * FROM supermarket.suppliers ORDER BY company_name").Scan(&suppliers)

	return c.Render("pages/products/form", fiber.Map{
		"Title":           "Chỉnh sửa sản phẩm",
		"Active":          "products",
		"Product":         product,
		"Categories":      categories,
		"Suppliers":       suppliers,
		"IsNew":           false,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	})
}

// ProductUpdate updates a product
func ProductUpdate(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	// Parse form data
	importPrice, _ := strconv.ParseFloat(c.FormValue("import_price"), 64)
	sellingPrice, _ := strconv.ParseFloat(c.FormValue("selling_price"), 64)
	categoryID, _ := strconv.ParseUint(c.FormValue("category_id"), 10, 64)
	supplierID, _ := strconv.ParseUint(c.FormValue("supplier_id"), 10, 64)
	minStock, _ := strconv.ParseInt(c.FormValue("min_stock_level"), 10, 64)
	shelfLife, _ := strconv.ParseInt(c.FormValue("shelf_life_days"), 10, 64)

	// Validate price constraint
	if sellingPrice <= importPrice {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Giá bán phải lớn hơn giá nhập",
		})
	}

	// Use raw SQL
	query := `
		UPDATE supermarket.products 
		SET product_code = $1, product_name = $2, category_id = $3, 
		    supplier_id = $4, import_price = $5, selling_price = $6,
		    min_stock_level = $7, shelf_life_days = $8
		WHERE product_id = $9
	`

	err := db.Exec(query,
		c.FormValue("product_code"),
		c.FormValue("product_name"),
		categoryID,
		supplierID,
		importPrice,
		sellingPrice,
		minStock,
		shelfLife,
		id,
	).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể cập nhật sản phẩm: " + err.Error(),
		})
	}

	return c.Redirect("/products")
}

// ProductDelete deletes a product
func ProductDelete(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	// Check if product has inventory
	var count int64
	db.Raw(`
		SELECT COUNT(*) FROM (
			SELECT 1 FROM supermarket.warehouse_inventory WHERE product_id = $1
			UNION ALL
			SELECT 1 FROM supermarket.shelf_inventory WHERE product_id = $1
		) t
	`, id).Scan(&count)

	if count > 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Không thể xóa sản phẩm đang có trong kho hoặc trên quầy",
		})
	}

	// Delete product
	err := db.Exec("DELETE FROM supermarket.products WHERE product_id = $1", id).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể xóa sản phẩm: " + err.Error(),
		})
	}

	return c.SendStatus(fiber.StatusOK)
}
