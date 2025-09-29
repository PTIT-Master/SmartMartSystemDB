package handlers

import (
	"fmt"
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/supermarket/database"
	"github.com/supermarket/models"
)

// Employee handlers (full CRUD)
func EmployeeList(c *fiber.Ctx) error {
	db := database.GetDB()

	var employees []struct {
		EmployeeID   uint
		EmployeeCode string
		FullName     string
		PositionName string
		Phone        *string
		Email        *string
		HireDate     string
		IsActive     bool
	}

	err := db.Raw(`
        SELECT e.employee_id, e.employee_code, e.full_name,
               p.position_name, e.phone, e.email,
               TO_CHAR(e.hire_date, 'DD/MM/YYYY') AS hire_date,
               e.is_active
        FROM supermarket.employees e
        JOIN supermarket.positions p ON e.position_id = p.position_id
        ORDER BY e.full_name
    `).Scan(&employees).Error
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "Lỗi tải nhân viên: "+err.Error())
	}

	return c.Render("pages/employees/list", fiber.Map{
		"Title":           "Quản lý nhân viên",
		"Active":          "employees",
		"Employees":       employees,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func EmployeeNew(c *fiber.Ctx) error {
	db := database.GetDB()

	var positions []models.Position
	db.Raw("SELECT * FROM supermarket.positions ORDER BY position_name").Scan(&positions)

	return c.Render("pages/employees/form", fiber.Map{
		"Title":           "Thêm nhân viên",
		"Active":          "employees",
		"Positions":       positions,
		"IsNew":           true,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func EmployeeCreate(c *fiber.Ctx) error {
	db := database.GetDB()

	positionID, _ := strconv.ParseUint(c.FormValue("position_id"), 10, 64)
	hireDate := c.FormValue("hire_date")
	isActive := c.FormValue("is_active") == "on"

	err := db.Exec(`
        INSERT INTO supermarket.employees
        (employee_code, full_name, position_id, phone, email, address, hire_date, id_card, bank_account, is_active)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
    `,
		c.FormValue("employee_code"),
		c.FormValue("full_name"),
		positionID,
		nullIfEmpty(c.FormValue("phone")),
		nullIfEmpty(c.FormValue("email")),
		nullIfEmpty(c.FormValue("address")),
		hireDate,
		nullIfEmpty(c.FormValue("id_card")),
		nullIfEmpty(c.FormValue("bank_account")),
		isActive,
	).Error
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể tạo nhân viên: " + err.Error()})
	}
	return c.Redirect("/employees")
}

func EmployeeView(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	var emp struct {
		models.Employee
		PositionName string
		HireDateText string
	}
	err := db.Raw(`
        SELECT e.*, p.position_name,
               TO_CHAR(e.hire_date, 'DD/MM/YYYY') AS hire_date_text
        FROM supermarket.employees e
        JOIN supermarket.positions p ON e.position_id = p.position_id
        WHERE e.employee_id = $1
    `, id).Scan(&emp).Error
	if err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{"Title": "Lỗi", "Error": "Không tìm thấy nhân viên", "Code": 404})
	}

	return c.Render("pages/employees/view", fiber.Map{
		"Title":           "Chi tiết nhân viên",
		"Active":          "employees",
		"Employee":        emp,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func EmployeeEdit(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	var employee models.Employee
	if err := db.Raw("SELECT * FROM supermarket.employees WHERE employee_id = $1", id).Scan(&employee).Error; err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{"Title": "Lỗi", "Error": "Không tìm thấy nhân viên", "Code": 404})
	}

	var positions []models.Position
	db.Raw("SELECT * FROM supermarket.positions ORDER BY position_name").Scan(&positions)

	return c.Render("pages/employees/form", fiber.Map{
		"Title":           "Chỉnh sửa nhân viên",
		"Active":          "employees",
		"Employee":        employee,
		"Positions":       positions,
		"IsNew":           false,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func EmployeeUpdate(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	positionID, _ := strconv.ParseUint(c.FormValue("position_id"), 10, 64)
	hireDate := c.FormValue("hire_date")
	isActive := c.FormValue("is_active") == "on"

	err := db.Exec(`
        UPDATE supermarket.employees
        SET employee_code=$1, full_name=$2, position_id=$3, phone=$4, email=$5,
            address=$6, hire_date=$7, id_card=$8, bank_account=$9, is_active=$10
        WHERE employee_id=$11
    `,
		c.FormValue("employee_code"),
		c.FormValue("full_name"),
		positionID,
		nullIfEmpty(c.FormValue("phone")),
		nullIfEmpty(c.FormValue("email")),
		nullIfEmpty(c.FormValue("address")),
		hireDate,
		nullIfEmpty(c.FormValue("id_card")),
		nullIfEmpty(c.FormValue("bank_account")),
		isActive,
		id,
	).Error
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể cập nhật nhân viên: " + err.Error()})
	}
	return c.Redirect("/employees")
}

func EmployeeDelete(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	// Prevent delete when referenced
	var refCount int64
	db.Raw(`
        SELECT COUNT(*) FROM (
            SELECT 1 FROM supermarket.sales_invoices WHERE employee_id = $1
            UNION ALL
            SELECT 1 FROM supermarket.purchase_orders WHERE employee_id = $1
            UNION ALL
            SELECT 1 FROM supermarket.stock_transfers WHERE employee_id = $1
        ) t
    `, id).Scan(&refCount)
	if refCount > 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể xóa nhân viên đang được tham chiếu bởi giao dịch"})
	}

	if err := db.Exec("DELETE FROM supermarket.employees WHERE employee_id = $1", id).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Không thể xóa nhân viên: " + err.Error()})
	}
	return c.SendStatus(fiber.StatusOK)
}

// nullIfEmpty converts empty string to nil pointer for nullable columns
func nullIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	v := s
	return &v
}

// Customer handlers (full CRUD)
func CustomerList(c *fiber.Ctx) error {
	db := database.GetDB()

	// Use view v_vip_customers to show membership summary
	var customers []struct {
		CustomerID      uint
		FullName        string
		Phone           *string
		Email           *string
		MembershipLevel *string
		TotalSpending   float64
		LoyaltyPoints   int64
		PurchaseCount   int64
		LastPurchase    *string
	}
	err := db.Raw(`
        SELECT 
            customer_id, full_name, phone, email, membership_level,
            total_spending, loyalty_points, purchase_count, 
            TO_CHAR(last_purchase, 'DD/MM/YYYY HH24:MI') as last_purchase
        FROM supermarket.v_vip_customers
        ORDER BY total_spending DESC
    `).Scan(&customers).Error
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "Lỗi tải khách hàng: "+err.Error())
	}

	return c.Render("pages/customers/list", fiber.Map{
		"Title":           "Quản lý khách hàng",
		"Active":          "customers",
		"Customers":       customers,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func CustomerNew(c *fiber.Ctx) error {
	db := database.GetDB()
	var levels []models.MembershipLevel
	db.Raw("SELECT * FROM supermarket.membership_levels ORDER BY min_spending").Scan(&levels)
	return c.Render("pages/customers/form", fiber.Map{
		"Title":           "Thêm khách hàng",
		"Active":          "customers",
		"Levels":          levels,
		"IsNew":           true,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func CustomerCreate(c *fiber.Ctx) error {
	db := database.GetDB()
	levelID, _ := strconv.ParseUint(c.FormValue("membership_level_id"), 10, 64)
	isActive := c.FormValue("is_active") == "on"

	err := db.Exec(`
        INSERT INTO supermarket.customers
        (customer_code, full_name, phone, email, address, membership_card_no, membership_level_id, is_active)
        VALUES ($1,$2, NULLIF($3,''), NULLIF($4,''), NULLIF($5,''), NULLIF($6,''), NULLIF($7,0), $8)
    `,
		c.FormValue("customer_code"),
		c.FormValue("full_name"),
		c.FormValue("phone"),
		c.FormValue("email"),
		c.FormValue("address"),
		c.FormValue("membership_card_no"),
		levelID,
		isActive,
	).Error
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể tạo khách hàng: " + err.Error()})
	}
	return c.Redirect("/customers")
}

func CustomerView(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	var customer struct {
		models.Customer
		LevelName *string
	}
	err := db.Raw(`
        SELECT c.*, ml.level_name as level_name
        FROM supermarket.customers c
        LEFT JOIN supermarket.membership_levels ml ON c.membership_level_id = ml.level_id
        WHERE c.customer_id = $1
    `, id).Scan(&customer).Error
	if err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{"Title": "Lỗi", "Error": "Không tìm thấy khách hàng", "Code": 404})
	}

	// Fetch invoices of this customer
	var invoices []struct {
		InvoiceID   uint
		InvoiceNo   string
		InvoiceDate string
		TotalAmount float64
	}
	db.Raw(`
        SELECT invoice_id, invoice_no, TO_CHAR(invoice_date,'DD/MM/YYYY HH24:MI') as invoice_date, total_amount
        FROM supermarket.sales_invoices WHERE customer_id = $1
        ORDER BY invoice_date DESC
    `, id).Scan(&invoices)

	return c.Render("pages/customers/view", fiber.Map{
		"Title":           "Chi tiết khách hàng",
		"Active":          "customers",
		"Customer":        customer,
		"Invoices":        invoices,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func CustomerEdit(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	var customer models.Customer
	if err := db.Raw("SELECT * FROM supermarket.customers WHERE customer_id = $1", id).Scan(&customer).Error; err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{"Title": "Lỗi", "Error": "Không tìm thấy khách hàng", "Code": 404})
	}

	var levels []models.MembershipLevel
	db.Raw("SELECT * FROM supermarket.membership_levels ORDER BY min_spending").Scan(&levels)

	return c.Render("pages/customers/form", fiber.Map{
		"Title":           "Chỉnh sửa khách hàng",
		"Active":          "customers",
		"Customer":        customer,
		"Levels":          levels,
		"IsNew":           false,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func CustomerUpdate(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	levelID, _ := strconv.ParseUint(c.FormValue("membership_level_id"), 10, 64)
	isActive := c.FormValue("is_active") == "on"

	err := db.Exec(`
        UPDATE supermarket.customers
        SET customer_code=$1, full_name=$2, phone=NULLIF($3,''), email=NULLIF($4,''), address=NULLIF($5,''),
            membership_card_no=NULLIF($6,''), membership_level_id=NULLIF($7,0), is_active=$8
        WHERE customer_id=$9
    `,
		c.FormValue("customer_code"),
		c.FormValue("full_name"),
		c.FormValue("phone"),
		c.FormValue("email"),
		c.FormValue("address"),
		c.FormValue("membership_card_no"),
		levelID,
		isActive,
		id,
	).Error
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể cập nhật khách hàng: " + err.Error()})
	}
	return c.Redirect("/customers")
}

func CustomerDelete(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	// Prevent delete when referenced by invoices
	var cnt int64
	db.Raw("SELECT COUNT(*) FROM supermarket.sales_invoices WHERE customer_id = $1", id).Scan(&cnt)
	if cnt > 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể xóa khách hàng có hóa đơn"})
	}

	if err := db.Exec("DELETE FROM supermarket.customers WHERE customer_id = $1", id).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Không thể xóa khách hàng: " + err.Error()})
	}
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

// ===== Employee Work Hours =====
func WorkHourList(c *fiber.Ctx) error {
	db := database.GetDB()

	// Optional filters: month, year, employee_id
	month := c.Query("month")
	year := c.Query("year")
	emp := c.Query("employee_id")

	query := `
        SELECT ewh.work_hour_id, ewh.work_date,
               TO_CHAR(ewh.check_in_time, 'HH24:MI') AS check_in,
               TO_CHAR(ewh.check_out_time, 'HH24:MI') AS check_out,
               ewh.total_hours,
               e.full_name, e.employee_id
        FROM supermarket.employee_work_hours ewh
        JOIN supermarket.employees e ON ewh.employee_id = e.employee_id
        WHERE ( $1 = '' OR EXTRACT(MONTH FROM ewh.work_date)::text = $1 )
          AND ( $2 = '' OR EXTRACT(YEAR FROM ewh.work_date)::text = $2 )
          AND ( $3 = '' OR ewh.employee_id::text = $3 )
        ORDER BY ewh.work_date DESC, e.full_name
    `

	var rows []struct {
		WorkHourID uint
		WorkDate   string
		CheckIn    *string
		CheckOut   *string
		TotalHours *float64
		FullName   string
		EmployeeID uint
	}
	if err := db.Raw(query, month, year, emp).Scan(&rows).Error; err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "Lỗi tải công: "+err.Error())
	}

	var employees []models.Employee
	db.Raw("SELECT employee_id, full_name FROM supermarket.employees ORDER BY full_name").Scan(&employees)

	return c.Render("pages/employees/work_hours_list", fiber.Map{
		"Title":           "Công nhân viên",
		"Active":          "employees",
		"Rows":            rows,
		"Employees":       employees,
		"Month":           month,
		"Year":            year,
		"EmployeeID":      emp,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func WorkHourNew(c *fiber.Ctx) error {
	db := database.GetDB()
	var employees []models.Employee
	db.Raw("SELECT employee_id, full_name FROM supermarket.employees ORDER BY full_name").Scan(&employees)
	return c.Render("pages/employees/work_hours_form", fiber.Map{
		"Title":           "Chấm công - thêm",
		"Active":          "employees",
		"Employees":       employees,
		"IsNew":           true,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func WorkHourCreate(c *fiber.Ctx) error {
	db := database.GetDB()
	employeeID, _ := strconv.ParseUint(c.FormValue("employee_id"), 10, 64)
	workDate := c.FormValue("work_date")
	checkIn := c.FormValue("check_in_time")
	checkOut := c.FormValue("check_out_time")

	err := db.Exec(`
        INSERT INTO supermarket.employee_work_hours
        (employee_id, work_date, check_in_time, check_out_time)
        VALUES ($1, $2, NULLIF($3,'' )::timestamptz, NULLIF($4,'')::timestamptz)
    `, employeeID, workDate, checkIn, checkOut).Error
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể lưu chấm công: " + err.Error()})
	}
	return c.Redirect("/employees/work-hours")
}

func WorkHourEdit(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")

	var row struct {
		WorkHourID uint
		EmployeeID uint
		WorkDate   string
		CheckIn    *string
		CheckOut   *string
	}
	if err := db.Raw(`
        SELECT work_hour_id, employee_id, work_date::text,
               TO_CHAR(check_in_time, 'YYYY-MM-DD"T"HH24:MI') as check_in,
               TO_CHAR(check_out_time,'YYYY-MM-DD"T"HH24:MI') as check_out
        FROM supermarket.employee_work_hours WHERE work_hour_id=$1
    `, id).Scan(&row).Error; err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{"Title": "Lỗi", "Error": "Không tìm thấy bản ghi công", "Code": 404})
	}

	var employees []models.Employee
	db.Raw("SELECT employee_id, full_name FROM supermarket.employees ORDER BY full_name").Scan(&employees)

	return c.Render("pages/employees/work_hours_form", fiber.Map{
		"Title":           "Chấm công - sửa",
		"Active":          "employees",
		"Row":             row,
		"Employees":       employees,
		"IsNew":           false,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func WorkHourUpdate(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	employeeID, _ := strconv.ParseUint(c.FormValue("employee_id"), 10, 64)
	workDate := c.FormValue("work_date")
	checkIn := c.FormValue("check_in_time")
	checkOut := c.FormValue("check_out_time")

	err := db.Exec(`
        UPDATE supermarket.employee_work_hours
        SET employee_id=$1, work_date=$2,
            check_in_time=NULLIF($3,'')::timestamptz,
            check_out_time=NULLIF($4,'')::timestamptz
        WHERE work_hour_id=$5
    `, employeeID, workDate, checkIn, checkOut, id).Error
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể cập nhật chấm công: " + err.Error()})
	}
	return c.Redirect("/employees/work-hours")
}

func WorkHourDelete(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	if err := db.Exec("DELETE FROM supermarket.employee_work_hours WHERE work_hour_id=$1", id).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Không thể xóa: " + err.Error()})
	}
	return c.SendStatus(fiber.StatusOK)
}

func SalarySummary(c *fiber.Ctx) error {
	db := database.GetDB()
	month := c.Query("month")
	year := c.Query("year")
	if month == "" || year == "" {
		now := time.Now()
		month = fmt.Sprintf("%02d", int(now.Month()))
		year = fmt.Sprintf("%d", now.Year())
	}

	query := `
        SELECT e.employee_id, e.full_name, p.position_name,
               p.base_salary, p.hourly_rate,
               COALESCE(SUM(ewh.total_hours),0) as total_hours,
               (p.base_salary + p.hourly_rate * COALESCE(SUM(ewh.total_hours),0)) as total_salary
        FROM supermarket.employees e
        JOIN supermarket.positions p ON e.position_id = p.position_id
        LEFT JOIN supermarket.employee_work_hours ewh ON e.employee_id = ewh.employee_id
            AND EXTRACT(MONTH FROM ewh.work_date)::text = $1
            AND EXTRACT(YEAR FROM ewh.work_date)::text = $2
        GROUP BY e.employee_id, e.full_name, p.position_name, p.base_salary, p.hourly_rate
        ORDER BY e.full_name
    `
	var rows []struct {
		EmployeeID   uint
		FullName     string
		PositionName string
		BaseSalary   float64
		HourlyRate   float64
		TotalHours   float64
		TotalSalary  float64
	}
	if err := db.Raw(query, month, year).Scan(&rows).Error; err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "Lỗi thống kê lương: "+err.Error())
	}

	return c.Render("pages/employees/salary_summary", fiber.Map{
		"Title":           "Bảng lương theo tháng",
		"Active":          "employees",
		"Rows":            rows,
		"Month":           month,
		"Year":            year,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// ===== Warehouse CRUD =====
func WarehouseList(c *fiber.Ctx) error {
	db := database.GetDB()
	var rows []models.Warehouse
	db.Raw("SELECT * FROM supermarket.warehouse ORDER BY warehouse_name").Scan(&rows)
	return c.Render("pages/warehouses/list", fiber.Map{
		"Title":           "Quản lý kho",
		"Active":          "warehouses",
		"Warehouses":      rows,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// ===== Positions CRUD =====
func PositionList(c *fiber.Ctx) error {
	db := database.GetDB()
	var rows []models.Position
	db.Raw("SELECT * FROM supermarket.positions ORDER BY position_name").Scan(&rows)
	return c.Render("pages/positions/list", fiber.Map{
		"Title":           "Chức danh & lương cơ bản",
		"Active":          "positions",
		"Positions":       rows,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func PositionNew(c *fiber.Ctx) error {
	return c.Render("pages/positions/form", fiber.Map{
		"Title":           "Thêm chức danh",
		"Active":          "positions",
		"IsNew":           true,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func PositionCreate(c *fiber.Ctx) error {
	db := database.GetDB()
	err := db.Exec(`
        INSERT INTO supermarket.positions
        (position_code, position_name, base_salary, hourly_rate)
        VALUES ($1,$2,$3,$4)
    `,
		c.FormValue("position_code"),
		c.FormValue("position_name"),
		c.FormValue("base_salary"),
		c.FormValue("hourly_rate"),
	).Error
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể tạo chức danh: " + err.Error()})
	}
	return c.Redirect("/positions")
}

func PositionView(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	var row models.Position
	if err := db.Raw("SELECT * FROM supermarket.positions WHERE position_id=$1", id).Scan(&row).Error; err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{"Title": "Lỗi", "Error": "Không tìm thấy chức danh", "Code": 404})
	}
	return c.Render("pages/positions/view", fiber.Map{
		"Title":           "Chi tiết chức danh",
		"Active":          "positions",
		"Position":        row,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func PositionEdit(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	var row models.Position
	if err := db.Raw("SELECT * FROM supermarket.positions WHERE position_id=$1", id).Scan(&row).Error; err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{"Title": "Lỗi", "Error": "Không tìm thấy chức danh", "Code": 404})
	}
	return c.Render("pages/positions/form", fiber.Map{
		"Title":           "Sửa chức danh",
		"Active":          "positions",
		"Position":        row,
		"IsNew":           false,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func PositionUpdate(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	err := db.Exec(`
        UPDATE supermarket.positions
        SET position_code=$1, position_name=$2, base_salary=$3, hourly_rate=$4
        WHERE position_id=$5
    `,
		c.FormValue("position_code"),
		c.FormValue("position_name"),
		c.FormValue("base_salary"),
		c.FormValue("hourly_rate"),
		id,
	).Error
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể cập nhật chức danh: " + err.Error()})
	}
	return c.Redirect("/positions")
}

func PositionDelete(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	var ref int64
	db.Raw("SELECT COUNT(*) FROM supermarket.employees WHERE position_id=$1", id).Scan(&ref)
	if ref > 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể xóa chức danh đang được sử dụng"})
	}
	if err := db.Exec("DELETE FROM supermarket.positions WHERE position_id=$1", id).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Không thể xóa chức danh: " + err.Error()})
	}
	return c.SendStatus(fiber.StatusOK)
}

// ===== Membership Levels CRUD =====
func LevelList(c *fiber.Ctx) error {
	db := database.GetDB()
	var rows []models.MembershipLevel
	db.Raw("SELECT * FROM supermarket.membership_levels ORDER BY min_spending").Scan(&rows)
	return c.Render("pages/membership_levels/list", fiber.Map{
		"Title":           "Cấp thành viên",
		"Active":          "membership-levels",
		"Levels":          rows,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func LevelNew(c *fiber.Ctx) error {
	return c.Render("pages/membership_levels/form", fiber.Map{
		"Title":           "Thêm cấp thành viên",
		"Active":          "membership-levels",
		"IsNew":           true,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func LevelCreate(c *fiber.Ctx) error {
	db := database.GetDB()
	err := db.Exec(`
        INSERT INTO supermarket.membership_levels
        (level_name, min_spending, discount_percentage, points_multiplier)
        VALUES ($1,$2,$3,$4)
    `,
		c.FormValue("level_name"),
		c.FormValue("min_spending"),
		c.FormValue("discount_percentage"),
		c.FormValue("points_multiplier"),
	).Error
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể tạo cấp thành viên: " + err.Error()})
	}
	return c.Redirect("/membership-levels")
}

func LevelView(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	var row models.MembershipLevel
	if err := db.Raw("SELECT * FROM supermarket.membership_levels WHERE level_id=$1", id).Scan(&row).Error; err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{"Title": "Lỗi", "Error": "Không tìm thấy cấp thành viên", "Code": 404})
	}
	// Basic stats: number of customers in this level
	var custCount int64
	db.Raw("SELECT COUNT(*) FROM supermarket.customers WHERE membership_level_id=$1", id).Scan(&custCount)
	return c.Render("pages/membership_levels/view", fiber.Map{
		"Title":           "Chi tiết cấp thành viên",
		"Active":          "membership-levels",
		"Level":           row,
		"CustomerCount":   custCount,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func LevelEdit(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	var row models.MembershipLevel
	if err := db.Raw("SELECT * FROM supermarket.membership_levels WHERE level_id=$1", id).Scan(&row).Error; err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{"Title": "Lỗi", "Error": "Không tìm thấy cấp thành viên", "Code": 404})
	}
	return c.Render("pages/membership_levels/form", fiber.Map{
		"Title":           "Sửa cấp thành viên",
		"Active":          "membership-levels",
		"Level":           row,
		"IsNew":           false,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func LevelUpdate(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	err := db.Exec(`
        UPDATE supermarket.membership_levels
        SET level_name=$1, min_spending=$2, discount_percentage=$3, points_multiplier=$4
        WHERE level_id=$5
    `,
		c.FormValue("level_name"),
		c.FormValue("min_spending"),
		c.FormValue("discount_percentage"),
		c.FormValue("points_multiplier"),
		id,
	).Error
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể cập nhật cấp thành viên: " + err.Error()})
	}
	return c.Redirect("/membership-levels")
}

func LevelDelete(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	var ref int64
	db.Raw("SELECT COUNT(*) FROM supermarket.customers WHERE membership_level_id=$1", id).Scan(&ref)
	if ref > 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể xóa cấp thành viên đang có khách hàng"})
	}
	if err := db.Exec("DELETE FROM supermarket.membership_levels WHERE level_id=$1", id).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Không thể xóa cấp thành viên: " + err.Error()})
	}
	return c.SendStatus(fiber.StatusOK)
}

func WarehouseNew(c *fiber.Ctx) error {
	return c.Render("pages/warehouses/form", fiber.Map{
		"Title":           "Thêm kho",
		"Active":          "warehouses",
		"IsNew":           true,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func WarehouseCreate(c *fiber.Ctx) error {
	db := database.GetDB()
	err := db.Exec(`
        INSERT INTO supermarket.warehouse
        (warehouse_code, warehouse_name, location, manager_name, capacity)
        VALUES ($1, $2, NULLIF($3,''), NULLIF($4,''), NULLIF($5,'')::bigint)
    `,
		c.FormValue("warehouse_code"),
		c.FormValue("warehouse_name"),
		c.FormValue("location"),
		c.FormValue("manager_name"),
		c.FormValue("capacity"),
	).Error
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể tạo kho: " + err.Error()})
	}
	return c.Redirect("/warehouses")
}

func WarehouseView(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	var row models.Warehouse
	if err := db.Raw("SELECT * FROM supermarket.warehouse WHERE warehouse_id=$1", id).Scan(&row).Error; err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{"Title": "Lỗi", "Error": "Không tìm thấy kho", "Code": 404})
	}
	// Load current inventory summary for this warehouse
	var inv []struct {
		ProductID   uint
		ProductName string
		Quantity    int64
	}
	db.Raw(`
        SELECT p.product_id, p.product_name, SUM(wi.quantity) as quantity
        FROM supermarket.warehouse_inventory wi
        JOIN supermarket.products p ON wi.product_id = p.product_id
        WHERE wi.warehouse_id=$1
        GROUP BY p.product_id, p.product_name
        ORDER BY p.product_name
    `, id).Scan(&inv)
	return c.Render("pages/warehouses/view", fiber.Map{
		"Title":           "Chi tiết kho",
		"Active":          "warehouses",
		"Warehouse":       row,
		"Inventory":       inv,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func WarehouseEdit(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	var row models.Warehouse
	if err := db.Raw("SELECT * FROM supermarket.warehouse WHERE warehouse_id=$1", id).Scan(&row).Error; err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{"Title": "Lỗi", "Error": "Không tìm thấy kho", "Code": 404})
	}
	return c.Render("pages/warehouses/form", fiber.Map{
		"Title":           "Sửa kho",
		"Active":          "warehouses",
		"Warehouse":       row,
		"IsNew":           false,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

func WarehouseUpdate(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	err := db.Exec(`
        UPDATE supermarket.warehouse
        SET warehouse_code=$1, warehouse_name=$2, location=NULLIF($3,''),
            manager_name=NULLIF($4,''), capacity=NULLIF($5,'')::bigint
        WHERE warehouse_id=$6
    `,
		c.FormValue("warehouse_code"),
		c.FormValue("warehouse_name"),
		c.FormValue("location"),
		c.FormValue("manager_name"),
		c.FormValue("capacity"),
		id,
	).Error
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể cập nhật kho: " + err.Error()})
	}
	return c.Redirect("/warehouses")
}

func WarehouseDelete(c *fiber.Ctx) error {
	db := database.GetDB()
	id := c.Params("id")
	// Prevent delete when referenced
	var refCount int64
	db.Raw(`
        SELECT COUNT(*) FROM supermarket.warehouse_inventory WHERE warehouse_id=$1
    `, id).Scan(&refCount)
	if refCount > 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Không thể xóa kho còn tồn hàng"})
	}
	if err := db.Exec("DELETE FROM supermarket.warehouse WHERE warehouse_id=$1", id).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Không thể xóa kho: " + err.Error()})
	}
	return c.SendStatus(fiber.StatusOK)
}
