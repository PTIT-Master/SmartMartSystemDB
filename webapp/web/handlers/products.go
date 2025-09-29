package handlers

import (
	"strconv"
	"time"

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

	// Sorting control
	sortBy := c.Query("sort", "name") // name | total_asc | total_desc

	// Use VIEW for better database learning
	query := `
        SELECT 
            product_id, product_code, product_name, category_name,
            supplier_name, selling_price, import_price,
            warehouse_quantity, shelf_quantity, total_quantity
        FROM supermarket.v_product_overview
    `
	switch sortBy {
	case "total_asc":
		query += " ORDER BY total_quantity ASC, product_name"
	case "total_desc":
		query += " ORDER BY total_quantity DESC, product_name"
	default:
		query += " ORDER BY product_name"
	}

	// Execute query with error handling
	err := db.Raw(query).Scan(&products).Error
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError,
			"Lỗi truy vấn database: "+err.Error())
	}

	return c.Render("pages/products/list", fiber.Map{
		"Title":           "Quản lý sản phẩm",
		"Active":          "products",
		"Products":        products,
		"SortBy":          sortBy,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// ProductNew shows form to create new product
func ProductNew(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get categories
	var categories []models.ProductCategory
	db.Raw("SELECT * FROM supermarket.product_categories ORDER BY category_name").Scan(&categories)

	// Get suppliers
	var suppliers []models.Supplier
	db.Raw("SELECT * FROM supermarket.suppliers ORDER BY supplier_name").Scan(&suppliers)

	return c.Render("pages/products/form", fiber.Map{
		"Title":           "Thêm sản phẩm mới",
		"Active":          "products",
		"Categories":      categories,
		"Suppliers":       suppliers,
		"IsNew":           true,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
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
	}, "layouts/base")
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
	db.Raw("SELECT * FROM supermarket.suppliers ORDER BY supplier_name").Scan(&suppliers)

	return c.Render("pages/products/form", fiber.Map{
		"Title":           "Chỉnh sửa sản phẩm",
		"Active":          "products",
		"Product":         product,
		"Categories":      categories,
		"Suppliers":       suppliers,
		"IsNew":           false,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
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

// DisplayShelfList displays all display shelves
func DisplayShelfList(c *fiber.Ctx) error {
	db := database.GetDB()

	var shelves []struct {
		ShelfID      uint
		ShelfCode    string
		ShelfName    string
		CategoryName string
		Location     *string
		MaxCapacity  *int
		IsActive     bool
	}

	query := `
		SELECT ds.shelf_id, ds.shelf_code, ds.shelf_name, 
		       pc.category_name, ds.location, ds.max_capacity, ds.is_active
		FROM supermarket.display_shelves ds
		LEFT JOIN supermarket.product_categories pc ON ds.category_id = pc.category_id
		ORDER BY ds.shelf_name
	`

	err := db.Raw(query).Scan(&shelves).Error
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError,
			"Lỗi truy vấn database: "+err.Error())
	}

	return c.Render("pages/products/shelf_list", fiber.Map{
		"Title":           "Quản lý quầy trưng bày",
		"Active":          "products",
		"Shelves":         shelves,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// DisplayShelfNew shows form to create new display shelf
func DisplayShelfNew(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get categories
	var categories []models.ProductCategory
	db.Raw("SELECT * FROM supermarket.product_categories ORDER BY category_name").Scan(&categories)

	return c.Render("pages/products/shelf_form", fiber.Map{
		"Title":           "Thêm quầy trưng bày mới",
		"Active":          "products",
		"Categories":      categories,
		"IsNew":           true,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// DisplayShelfCreate creates a new display shelf
func DisplayShelfCreate(c *fiber.Ctx) error {
	db := database.GetDB()

	// Parse form data
	categoryID, _ := strconv.ParseUint(c.FormValue("category_id"), 10, 64)
	maxCapacity, _ := strconv.ParseInt(c.FormValue("max_capacity"), 10, 64)
	isActive := c.FormValue("is_active") == "on"

	query := `
		INSERT INTO supermarket.display_shelves 
		(shelf_code, shelf_name, category_id, location, max_capacity, is_active)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING shelf_id
	`

	var shelfID uint
	err := db.Raw(query,
		c.FormValue("shelf_code"),
		c.FormValue("shelf_name"),
		categoryID,
		c.FormValue("location"),
		maxCapacity,
		isActive,
	).Scan(&shelfID).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể tạo quầy trưng bày: " + err.Error(),
		})
	}

	return c.Redirect("/products/shelves")
}

// DisplayShelfView displays single display shelf details
func DisplayShelfView(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	var shelf struct {
		models.DisplayShelf
		CategoryName string
	}

	query := `
		SELECT ds.*, pc.category_name
		FROM supermarket.display_shelves ds
		LEFT JOIN supermarket.product_categories pc ON ds.category_id = pc.category_id
		WHERE ds.shelf_id = $1
	`

	err := db.Raw(query, id).Scan(&shelf).Error
	if err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không tìm thấy quầy trưng bày",
			"Code":  404,
		})
	}

	// Get shelf inventory info
	var inventory []struct {
		ProductName        string
		CurrentQuantity    int
		NearExpiryQuantity int
		ExpiredQuantity    int
	}

	db.Raw(`
		SELECT p.product_name, si.current_quantity, 
		       si.near_expiry_quantity, si.expired_quantity
		FROM supermarket.shelf_inventory si
		JOIN supermarket.products p ON si.product_id = p.product_id
		WHERE si.shelf_id = $1
		ORDER BY p.product_name
	`, id).Scan(&inventory)

	return c.Render("pages/products/shelf_view", fiber.Map{
		"Title":           "Chi tiết quầy trưng bày",
		"Active":          "products",
		"Shelf":           shelf,
		"Inventory":       inventory,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// DisplayShelfEdit shows form to edit display shelf
func DisplayShelfEdit(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	var shelf models.DisplayShelf
	err := db.Raw("SELECT * FROM supermarket.display_shelves WHERE shelf_id = $1", id).Scan(&shelf).Error
	if err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không tìm thấy quầy trưng bày",
			"Code":  404,
		})
	}

	// Get categories
	var categories []models.ProductCategory
	db.Raw("SELECT * FROM supermarket.product_categories ORDER BY category_name").Scan(&categories)

	return c.Render("pages/products/shelf_form", fiber.Map{
		"Title":           "Chỉnh sửa quầy trưng bày",
		"Active":          "products",
		"Shelf":           shelf,
		"Categories":      categories,
		"IsNew":           false,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// DisplayShelfUpdate updates a display shelf
func DisplayShelfUpdate(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	// Parse form data
	categoryID, _ := strconv.ParseUint(c.FormValue("category_id"), 10, 64)
	maxCapacity, _ := strconv.ParseInt(c.FormValue("max_capacity"), 10, 64)
	isActive := c.FormValue("is_active") == "on"

	query := `
		UPDATE supermarket.display_shelves 
		SET shelf_code = $1, shelf_name = $2, category_id = $3, 
		    location = $4, max_capacity = $5, is_active = $6
		WHERE shelf_id = $7
	`

	err := db.Exec(query,
		c.FormValue("shelf_code"),
		c.FormValue("shelf_name"),
		categoryID,
		c.FormValue("location"),
		maxCapacity,
		isActive,
		id,
	).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể cập nhật quầy trưng bày: " + err.Error(),
		})
	}

	return c.Redirect("/products/shelves")
}

// DisplayShelfDelete deletes a display shelf
func DisplayShelfDelete(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	// Check if shelf has inventory
	var count int64
	db.Raw("SELECT COUNT(*) FROM supermarket.shelf_inventory WHERE shelf_id = $1", id).Scan(&count)

	if count > 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Không thể xóa quầy trưng bày đang có sản phẩm",
		})
	}

	// Delete shelf
	err := db.Exec("DELETE FROM supermarket.display_shelves WHERE shelf_id = $1", id).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể xóa quầy trưng bày: " + err.Error(),
		})
	}

	return c.SendStatus(fiber.StatusOK)
}

// ShelfLayoutList displays all shelf layouts
func ShelfLayoutList(c *fiber.Ctx) error {
	db := database.GetDB()

	var layouts []struct {
		LayoutID     uint
		ShelfName    string
		ProductName  string
		PositionCode string
		MaxQuantity  int
		CreatedAt    time.Time
	}

	query := `
		SELECT sl.layout_id, ds.shelf_name, p.product_name, 
		       sl.position_code, sl.max_quantity, sl.created_at
		FROM supermarket.shelf_layout sl
		JOIN supermarket.display_shelves ds ON sl.shelf_id = ds.shelf_id
		JOIN supermarket.products p ON sl.product_id = p.product_id
		ORDER BY ds.shelf_name, sl.position_code
	`

	err := db.Raw(query).Scan(&layouts).Error
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError,
			"Lỗi truy vấn database: "+err.Error())
	}

	return c.Render("pages/products/shelf_layout_list", fiber.Map{
		"Title":           "Quản lý bố trí quầy",
		"Active":          "products",
		"Layouts":         layouts,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// ShelfLayoutNew shows form to create new shelf layout
func ShelfLayoutNew(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get shelves
	var shelves []models.DisplayShelf
	db.Raw("SELECT * FROM supermarket.display_shelves WHERE is_active = true ORDER BY shelf_name").Scan(&shelves)

	// Get products
	var products []models.Product
	db.Raw("SELECT * FROM supermarket.products ORDER BY product_name").Scan(&products)

	return c.Render("pages/products/shelf_layout_form", fiber.Map{
		"Title":           "Thêm bố trí quầy mới",
		"Active":          "products",
		"Shelves":         shelves,
		"Products":        products,
		"IsNew":           true,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// ShelfLayoutCreate creates a new shelf layout
func ShelfLayoutCreate(c *fiber.Ctx) error {
	db := database.GetDB()

	// Parse form data
	shelfID, _ := strconv.ParseUint(c.FormValue("shelf_id"), 10, 64)
	productID, _ := strconv.ParseUint(c.FormValue("product_id"), 10, 64)
	maxQuantity, _ := strconv.ParseInt(c.FormValue("max_quantity"), 10, 64)

	// Check if layout already exists for this shelf-product combination
	var count int64
	db.Raw("SELECT COUNT(*) FROM supermarket.shelf_layout WHERE shelf_id = $1 AND product_id = $2",
		shelfID, productID).Scan(&count)

	if count > 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Sản phẩm này đã được bố trí trên quầy này",
		})
	}

	query := `
		INSERT INTO supermarket.shelf_layout 
		(shelf_id, product_id, position_code, max_quantity)
		VALUES ($1, $2, $3, $4)
		RETURNING layout_id
	`

	var layoutID uint
	err := db.Raw(query,
		shelfID,
		productID,
		c.FormValue("position_code"),
		maxQuantity,
	).Scan(&layoutID).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể tạo bố trí quầy: " + err.Error(),
		})
	}

	return c.Redirect("/products/shelf-layouts")
}

// ShelfLayoutView displays single shelf layout details
func ShelfLayoutView(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	var layout struct {
		models.ShelfLayout
		ShelfName   string
		ProductName string
	}

	query := `
		SELECT sl.*, ds.shelf_name, p.product_name
		FROM supermarket.shelf_layout sl
		JOIN supermarket.display_shelves ds ON sl.shelf_id = ds.shelf_id
		JOIN supermarket.products p ON sl.product_id = p.product_id
		WHERE sl.layout_id = $1
	`

	err := db.Raw(query, id).Scan(&layout).Error
	if err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không tìm thấy bố trí quầy",
			"Code":  404,
		})
	}

	// Get current inventory for this shelf-product combination
	var inventory struct {
		CurrentQuantity    int
		NearExpiryQuantity int
		ExpiredQuantity    int
	}

	db.Raw(`
		SELECT COALESCE(current_quantity, 0) as current_quantity,
		       COALESCE(near_expiry_quantity, 0) as near_expiry_quantity,
		       COALESCE(expired_quantity, 0) as expired_quantity
		FROM supermarket.shelf_inventory
		WHERE shelf_id = $1 AND product_id = $2
	`, layout.ShelfID, layout.ProductID).Scan(&inventory)

	return c.Render("pages/products/shelf_layout_view", fiber.Map{
		"Title":           "Chi tiết bố trí quầy",
		"Active":          "products",
		"Layout":          layout,
		"Inventory":       inventory,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// ShelfLayoutEdit shows form to edit shelf layout
func ShelfLayoutEdit(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	var layout models.ShelfLayout
	err := db.Raw("SELECT * FROM supermarket.shelf_layout WHERE layout_id = $1", id).Scan(&layout).Error
	if err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không tìm thấy bố trí quầy",
			"Code":  404,
		})
	}

	// Get shelves
	var shelves []models.DisplayShelf
	db.Raw("SELECT * FROM supermarket.display_shelves WHERE is_active = true ORDER BY shelf_name").Scan(&shelves)

	// Get products
	var products []models.Product
	db.Raw("SELECT * FROM supermarket.products ORDER BY product_name").Scan(&products)

	return c.Render("pages/products/shelf_layout_form", fiber.Map{
		"Title":           "Chỉnh sửa bố trí quầy",
		"Active":          "products",
		"Layout":          layout,
		"Shelves":         shelves,
		"Products":        products,
		"IsNew":           false,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// ShelfLayoutUpdate updates a shelf layout
func ShelfLayoutUpdate(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	// Parse form data
	shelfID, _ := strconv.ParseUint(c.FormValue("shelf_id"), 10, 64)
	productID, _ := strconv.ParseUint(c.FormValue("product_id"), 10, 64)
	maxQuantity, _ := strconv.ParseInt(c.FormValue("max_quantity"), 10, 64)

	// Check if layout already exists for this shelf-product combination (excluding current layout)
	var count int64
	db.Raw("SELECT COUNT(*) FROM supermarket.shelf_layout WHERE shelf_id = $1 AND product_id = $2 AND layout_id != $3",
		shelfID, productID, id).Scan(&count)

	if count > 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Sản phẩm này đã được bố trí trên quầy này",
		})
	}

	query := `
		UPDATE supermarket.shelf_layout 
		SET shelf_id = $1, product_id = $2, position_code = $3, max_quantity = $4
		WHERE layout_id = $5
	`

	err := db.Exec(query,
		shelfID,
		productID,
		c.FormValue("position_code"),
		maxQuantity,
		id,
	).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể cập nhật bố trí quầy: " + err.Error(),
		})
	}

	return c.Redirect("/products/shelf-layouts")
}

// ShelfLayoutDelete deletes a shelf layout
func ShelfLayoutDelete(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	// Check if layout has inventory
	var count int64
	db.Raw(`
		SELECT COUNT(*) FROM supermarket.shelf_inventory si
		JOIN supermarket.shelf_layout sl ON si.shelf_id = sl.shelf_id AND si.product_id = sl.product_id
		WHERE sl.layout_id = $1 AND si.current_quantity > 0
	`, id).Scan(&count)

	if count > 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Không thể xóa bố trí quầy đang có sản phẩm",
		})
	}

	// Delete layout
	err := db.Exec("DELETE FROM supermarket.shelf_layout WHERE layout_id = $1", id).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể xóa bố trí quầy: " + err.Error(),
		})
	}

	return c.SendStatus(fiber.StatusOK)
}
