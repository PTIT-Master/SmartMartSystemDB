package handlers

import (
	"fmt"
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/supermarket/database"
	"github.com/supermarket/models"
)

// PurchaseOrderList displays all purchase orders
func PurchaseOrderList(c *fiber.Ctx) error {
	var orders []models.PurchaseOrder
	var suppliers []models.Supplier
	var employees []models.Employee

	// Get all orders with related data
	if err := database.DB.Preload("Supplier").Preload("Employee").Order("order_date DESC").Find(&orders).Error; err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to fetch purchase orders"})
	}

	// Get suppliers and employees for form
	if err := database.DB.Find(&suppliers).Error; err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to fetch suppliers"})
	}

	if err := database.DB.Find(&employees).Error; err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to fetch employees"})
	}

	return c.Render("pages/purchase_orders/list", fiber.Map{
		"Title":           "Quản lý đơn đặt hàng",
		"Active":          "purchase-orders",
		"Orders":          orders,
		"Suppliers":       suppliers,
		"Employees":       employees,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// PurchaseOrderNew displays the form to create a new purchase order
func PurchaseOrderNew(c *fiber.Ctx) error {
	var suppliers []models.Supplier
	var employees []models.Employee
	var products []models.Product

	// Get query parameters
	productID := c.Query("product")

	// Get suppliers and employees
	if err := database.DB.Find(&suppliers).Error; err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to fetch suppliers"})
	}

	if err := database.DB.Find(&employees).Error; err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to fetch employees"})
	}

	// Get products
	if err := database.DB.Find(&products).Error; err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to fetch products"})
	}

	// If product ID is specified, pre-select it
	var selectedProduct *models.Product
	if productID != "" {
		if id, err := strconv.ParseUint(productID, 10, 32); err == nil {
			if err := database.DB.Preload("Supplier").First(&selectedProduct, id).Error; err == nil {
				// Find the supplier for this product
				for _, supplier := range suppliers {
					if supplier.SupplierID == selectedProduct.SupplierID {
						break
					}
				}
			}
		}
	}

	return c.Render("pages/purchase_orders/form", fiber.Map{
		"Title":           "Tạo đơn đặt hàng mới",
		"Active":          "purchase-orders",
		"Suppliers":       suppliers,
		"Employees":       employees,
		"Products":        products,
		"SelectedProduct": selectedProduct,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// PurchaseOrderCreate creates a new purchase order
func PurchaseOrderCreate(c *fiber.Ctx) error {
	var order models.PurchaseOrder
	var details []models.PurchaseOrderDetail

	// Parse form data
	supplierID, err := strconv.ParseUint(c.FormValue("supplier_id"), 10, 32)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid supplier ID"})
	}

	employeeID, err := strconv.ParseUint(c.FormValue("employee_id"), 10, 32)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid employee ID"})
	}

	// Generate order number
	var count int64
	database.DB.Model(&models.PurchaseOrder{}).Count(&count)
	orderCounter := int(count) + 1
	orderNo := fmt.Sprintf("PO%s%03d", time.Now().Format("200601"), orderCounter)

	// Create purchase order
	order = models.PurchaseOrder{
		OrderNo:    orderNo,
		SupplierID: uint(supplierID),
		EmployeeID: uint(employeeID),
		OrderDate:  time.Now(),
		Status:     models.OrderPending,
		Notes:      stringPtr(c.FormValue("notes")),
	}

	// Parse delivery date if provided
	if deliveryDateStr := c.FormValue("delivery_date"); deliveryDateStr != "" {
		if deliveryDate, err := time.Parse("2006-01-02", deliveryDateStr); err == nil {
			order.DeliveryDate = &deliveryDate
		}
	}

	// Start transaction
	tx := database.DB.Begin()

	// Create the order
	if err := tx.Create(&order).Error; err != nil {
		tx.Rollback()
		return c.Status(500).JSON(fiber.Map{"error": "Failed to create purchase order"})
	}

	// Parse order details - handle form values
	productIDStr := c.FormValue("product_id[]")
	quantityStr := c.FormValue("quantity[]")
	unitPriceStr := c.FormValue("unit_price[]")

	// Validate that we have product data
	if productIDStr == "" || quantityStr == "" || unitPriceStr == "" {
		tx.Rollback()
		return c.Status(400).JSON(fiber.Map{"error": "Đơn hàng phải có ít nhất một sản phẩm"})
	}

	productID, err := strconv.ParseUint(productIDStr, 10, 32)
	if err != nil {
		tx.Rollback()
		return c.Status(400).JSON(fiber.Map{"error": "Invalid product ID"})
	}

	quantity, err := strconv.Atoi(quantityStr)
	if err != nil || quantity <= 0 {
		tx.Rollback()
		return c.Status(400).JSON(fiber.Map{"error": "Invalid quantity"})
	}

	unitPrice, err := strconv.ParseFloat(unitPriceStr, 64)
	if err != nil || unitPrice <= 0 {
		tx.Rollback()
		return c.Status(400).JSON(fiber.Map{"error": "Invalid unit price"})
	}

	subtotal := float64(quantity) * unitPrice
	totalAmount := subtotal

	detail := models.PurchaseOrderDetail{
		OrderID:   order.OrderID,
		ProductID: uint(productID),
		Quantity:  quantity,
		UnitPrice: unitPrice,
		Subtotal:  subtotal,
	}

	if err := tx.Create(&detail).Error; err != nil {
		tx.Rollback()
		return c.Status(500).JSON(fiber.Map{"error": "Failed to create order detail"})
	}

	details = append(details, detail)

	// Update total amount
	order.TotalAmount = totalAmount
	if err := tx.Save(&order).Error; err != nil {
		tx.Rollback()
		return c.Status(500).JSON(fiber.Map{"error": "Failed to update order total"})
	}

	tx.Commit()

	return c.Redirect(fmt.Sprintf("/purchase-orders/%d", order.OrderID))
}

// PurchaseOrderView displays a single purchase order
func PurchaseOrderView(c *fiber.Ctx) error {
	id, err := strconv.ParseUint(c.Params("id"), 10, 32)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid order ID"})
	}

	var order models.PurchaseOrder
	var details []models.PurchaseOrderDetail

	// Get order with related data
	if err := database.DB.Preload("Supplier").Preload("Employee").First(&order, id).Error; err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "Purchase order not found"})
	}

	// Get order details
	if err := database.DB.Preload("Product").Where("order_id = ?", order.OrderID).Find(&details).Error; err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to fetch order details"})
	}

	return c.Render("pages/purchase_orders/view", fiber.Map{
		"Title":           "Chi tiết đơn đặt hàng",
		"Active":          "purchase-orders",
		"Order":           order,
		"Details":         details,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// PurchaseOrderEdit displays the form to edit a purchase order
func PurchaseOrderEdit(c *fiber.Ctx) error {
	id, err := strconv.ParseUint(c.Params("id"), 10, 32)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid order ID"})
	}

	var order models.PurchaseOrder
	var suppliers []models.Supplier
	var employees []models.Employee
	var products []models.Product
	var details []models.PurchaseOrderDetail

	// Get order
	if err := database.DB.Preload("Supplier").Preload("Employee").First(&order, id).Error; err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "Purchase order not found"})
	}

	// Get related data
	if err := database.DB.Find(&suppliers).Error; err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to fetch suppliers"})
	}

	if err := database.DB.Find(&employees).Error; err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to fetch employees"})
	}

	if err := database.DB.Find(&products).Error; err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to fetch products"})
	}

	// Get order details
	if err := database.DB.Preload("Product").Where("order_id = ?", order.OrderID).Find(&details).Error; err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to fetch order details"})
	}

	return c.Render("pages/purchase_orders/edit", fiber.Map{
		"Title":           "Chỉnh sửa đơn đặt hàng",
		"Active":          "purchase-orders",
		"Order":           order,
		"Suppliers":       suppliers,
		"Employees":       employees,
		"Products":        products,
		"Details":         details,
		"SQLQueries":      c.Locals("SQLQueries"),
		"TotalSQLQueries": c.Locals("TotalSQLQueries"),
	}, "layouts/base")
}

// PurchaseOrderUpdate updates an existing purchase order
func PurchaseOrderUpdate(c *fiber.Ctx) error {
	id, err := strconv.ParseUint(c.Params("id"), 10, 32)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid order ID"})
	}

	var order models.PurchaseOrder
	if err := database.DB.First(&order, id).Error; err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "Purchase order not found"})
	}

	// Update order fields
	if supplierIDStr := c.FormValue("supplier_id"); supplierIDStr != "" {
		if supplierID, err := strconv.ParseUint(supplierIDStr, 10, 32); err == nil {
			order.SupplierID = uint(supplierID)
		}
	}

	if employeeIDStr := c.FormValue("employee_id"); employeeIDStr != "" {
		if employeeID, err := strconv.ParseUint(employeeIDStr, 10, 32); err == nil {
			order.EmployeeID = uint(employeeID)
		}
	}

	if status := c.FormValue("status"); status != "" {
		order.Status = models.OrderStatus(status)
	}

	if notes := c.FormValue("notes"); notes != "" {
		order.Notes = stringPtr(notes)
	}

	// Parse delivery date if provided
	if deliveryDateStr := c.FormValue("delivery_date"); deliveryDateStr != "" {
		if deliveryDate, err := time.Parse("2006-01-02", deliveryDateStr); err == nil {
			order.DeliveryDate = &deliveryDate
		}
	}

	// Start transaction
	tx := database.DB.Begin()

	// Update order
	if err := tx.Save(&order).Error; err != nil {
		tx.Rollback()
		return c.Status(500).JSON(fiber.Map{"error": "Failed to update purchase order"})
	}

	// Update order details if provided
	productIDStr := c.FormValue("product_id[]")
	quantityStr := c.FormValue("quantity[]")
	unitPriceStr := c.FormValue("unit_price[]")

	if productIDStr != "" && quantityStr != "" && unitPriceStr != "" {
		// Delete existing details
		if err := tx.Where("order_id = ?", order.OrderID).Delete(&models.PurchaseOrderDetail{}).Error; err != nil {
			tx.Rollback()
			return c.Status(500).JSON(fiber.Map{"error": "Failed to delete existing details"})
		}

		productID, err := strconv.ParseUint(productIDStr, 10, 32)
		if err != nil {
			tx.Rollback()
			return c.Status(400).JSON(fiber.Map{"error": "Invalid product ID"})
		}

		quantity, err := strconv.Atoi(quantityStr)
		if err != nil || quantity <= 0 {
			tx.Rollback()
			return c.Status(400).JSON(fiber.Map{"error": "Invalid quantity"})
		}

		unitPrice, err := strconv.ParseFloat(unitPriceStr, 64)
		if err != nil || unitPrice <= 0 {
			tx.Rollback()
			return c.Status(400).JSON(fiber.Map{"error": "Invalid unit price"})
		}

		subtotal := float64(quantity) * unitPrice
		totalAmount := subtotal

		detail := models.PurchaseOrderDetail{
			OrderID:   order.OrderID,
			ProductID: uint(productID),
			Quantity:  quantity,
			UnitPrice: unitPrice,
			Subtotal:  subtotal,
		}

		if err := tx.Create(&detail).Error; err != nil {
			tx.Rollback()
			return c.Status(500).JSON(fiber.Map{"error": "Failed to create order detail"})
		}

		// Update total amount
		order.TotalAmount = totalAmount
		if err := tx.Save(&order).Error; err != nil {
			tx.Rollback()
			return c.Status(500).JSON(fiber.Map{"error": "Failed to update order total"})
		}
	}

	tx.Commit()

	return c.Redirect(fmt.Sprintf("/purchase-orders/%d", order.OrderID))
}

// PurchaseOrderDelete deletes a purchase order
func PurchaseOrderDelete(c *fiber.Ctx) error {
	id, err := strconv.ParseUint(c.Params("id"), 10, 32)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid order ID"})
	}

	// Start transaction
	tx := database.DB.Begin()

	// Delete order details first
	if err := tx.Where("order_id = ?", id).Delete(&models.PurchaseOrderDetail{}).Error; err != nil {
		tx.Rollback()
		return c.Status(500).JSON(fiber.Map{"error": "Failed to delete order details"})
	}

	// Delete order
	if err := tx.Delete(&models.PurchaseOrder{}, id).Error; err != nil {
		tx.Rollback()
		return c.Status(500).JSON(fiber.Map{"error": "Failed to delete purchase order"})
	}

	tx.Commit()

	return c.Redirect("/purchase-orders")
}

// Helper function to create string pointer
func stringPtr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
