package handlers

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/supermarket/database"
	"github.com/supermarket/models"
)

// SalesList displays all sales invoices
func SalesList(c *fiber.Ctx) error {
	fmt.Println("DEBUG: SalesList handler called")
	db := database.GetDB()

	// Get query parameters
	page := c.QueryInt("page", 1)
	limit := c.QueryInt("limit", 20)
	search := c.Query("search", "")
	customerID := c.Query("customer_id", "")
	employeeID := c.Query("employee_id", "")
	dateFrom := c.Query("date_from", "")
	dateTo := c.Query("date_to", "")

	fmt.Printf("DEBUG: Query params - page=%d, limit=%d, search=%s\n", page, limit, search)
	offset := (page - 1) * limit

	// Build query
	query := `
		SELECT 
			si.invoice_id,
			si.invoice_no,
			si.invoice_date,
			si.subtotal,
			si.discount_amount,
			si.total_amount,
			si.payment_method,
			si.points_earned,
			si.points_used,
			c.full_name as customer_name,
			c.phone as customer_phone,
			e.full_name as employee_name,
			COALESCE(item_counts.item_count, 0) as item_count
		FROM supermarket.sales_invoices si
		LEFT JOIN supermarket.customers c ON si.customer_id = c.customer_id
		JOIN supermarket.employees e ON si.employee_id = e.employee_id
		LEFT JOIN (
			SELECT invoice_id, COUNT(*) as item_count
			FROM supermarket.sales_invoice_details
			GROUP BY invoice_id
		) item_counts ON si.invoice_id = item_counts.invoice_id
		WHERE 1=1
	`

	args := []interface{}{}
	argIndex := 1

	if search != "" {
		query += fmt.Sprintf(" AND (si.invoice_no ILIKE $%d OR c.full_name ILIKE $%d OR e.full_name ILIKE $%d)", argIndex, argIndex, argIndex)
		args = append(args, "%"+search+"%")
		argIndex++
	}

	if customerID != "" {
		query += fmt.Sprintf(" AND si.customer_id = $%d", argIndex)
		args = append(args, customerID)
		argIndex++
	}

	if employeeID != "" {
		query += fmt.Sprintf(" AND si.employee_id = $%d", argIndex)
		args = append(args, employeeID)
		argIndex++
	}

	if dateFrom != "" {
		query += fmt.Sprintf(" AND DATE(si.invoice_date) >= $%d", argIndex)
		args = append(args, dateFrom)
		argIndex++
	}

	if dateTo != "" {
		query += fmt.Sprintf(" AND DATE(si.invoice_date) <= $%d", argIndex)
		args = append(args, dateTo)
		argIndex++
	}

	query += fmt.Sprintf(`
		ORDER BY si.invoice_date DESC
		LIMIT $%d OFFSET $%d
	`, argIndex, argIndex+1)
	args = append(args, limit, offset)

	var invoices []struct {
		InvoiceID      uint      `json:"invoice_id"`
		InvoiceNo      string    `json:"invoice_no"`
		InvoiceDate    time.Time `json:"invoice_date"`
		Subtotal       float64   `json:"subtotal"`
		DiscountAmount float64   `json:"discount_amount"`
		TotalAmount    float64   `json:"total_amount"`
		PaymentMethod  *string   `json:"payment_method"`
		PointsEarned   int       `json:"points_earned"`
		PointsUsed     int       `json:"points_used"`
		CustomerName   *string   `json:"customer_name"`
		CustomerPhone  *string   `json:"customer_phone"`
		EmployeeName   string    `json:"employee_name"`
		ItemCount      int64     `json:"item_count"`
	}

	err := db.Raw(query, args...).Scan(&invoices).Error
	if err != nil {
		fmt.Printf("DEBUG: Database query error: %v\n", err)
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải danh sách hóa đơn: " + err.Error(),
			"Code":  500,
		})
	}

	fmt.Printf("DEBUG: Found %d invoices\n", len(invoices))

	// Get total count for pagination
	countQuery := `
		SELECT COUNT(DISTINCT si.invoice_id)
		FROM supermarket.sales_invoices si
		LEFT JOIN supermarket.customers c ON si.customer_id = c.customer_id
		JOIN supermarket.employees e ON si.employee_id = e.employee_id
		WHERE 1=1
	`

	countArgs := []interface{}{}
	countArgIndex := 1

	if search != "" {
		countQuery += fmt.Sprintf(" AND (si.invoice_no ILIKE $%d OR c.full_name ILIKE $%d OR e.full_name ILIKE $%d)", countArgIndex, countArgIndex, countArgIndex)
		countArgs = append(countArgs, "%"+search+"%")
		countArgIndex++
	}

	if customerID != "" {
		countQuery += fmt.Sprintf(" AND si.customer_id = $%d", countArgIndex)
		countArgs = append(countArgs, customerID)
		countArgIndex++
	}

	if employeeID != "" {
		countQuery += fmt.Sprintf(" AND si.employee_id = $%d", countArgIndex)
		countArgs = append(countArgs, employeeID)
		countArgIndex++
	}

	if dateFrom != "" {
		countQuery += fmt.Sprintf(" AND DATE(si.invoice_date) >= $%d", countArgIndex)
		countArgs = append(countArgs, dateFrom)
		countArgIndex++
	}

	if dateTo != "" {
		countQuery += fmt.Sprintf(" AND DATE(si.invoice_date) <= $%d", countArgIndex)
		countArgs = append(countArgs, dateTo)
		countArgIndex++
	}

	var totalCount int64
	err = db.Raw(countQuery, countArgs...).Scan(&totalCount).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể đếm số lượng hóa đơn: " + err.Error(),
			"Code":  500,
		})
	}

	// Get customers and employees for filters
	var customers []models.Customer
	db.Raw("SELECT customer_id, full_name, phone FROM supermarket.customers ORDER BY full_name").Scan(&customers)

	var employees []models.Employee
	db.Raw("SELECT employee_id, full_name FROM supermarket.employees ORDER BY full_name").Scan(&employees)

	totalPages := (totalCount + int64(limit) - 1) / int64(limit)

	fmt.Printf("DEBUG: About to render template with %d invoices, %d total\n", len(invoices), totalCount)

	data := fiber.Map{
		"Title":        "Quản lý bán hàng",
		"Active":       "sales",
		"Invoices":     invoices,
		"InvoiceCount": len(invoices),
		"Customers":    customers,
		"Employees":    employees,
		"Pagination": fiber.Map{
			"CurrentPage": page,
			"TotalPages":  totalPages,
			"TotalCount":  totalCount,
			"Limit":       limit,
		},
		"Filters": fiber.Map{
			"Search":     search,
			"CustomerID": customerID,
			"EmployeeID": employeeID,
			"DateFrom":   dateFrom,
			"DateTo":     dateTo,
		},
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}

	err = c.Render("pages/sales/list", data, "layouts/base")
	if err != nil {
		fmt.Printf("DEBUG: Template rendering error: %v\n", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Template rendering error: " + err.Error(),
		})
	}

	fmt.Println("DEBUG: Template rendered successfully")
	return nil
}

// SalesListSimple displays sales invoices with a simple template
func SalesListSimple(c *fiber.Ctx) error {
	fmt.Println("DEBUG: SalesListSimple handler called")
	db := database.GetDB()

	// Get query parameters
	page := c.QueryInt("page", 1)
	limit := c.QueryInt("limit", 20)
	offset := (page - 1) * limit

	// Simple query
	var invoices []struct {
		InvoiceID    uint      `json:"invoice_id"`
		InvoiceNo    string    `json:"invoice_no"`
		InvoiceDate  time.Time `json:"invoice_date"`
		TotalAmount  float64   `json:"total_amount"`
		CustomerName *string   `json:"customer_name"`
		EmployeeName string    `json:"employee_name"`
		ItemCount    int64     `json:"item_count"`
	}

	err := db.Raw(`
		SELECT 
			si.invoice_id,
			si.invoice_no,
			si.invoice_date,
			si.total_amount,
			c.full_name as customer_name,
			e.full_name as employee_name,
			COALESCE(item_counts.item_count, 0) as item_count
		FROM supermarket.sales_invoices si
		LEFT JOIN supermarket.customers c ON si.customer_id = c.customer_id
		JOIN supermarket.employees e ON si.employee_id = e.employee_id
		LEFT JOIN (
			SELECT invoice_id, COUNT(*) as item_count
			FROM supermarket.sales_invoice_details
			GROUP BY invoice_id
		) item_counts ON si.invoice_id = item_counts.invoice_id
		ORDER BY si.invoice_date DESC
		LIMIT $1 OFFSET $2
	`, limit, offset).Scan(&invoices).Error

	if err != nil {
		fmt.Printf("DEBUG: Database query error: %v\n", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Database error: " + err.Error(),
		})
	}

	// Get total count
	var totalCount int64
	err = db.Raw("SELECT COUNT(*) FROM supermarket.sales_invoices").Scan(&totalCount).Error
	if err != nil {
		fmt.Printf("DEBUG: Count query error: %v\n", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Count error: " + err.Error(),
		})
	}

	fmt.Printf("DEBUG: Found %d invoices, total: %d\n", len(invoices), totalCount)

	data := fiber.Map{
		"Title":        "Quản lý bán hàng (Simple)",
		"Invoices":     invoices,
		"InvoiceCount": len(invoices),
		"Pagination": fiber.Map{
			"TotalCount": totalCount,
		},
	}

	err = c.Render("pages/sales/list_simple", data, "layouts/base")
	if err != nil {
		fmt.Printf("DEBUG: Template rendering error: %v\n", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Template rendering error: " + err.Error(),
		})
	}

	fmt.Println("DEBUG: Simple template rendered successfully")
	return nil
}

// SalesNew displays the new sales invoice form
func SalesNew(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get all customers
	var customers []models.Customer
	err := db.Raw("SELECT customer_id, full_name, phone, membership_level_id, loyalty_points FROM supermarket.customers ORDER BY customer_id").Scan(&customers).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải danh sách khách hàng: " + err.Error(),
		})
	}

	// log customers
	// convert customer.FullName to string

	// Get all employees
	var employees []models.Employee
	err = db.Raw("SELECT employee_id, full_name FROM supermarket.employees ORDER BY full_name").Scan(&employees).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải danh sách nhân viên: " + err.Error(),
		})
	}

	// Get products with shelf inventory
	var products []struct {
		ProductID     uint       `json:"product_id"`
		ProductCode   string     `json:"product_code"`
		ProductName   string     `json:"product_name"`
		SellingPrice  float64    `json:"selling_price"`
		CategoryName  string     `json:"category_name"`
		ShelfQuantity int64      `json:"shelf_quantity"`
		ShelfName     string     `json:"shelf_name"`
		ExpiryDate    *time.Time `json:"expiry_date"`
		DaysToExpiry  int        `json:"days_to_expiry"`
		DiscountPrice *float64   `json:"discount_price"`
	}

	err = db.Raw(`
		SELECT DISTINCT
			p.product_id,
			p.product_code,
			p.product_name,
			p.selling_price,
			pc.category_name,
			COALESCE(si.current_quantity, 0) as shelf_quantity,
			ds.shelf_name,
			sbi.expiry_date,
			CASE 
				WHEN sbi.expiry_date IS NOT NULL 
				THEN supermarket.calculate_discount_price(p.product_id, sbi.expiry_date)
				ELSE NULL 
			END as discount_price
		FROM supermarket.products p
		LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
		LEFT JOIN supermarket.shelf_inventory si ON p.product_id = si.product_id
		LEFT JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
		LEFT JOIN supermarket.shelf_batch_inventory sbi ON si.shelf_id = sbi.shelf_id AND p.product_id = sbi.product_id AND sbi.quantity > 0
		WHERE si.current_quantity > 0
		ORDER BY p.product_name
	`).Scan(&products).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải danh sách sản phẩm: " + err.Error(),
		})
	}

	// Calculate days to expiry for each product
	for i := range products {
		if products[i].ExpiryDate != nil {
			now := time.Now()
			expiry := *products[i].ExpiryDate
			// Calculate days difference
			diff := expiry.Sub(now)
			products[i].DaysToExpiry = int(diff.Hours() / 24)
		} else {
			products[i].DaysToExpiry = 999999 // Large number to indicate no expiry
		}
	}

	// Get membership levels for customer benefits
	var membershipLevels []struct {
		LevelID            uint    `json:"level_id"`
		LevelName          string  `json:"level_name"`
		DiscountPercentage float64 `json:"discount_percentage"`
		PointsMultiplier   float64 `json:"points_multiplier"`
		MinSpending        float64 `json:"min_spending"`
	}

	err = db.Raw("SELECT level_id, level_name, discount_percentage, points_multiplier, min_spending FROM supermarket.membership_levels ORDER BY min_spending").Scan(&membershipLevels).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải thông tin thành viên: " + err.Error(),
		})
	}

	return c.Render("pages/sales/form", fiber.Map{
		"Title":            "Tạo hóa đơn bán hàng",
		"Active":           "sales",
		"Customers":        customers,
		"Employees":        employees,
		"Products":         products,
		"MembershipLevels": membershipLevels,
		"SQLQueries":       c.Locals("SQLQueries"),
		"TotalSQLQueries":  c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// SalesCreate processes the new sales invoice creation
func SalesCreate(c *fiber.Ctx) error {
	db := database.GetDB()

	// Parse form data
	customerIDStr := c.FormValue("customer_id")
	employeeIDStr := c.FormValue("employee_id")
	paymentMethod := c.FormValue("payment_method")
	pointsUsedStr := c.FormValue("points_used")
	notes := c.FormValue("notes")

	// Validate required fields
	if employeeIDStr == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Vui lòng chọn nhân viên bán hàng",
		})
	}

	employeeID, err := strconv.ParseUint(employeeIDStr, 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "ID nhân viên không hợp lệ",
		})
	}

	pointsUsed := 0
	if pointsUsedStr != "" {
		pointsUsed, err = strconv.Atoi(pointsUsedStr)
		if err != nil || pointsUsed < 0 {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "Số điểm sử dụng không hợp lệ",
			})
		}
	}

	// Parse products from form
	productIDs := c.FormValue("product_ids")
	quantities := c.FormValue("quantities")
	unitPrices := c.FormValue("unit_prices")
	discountPercentages := c.FormValue("discount_percentages")

	if productIDs == "" || quantities == "" || unitPrices == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Vui lòng chọn ít nhất một sản phẩm",
		})
	}

	// Parse arrays (assuming they're comma-separated)
	productIDList := parseStringArray(productIDs)
	quantityList := parseStringArray(quantities)
	unitPriceList := parseStringArray(unitPrices)
	discountList := parseStringArray(discountPercentages)

	if len(productIDList) != len(quantityList) || len(productIDList) != len(unitPriceList) {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Dữ liệu sản phẩm không hợp lệ",
		})
	}

	// Generate unique invoice number with retry logic
	var invoiceNo string
	var invoiceID uint
	maxRetries := 10

	for i := 0; i < maxRetries; i++ {
		// Use timestamp + microseconds + retry counter for uniqueness
		timestamp := time.Now()
		invoiceNo = fmt.Sprintf("HD%s%06d", timestamp.Format("20060102"), timestamp.Nanosecond()/1000+i)

		// Check if invoice_no already exists
		var count int64
		err = db.Raw("SELECT COUNT(*) FROM supermarket.sales_invoices WHERE invoice_no = $1", invoiceNo).Scan(&count).Error
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Không thể kiểm tra số hóa đơn: " + err.Error(),
			})
		}

		if count == 0 {
			break // Found unique invoice_no
		}

		if i == maxRetries-1 {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Không thể tạo số hóa đơn duy nhất",
			})
		}
	}

	// Start transaction
	tx := db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// Create sales invoice
	err = tx.Raw(`
		INSERT INTO supermarket.sales_invoices 
		(invoice_no, customer_id, employee_id, invoice_date, payment_method, points_used, notes)
		VALUES ($1, $2, $3, CURRENT_TIMESTAMP, $4, $5, $6)
		RETURNING invoice_id
	`, invoiceNo, customerIDStr, employeeID, paymentMethod, pointsUsed, notes).Scan(&invoiceID).Error

	if err != nil {
		tx.Rollback()
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể tạo hóa đơn: " + err.Error(),
		})
	}

	// Add invoice details
	for i, productIDStr := range productIDList {
		productID, err := strconv.ParseUint(productIDStr, 10, 64)
		if err != nil {
			tx.Rollback()
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "ID sản phẩm không hợp lệ: " + productIDStr,
			})
		}

		quantity, err := strconv.Atoi(quantityList[i])
		if err != nil || quantity <= 0 {
			tx.Rollback()
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "Số lượng không hợp lệ: " + quantityList[i],
			})
		}

		unitPrice, err := strconv.ParseFloat(unitPriceList[i], 64)
		if err != nil || unitPrice <= 0 {
			tx.Rollback()
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "Giá đơn vị không hợp lệ: " + unitPriceList[i],
			})
		}

		discountPercentage := 0.0
		if i < len(discountList) && discountList[i] != "" {
			discountPercentage, err = strconv.ParseFloat(discountList[i], 64)
			if err != nil || discountPercentage < 0 || discountPercentage > 100 {
				tx.Rollback()
				return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
					"error": "Phần trăm giảm giá không hợp lệ: " + discountList[i],
				})
			}
		}

		// Insert invoice detail - triggers will handle calculations and stock deduction
		err = tx.Exec(`
			INSERT INTO supermarket.sales_invoice_details 
			(invoice_id, product_id, quantity, unit_price, discount_percentage)
			VALUES ($1, $2, $3, $4, $5)
		`, invoiceID, productID, quantity, unitPrice, discountPercentage).Error

		if err != nil {
			tx.Rollback()
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Không thể thêm chi tiết hóa đơn: " + err.Error(),
			})
		}
	}

	// Commit transaction
	if err := tx.Commit().Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Không thể hoàn tất giao dịch: " + err.Error(),
		})
	}

	// Return success response
	if c.Get("Content-Type") == "application/json" {
		return c.JSON(fiber.Map{
			"success":    true,
			"invoice_id": invoiceID,
			"invoice_no": invoiceNo,
			"message":    "Tạo hóa đơn thành công",
		})
	}

	// Redirect to invoice view
	return c.Redirect(fmt.Sprintf("/sales/invoice/%d", invoiceID))
}

// SalesView displays a specific sales invoice
func SalesView(c *fiber.Ctx) error {
	db := database.GetDB()

	invoiceIDStr := c.Params("id")
	invoiceID, err := strconv.ParseUint(invoiceIDStr, 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "ID hóa đơn không hợp lệ",
			"Code":  400,
		})
	}

	// Get invoice details
	var invoice struct {
		models.SalesInvoice
		CustomerName    *string `json:"customer_name"`
		CustomerPhone   *string `json:"customer_phone"`
		CustomerEmail   *string `json:"customer_email"`
		EmployeeName    string  `json:"employee_name"`
		MembershipLevel *string `json:"membership_level"`
	}

	err = db.Raw(`
		SELECT 
			si.*,
			c.full_name as customer_name,
			c.phone as customer_phone,
			c.email as customer_email,
			e.full_name as employee_name,
			ml.level_name as membership_level
		FROM supermarket.sales_invoices si
		LEFT JOIN supermarket.customers c ON si.customer_id = c.customer_id
		LEFT JOIN supermarket.membership_levels ml ON c.membership_level_id = ml.level_id
		JOIN supermarket.employees e ON si.employee_id = e.employee_id
		WHERE si.invoice_id = $1
	`, invoiceID).Scan(&invoice).Error

	if err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không tìm thấy hóa đơn",
			"Code":  404,
		})
	}

	// Get invoice items
	var items []struct {
		models.SalesInvoiceDetail
		ProductCode  string     `json:"product_code"`
		ProductName  string     `json:"product_name"`
		CategoryName string     `json:"category_name"`
		ShelfName    string     `json:"shelf_name"`
		ExpiryDate   *time.Time `json:"expiry_date"`
		DaysToExpiry int        `json:"days_to_expiry"`
	}

	err = db.Raw(`
		SELECT 
			sid.*,
			p.product_code,
			p.product_name,
			pc.category_name,
			ds.shelf_name,
			sbi.expiry_date
		FROM supermarket.sales_invoice_details sid
		JOIN supermarket.products p ON sid.product_id = p.product_id
		LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
		LEFT JOIN supermarket.shelf_inventory si ON p.product_id = si.product_id
		LEFT JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
		LEFT JOIN (
			-- Chỉ lấy 1 batch cho mỗi sản phẩm dựa trên thời gian mua hàng
			SELECT DISTINCT ON (sbi.product_id, sbi.shelf_id)
				sbi.shelf_id,
				sbi.product_id,
				sbi.expiry_date,
				sbi.stocked_date,
				sbi.batch_code
			FROM supermarket.shelf_batch_inventory sbi
			JOIN supermarket.sales_invoices si ON si.invoice_id = $1
			WHERE sbi.quantity > 0
			ORDER BY sbi.product_id, sbi.shelf_id, 
				-- Ưu tiên batch có stocked_date gần nhất với thời gian mua hàng
				ABS(EXTRACT(EPOCH FROM (sbi.stocked_date - si.invoice_date))),
				-- Nếu cùng thời gian, chọn batch có expiry_date sớm nhất (FIFO)
				sbi.expiry_date ASC NULLS LAST
		) sbi ON si.shelf_id = sbi.shelf_id AND p.product_id = sbi.product_id
		WHERE sid.invoice_id = $1
		ORDER BY sid.detail_id
	`, invoiceID).Scan(&items).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải chi tiết hóa đơn: " + err.Error(),
		})
	}

	// Calculate days to expiry for each item
	for i := range items {
		if items[i].ExpiryDate != nil {
			now := time.Now()
			expiry := *items[i].ExpiryDate
			// Calculate days difference
			diff := expiry.Sub(now)
			items[i].DaysToExpiry = int(diff.Hours() / 24)
		} else {
			items[i].DaysToExpiry = 999999 // Large number to indicate no expiry
		}
	}

	return c.Render("pages/sales/view", fiber.Map{
		"Title":           "Chi tiết hóa đơn",
		"Active":          "sales",
		"Invoice":         invoice,
		"Items":           items,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// SalesInvoice displays printable invoice
func SalesInvoice(c *fiber.Ctx) error {
	db := database.GetDB()

	invoiceIDStr := c.Params("id")
	invoiceID, err := strconv.ParseUint(invoiceIDStr, 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "ID hóa đơn không hợp lệ",
			"Code":  400,
		})
	}

	// Get invoice details
	var invoice struct {
		models.SalesInvoice
		CustomerName    *string `json:"customer_name"`
		CustomerPhone   *string `json:"customer_phone"`
		CustomerEmail   *string `json:"customer_email"`
		CustomerAddress *string `json:"customer_address"`
		EmployeeName    string  `json:"employee_name"`
		MembershipLevel *string `json:"membership_level"`
		StoreName       string  `json:"store_name"`
		StoreAddress    string  `json:"store_address"`
		StorePhone      string  `json:"store_phone"`
	}

	err = db.Raw(`
		SELECT 
			si.*,
			c.full_name as customer_name,
			c.phone as customer_phone,
			c.email as customer_email,
			c.address as customer_address,
			e.full_name as employee_name,
			ml.level_name as membership_level,
			'Siêu thị ABC' as store_name,
			'123 Đường ABC, Quận 1, TP.HCM' as store_address,
			'(028) 1234-5678' as store_phone
		FROM supermarket.sales_invoices si
		LEFT JOIN supermarket.customers c ON si.customer_id = c.customer_id
		LEFT JOIN supermarket.membership_levels ml ON c.membership_level_id = ml.level_id
		JOIN supermarket.employees e ON si.employee_id = e.employee_id
		WHERE si.invoice_id = $1
	`, invoiceID).Scan(&invoice).Error

	if err != nil {
		return c.Status(fiber.StatusNotFound).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không tìm thấy hóa đơn",
			"Code":  404,
		})
	}

	// Get invoice items
	var items []struct {
		models.SalesInvoiceDetail
		ProductCode  string `json:"product_code"`
		ProductName  string `json:"product_name"`
		CategoryName string `json:"category_name"`
		Unit         string `json:"unit"`
	}

	err = db.Raw(`
		SELECT 
			sid.*,
			p.product_code,
			p.product_name,
			pc.category_name,
			COALESCE(p.unit, 'cái') as unit
		FROM supermarket.sales_invoice_details sid
		JOIN supermarket.products p ON sid.product_id = p.product_id
		LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
		WHERE sid.invoice_id = $1
		ORDER BY sid.detail_id
	`, invoiceID).Scan(&items).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải chi tiết hóa đơn: " + err.Error(),
		})
	}

	return c.Render("pages/sales/invoice", fiber.Map{
		"Title":           "Hóa đơn bán hàng",
		"Invoice":         invoice,
		"Items":           items,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// Helper function to parse comma-separated string arrays
func parseStringArray(str string) []string {
	if str == "" {
		return []string{}
	}

	var result []string
	for _, s := range strings.Split(str, ",") {
		s = strings.TrimSpace(s)
		if s != "" {
			result = append(result, s)
		}
	}
	return result
}
