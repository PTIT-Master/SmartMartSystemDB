package handlers

import (
	"fmt"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/supermarket/database"
)

// ReportsOverview displays the main reports dashboard
func ReportsOverview(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get date range (last 30 days by default)
	dateFrom := time.Now().AddDate(0, 0, -30).Format("2006-01-02")
	dateTo := time.Now().Format("2006-01-02")

	// Quick stats
	var stats struct {
		TotalRevenue    float64 `json:"total_revenue"`
		TotalInvoices   int64   `json:"total_invoices"`
		TotalCustomers  int64   `json:"total_customers"`
		AvgInvoiceValue float64 `json:"avg_invoice_value"`
		TopProduct      string  `json:"top_product"`
		TopCategory     string  `json:"top_category"`
		TopEmployee     string  `json:"top_employee"`
	}

	err := db.Raw(`
		SELECT 
			COALESCE(SUM(total_amount), 0) as total_revenue,
			COUNT(invoice_id) as total_invoices,
			COUNT(DISTINCT customer_id) as total_customers,
			COALESCE(AVG(total_amount), 0) as avg_invoice_value
		FROM supermarket.sales_invoices
		WHERE DATE(invoice_date) BETWEEN $1 AND $2
	`, dateFrom, dateTo).Scan(&stats).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải thống kê: " + err.Error(),
		})
	}

	// Get top product
	var topProduct struct {
		ProductName string `json:"product_name"`
	}
	db.Raw(`
		SELECT p.product_name
		FROM supermarket.sales_invoice_details sid
		JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
		JOIN supermarket.products p ON sid.product_id = p.product_id
		WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
		GROUP BY p.product_id, p.product_name
		ORDER BY SUM(sid.quantity) DESC
		LIMIT 1
	`, dateFrom, dateTo).Scan(&topProduct)
	stats.TopProduct = topProduct.ProductName

	// Get top category
	var topCategory struct {
		CategoryName string `json:"category_name"`
	}
	db.Raw(`
		SELECT pc.category_name
		FROM supermarket.sales_invoice_details sid
		JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
		JOIN supermarket.products p ON sid.product_id = p.product_id
		LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
		WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
		GROUP BY pc.category_id, pc.category_name
		ORDER BY SUM(sid.subtotal) DESC
		LIMIT 1
	`, dateFrom, dateTo).Scan(&topCategory)
	stats.TopCategory = topCategory.CategoryName

	// Get top employee
	var topEmployee struct {
		EmployeeName string `json:"employee_name"`
	}
	db.Raw(`
		SELECT e.full_name as employee_name
		FROM supermarket.sales_invoices si
		JOIN supermarket.employees e ON si.employee_id = e.employee_id
		WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
		GROUP BY e.employee_id, e.full_name
		ORDER BY SUM(si.total_amount) DESC
		LIMIT 1
	`, dateFrom, dateTo).Scan(&topEmployee)
	stats.TopEmployee = topEmployee.EmployeeName

	// Recent sales trend (last 7 days)
	var trendData []struct {
		Date     string  `json:"date"`
		Revenue  float64 `json:"revenue"`
		Invoices int64   `json:"invoices"`
	}

	err = db.Raw(`
        SELECT 
            DATE(invoice_date)::text as date,
            SUM(total_amount) as revenue,
            COUNT(invoice_id) as invoices
        FROM supermarket.sales_invoices
        WHERE DATE(invoice_date) BETWEEN $1 AND $2
        GROUP BY DATE(invoice_date)
        ORDER BY DATE(invoice_date) DESC
        LIMIT 7
    `, dateFrom, dateTo).Scan(&trendData).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải xu hướng bán hàng: " + err.Error(),
		})
	}

	return c.Render("pages/reports/overview", fiber.Map{
		"Title":           "Báo cáo thống kê",
		"Active":          "reports",
		"Stats":           stats,
		"TrendData":       trendData,
		"DateFrom":        dateFrom,
		"DateTo":          dateTo,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// SalesReport displays sales statistics and reports
func SalesReport(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get query parameters
	dateFrom := c.Query("date_from", time.Now().AddDate(0, -1, 0).Format("2006-01-02"))
	dateTo := c.Query("date_to", time.Now().Format("2006-01-02"))
	groupBy := c.Query("group_by", "day") // day, week, month

	// Sales summary
	var summary struct {
		TotalInvoices   int64   `json:"total_invoices"`
		TotalRevenue    float64 `json:"total_revenue"`
		TotalCustomers  int64   `json:"total_customers"`
		AvgInvoiceValue float64 `json:"avg_invoice_value"`
		TotalDiscount   float64 `json:"total_discount"`
		TotalTax        float64 `json:"total_tax"`
		PointsEarned    int64   `json:"points_earned"`
		PointsUsed      int64   `json:"points_used"`
	}

	err := db.Raw(`
		SELECT 
			COUNT(DISTINCT si.invoice_id) as total_invoices,
			COALESCE(SUM(si.total_amount), 0) as total_revenue,
			COUNT(DISTINCT si.customer_id) as total_customers,
			COALESCE(AVG(si.total_amount), 0) as avg_invoice_value,
			COALESCE(SUM(si.discount_amount), 0) as total_discount,
			COALESCE(SUM(si.tax_amount), 0) as total_tax,
			COALESCE(SUM(si.points_earned), 0) as points_earned,
			COALESCE(SUM(si.points_used), 0) as points_used
		FROM supermarket.sales_invoices si
		WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
	`, dateFrom, dateTo).Scan(&summary).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải thống kê bán hàng: " + err.Error(),
		})
	}

	// Daily/Weekly/Monthly sales trend
	var trendData []struct {
		Period    string  `json:"period"`
		Revenue   float64 `json:"revenue"`
		Invoices  int64   `json:"invoices"`
		Customers int64   `json:"customers"`
	}

	var trendQuery string
	switch groupBy {
	case "week":
		trendQuery = `
			SELECT 
				TO_CHAR(DATE_TRUNC('week', si.invoice_date), 'YYYY-"W"WW') as period,
				COALESCE(SUM(si.total_amount), 0) as revenue,
				COUNT(DISTINCT si.invoice_id) as invoices,
				COUNT(DISTINCT si.customer_id) as customers
			FROM supermarket.sales_invoices si
			WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
			GROUP BY DATE_TRUNC('week', si.invoice_date)
			ORDER BY DATE_TRUNC('week', si.invoice_date) DESC
		`
	case "month":
		trendQuery = `
			SELECT 
				TO_CHAR(DATE_TRUNC('month', si.invoice_date), 'YYYY-MM') as period,
				COALESCE(SUM(si.total_amount), 0) as revenue,
				COUNT(DISTINCT si.invoice_id) as invoices,
				COUNT(DISTINCT si.customer_id) as customers
			FROM supermarket.sales_invoices si
			WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
			GROUP BY DATE_TRUNC('month', si.invoice_date)
			ORDER BY DATE_TRUNC('month', si.invoice_date) DESC
		`
	default: // day
		trendQuery = `
			SELECT 
				TO_CHAR(DATE(si.invoice_date), 'YYYY-MM-DD') as period,
				COALESCE(SUM(si.total_amount), 0) as revenue,
				COUNT(DISTINCT si.invoice_id) as invoices,
				COUNT(DISTINCT si.customer_id) as customers
			FROM supermarket.sales_invoices si
			WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
			GROUP BY DATE(si.invoice_date)
			ORDER BY DATE(si.invoice_date) DESC
		`
	}

	err = db.Raw(trendQuery, dateFrom, dateTo).Scan(&trendData).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải xu hướng bán hàng: " + err.Error(),
		})
	}

	// Top selling products
	var topProducts []struct {
		ProductID    uint    `json:"product_id"`
		ProductCode  string  `json:"product_code"`
		ProductName  string  `json:"product_name"`
		CategoryName string  `json:"category_name"`
		TotalSold    int64   `json:"total_sold"`
		TotalRevenue float64 `json:"total_revenue"`
		AvgPrice     float64 `json:"avg_price"`
	}

	err = db.Raw(`
		SELECT 
			p.product_id,
			p.product_code,
			p.product_name,
			pc.category_name,
			SUM(sid.quantity) as total_sold,
			SUM(sid.subtotal) as total_revenue,
			AVG(sid.unit_price) as avg_price
		FROM supermarket.sales_invoice_details sid
		JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
		JOIN supermarket.products p ON sid.product_id = p.product_id
		LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
		WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
		GROUP BY p.product_id, p.product_code, p.product_name, pc.category_name
		ORDER BY total_sold DESC
		LIMIT 10
	`, dateFrom, dateTo).Scan(&topProducts).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải sản phẩm bán chạy: " + err.Error(),
		})
	}

	// Payment method analysis
	var paymentMethods []struct {
		PaymentMethod string  `json:"payment_method"`
		Count         int64   `json:"count"`
		TotalAmount   float64 `json:"total_amount"`
		Percentage    float64 `json:"percentage"`
	}

	err = db.Raw(`
		SELECT 
			COALESCE(si.payment_method, 'UNKNOWN') as payment_method,
			COUNT(*) as count,
			SUM(si.total_amount) as total_amount,
			ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
		FROM supermarket.sales_invoices si
		WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
		GROUP BY si.payment_method
		ORDER BY count DESC
	`, dateFrom, dateTo).Scan(&paymentMethods).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải phân tích phương thức thanh toán: " + err.Error(),
		})
	}

	// Employee performance
	var employeePerformance []struct {
		EmployeeID   uint    `json:"employee_id"`
		EmployeeName string  `json:"employee_name"`
		TotalSales   int64   `json:"total_sales"`
		TotalRevenue float64 `json:"total_revenue"`
		AvgInvoice   float64 `json:"avg_invoice"`
	}

	err = db.Raw(`
		SELECT 
			e.employee_id,
			e.full_name as employee_name,
			COUNT(si.invoice_id) as total_sales,
			SUM(si.total_amount) as total_revenue,
			AVG(si.total_amount) as avg_invoice
		FROM supermarket.sales_invoices si
		JOIN supermarket.employees e ON si.employee_id = e.employee_id
		WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
		GROUP BY e.employee_id, e.full_name
		ORDER BY total_revenue DESC
	`, dateFrom, dateTo).Scan(&employeePerformance).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải hiệu suất nhân viên: " + err.Error(),
		})
	}

	return c.Render("pages/reports/sales", fiber.Map{
		"Title":               "Báo cáo bán hàng",
		"Active":              "reports",
		"Summary":             summary,
		"TrendData":           trendData,
		"TopProducts":         topProducts,
		"PaymentMethods":      paymentMethods,
		"EmployeePerformance": employeePerformance,
		"Filters": fiber.Map{
			"DateFrom": dateFrom,
			"DateTo":   dateTo,
			"GroupBy":  groupBy,
		},
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// ProductReport displays product performance analysis
func ProductReport(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get query parameters
	dateFrom := c.Query("date_from", time.Now().AddDate(0, -1, 0).Format("2006-01-02"))
	dateTo := c.Query("date_to", time.Now().Format("2006-01-02"))
	categoryID := c.Query("category_id", "")

	// Build query
	query := `
		SELECT 
			p.product_id,
			p.product_code,
			p.product_name,
			pc.category_name,
			SUM(sid.quantity) as total_sold,
			SUM(sid.subtotal) as total_revenue,
			AVG(sid.unit_price) as avg_price,
			COUNT(DISTINCT si.invoice_id) as invoice_count,
			COUNT(DISTINCT si.customer_id) as customer_count
		FROM supermarket.sales_invoice_details sid
		JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
		JOIN supermarket.products p ON sid.product_id = p.product_id
		LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
		WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
	`

	args := []interface{}{dateFrom, dateTo}
	argIndex := 3

	if categoryID != "" {
		query += fmt.Sprintf(" AND p.category_id = $%d", argIndex)
		args = append(args, categoryID)
		argIndex++
	}

	query += `
		GROUP BY p.product_id, p.product_code, p.product_name, pc.category_name
		ORDER BY total_sold DESC
	`

	var products []struct {
		ProductID     uint    `json:"product_id"`
		ProductCode   string  `json:"product_code"`
		ProductName   string  `json:"product_name"`
		CategoryName  string  `json:"category_name"`
		TotalSold     int64   `json:"total_sold"`
		TotalRevenue  float64 `json:"total_revenue"`
		AvgPrice      float64 `json:"avg_price"`
		InvoiceCount  int64   `json:"invoice_count"`
		CustomerCount int64   `json:"customer_count"`
	}

	err := db.Raw(query, args...).Scan(&products).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải báo cáo sản phẩm: " + err.Error(),
		})
	}

	// Get categories for filter
	var categories []struct {
		CategoryID   uint   `json:"category_id"`
		CategoryName string `json:"category_name"`
	}

	err = db.Raw("SELECT category_id, category_name FROM supermarket.product_categories ORDER BY category_name").Scan(&categories).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải danh mục: " + err.Error(),
		})
	}

	return c.Render("pages/reports/products", fiber.Map{
		"Title":      "Báo cáo sản phẩm",
		"Active":     "reports",
		"Products":   products,
		"Categories": categories,
		"Filters": fiber.Map{
			"DateFrom":   dateFrom,
			"DateTo":     dateTo,
			"CategoryID": categoryID,
		},
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// RevenueReport displays revenue analysis
func RevenueReport(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get query parameters
	dateFrom := c.Query("date_from", time.Now().AddDate(0, -1, 0).Format("2006-01-02"))
	dateTo := c.Query("date_to", time.Now().Format("2006-01-02"))

	// Revenue by period
	var revenueData []struct {
		Period         string  `json:"period"`
		TotalRevenue   float64 `json:"total_revenue"`
		TotalInvoices  int64   `json:"total_invoices"`
		AvgInvoice     float64 `json:"avg_invoice"`
		TotalCustomers int64   `json:"total_customers"`
	}

	err := db.Raw(`
        SELECT 
            DATE(si.invoice_date)::text as period,
            SUM(si.total_amount) as total_revenue,
            COUNT(si.invoice_id) as total_invoices,
            AVG(si.total_amount) as avg_invoice,
            COUNT(DISTINCT si.customer_id) as total_customers
        FROM supermarket.sales_invoices si
        WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
        GROUP BY DATE(si.invoice_date)
        ORDER BY DATE(si.invoice_date) DESC
    `, dateFrom, dateTo).Scan(&revenueData).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải dữ liệu doanh thu: " + err.Error(),
		})
	}

	// Revenue by category
	var categoryRevenue []struct {
		CategoryName string  `json:"category_name"`
		TotalRevenue float64 `json:"total_revenue"`
		TotalSold    int64   `json:"total_sold"`
		AvgPrice     float64 `json:"avg_price"`
	}

	err = db.Raw(`
		SELECT 
			pc.category_name,
			SUM(sid.subtotal) as total_revenue,
			SUM(sid.quantity) as total_sold,
			AVG(sid.unit_price) as avg_price
		FROM supermarket.sales_invoice_details sid
		JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
		JOIN supermarket.products p ON sid.product_id = p.product_id
		LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
		WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
		GROUP BY pc.category_name
		ORDER BY total_revenue DESC
	`, dateFrom, dateTo).Scan(&categoryRevenue).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải doanh thu theo danh mục: " + err.Error(),
		})
	}

	// Revenue summary
	var summary struct {
		TotalRevenue    float64 `json:"total_revenue"`
		TotalDiscount   float64 `json:"total_discount"`
		TotalTax        float64 `json:"total_tax"`
		NetRevenue      float64 `json:"net_revenue"`
		TotalInvoices   int64   `json:"total_invoices"`
		AvgInvoiceValue float64 `json:"avg_invoice_value"`
	}

	err = db.Raw(`
		SELECT 
			SUM(total_amount) as total_revenue,
			SUM(discount_amount) as total_discount,
			SUM(tax_amount) as total_tax,
			SUM(total_amount - discount_amount) as net_revenue,
			COUNT(invoice_id) as total_invoices,
			AVG(total_amount) as avg_invoice_value
		FROM supermarket.sales_invoices
		WHERE DATE(invoice_date) BETWEEN $1 AND $2
	`, dateFrom, dateTo).Scan(&summary).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải tổng kết doanh thu: " + err.Error(),
		})
	}

	return c.Render("pages/reports/revenue", fiber.Map{
		"Title":           "Báo cáo doanh thu",
		"Active":          "reports",
		"RevenueData":     revenueData,
		"CategoryRevenue": categoryRevenue,
		"Summary":         summary,
		"Filters": fiber.Map{
			"DateFrom": dateFrom,
			"DateTo":   dateTo,
		},
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// SupplierReport displays supplier performance analysis
func SupplierReport(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get query parameters
	dateFrom := c.Query("date_from", time.Now().AddDate(0, -1, 0).Format("2006-01-02"))
	dateTo := c.Query("date_to", time.Now().Format("2006-01-02"))

	// Supplier revenue analysis
	var supplierRevenue []struct {
		SupplierID   uint    `json:"supplier_id"`
		SupplierName string  `json:"supplier_name"`
		ContactPhone string  `json:"contact_phone"`
		TotalRevenue float64 `json:"total_revenue"`
		TotalSold    int64   `json:"total_sold"`
		ProductCount int64   `json:"product_count"`
		AvgPrice     float64 `json:"avg_price"`
	}

	err := db.Raw(`
        SELECT 
            s.supplier_id,
            s.supplier_name,
            COALESCE(s.phone, '') as contact_phone,
            SUM(sid.subtotal) as total_revenue,
            SUM(sid.quantity) as total_sold,
            COUNT(DISTINCT p.product_id) as product_count,
            AVG(sid.unit_price) as avg_price
        FROM supermarket.sales_invoice_details sid
        JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
        JOIN supermarket.products p ON sid.product_id = p.product_id
        JOIN supermarket.suppliers s ON p.supplier_id = s.supplier_id
        WHERE DATE(si.invoice_date) BETWEEN $1 AND $2
        GROUP BY s.supplier_id, s.supplier_name, s.phone
        ORDER BY total_revenue DESC
    `, dateFrom, dateTo).Scan(&supplierRevenue).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải báo cáo nhà cung cấp: " + err.Error(),
		})
	}

	return c.Render("pages/reports/suppliers", fiber.Map{
		"Title":           "Báo cáo nhà cung cấp",
		"Active":          "reports",
		"SupplierRevenue": supplierRevenue,
		"Filters": fiber.Map{
			"DateFrom": dateFrom,
			"DateTo":   dateTo,
		},
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// CustomerReport displays customer analysis
func CustomerReport(c *fiber.Ctx) error {
	db := database.GetDB()

	// Get query parameters
	dateFrom := c.Query("date_from", time.Now().AddDate(0, -1, 0).Format("2006-01-02"))
	dateTo := c.Query("date_to", time.Now().Format("2006-01-02"))
	membershipLevel := c.Query("membership_level", "")

	// Build query
	query := `
		SELECT 
			c.customer_id,
			c.full_name,
			c.phone,
			c.email,
			ml.level_name as membership_level,
			COUNT(si.invoice_id) as total_orders,
			SUM(si.total_amount) as total_spending,
			AVG(si.total_amount) as avg_order_value,
			MAX(si.invoice_date) as last_purchase,
			SUM(si.points_earned) as total_points_earned,
			c.loyalty_points as current_points
		FROM supermarket.customers c
		LEFT JOIN supermarket.membership_levels ml ON c.membership_level_id = ml.level_id
		LEFT JOIN supermarket.sales_invoices si ON c.customer_id = si.customer_id 
			AND DATE(si.invoice_date) BETWEEN $1 AND $2
		WHERE 1=1
	`

	args := []interface{}{dateFrom, dateTo}
	argIndex := 3

	if membershipLevel != "" {
		query += fmt.Sprintf(" AND ml.level_id = $%d", argIndex)
		args = append(args, membershipLevel)
		argIndex++
	}

	query += `
		GROUP BY c.customer_id, c.full_name, c.phone, c.email, ml.level_name, c.loyalty_points
		ORDER BY total_spending DESC NULLS LAST
	`

	var customers []struct {
		CustomerID        uint       `json:"customer_id"`
		FullName          string     `json:"full_name"`
		Phone             string     `json:"phone"`
		Email             *string    `json:"email"`
		MembershipLevel   *string    `json:"membership_level"`
		TotalOrders       int64      `json:"total_orders"`
		TotalSpending     *float64   `json:"total_spending"`
		AvgOrderValue     *float64   `json:"avg_order_value"`
		LastPurchase      *time.Time `json:"last_purchase"`
		TotalPointsEarned *int64     `json:"total_points_earned"`
		CurrentPoints     int        `json:"current_points"`
	}

	err := db.Raw(query, args...).Scan(&customers).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải báo cáo khách hàng: " + err.Error(),
		})
	}

	// Get membership levels for filter
	var membershipLevels []struct {
		LevelID   uint   `json:"level_id"`
		LevelName string `json:"level_name"`
	}

	err = db.Raw("SELECT level_id, level_name FROM supermarket.membership_levels ORDER BY min_spending").Scan(&membershipLevels).Error
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).Render("pages/error", fiber.Map{
			"Title": "Lỗi",
			"Error": "Không thể tải cấp độ thành viên: " + err.Error(),
		})
	}

	return c.Render("pages/reports/customers", fiber.Map{
		"Title":            "Báo cáo khách hàng",
		"Active":           "reports",
		"Customers":        customers,
		"MembershipLevels": membershipLevels,
		"Filters": fiber.Map{
			"DateFrom":        dateFrom,
			"DateTo":          dateTo,
			"MembershipLevel": membershipLevel,
		},
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}
