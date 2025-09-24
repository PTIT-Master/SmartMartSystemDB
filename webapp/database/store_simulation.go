package database

import (
	"fmt"
	"log"
	"math/rand"
	"time"

	"github.com/supermarket/models"
	"gorm.io/gorm"
)

// SimulationConfig holds simulation parameters
type SimulationConfig struct {
	StartDate         time.Time
	EndDate           time.Time
	DB                *gorm.DB
	MinShelfStock     int     // Minimum stock on shelf before restock
	MinWarehouseStock int     // Minimum warehouse stock before reorder
	AverageDailySales int     // Average number of sales per day
	RestockThreshold  float64 // Percentage threshold for restocking (e.g., 0.3 = 30%)
}

// StoreSimulation handles the store simulation
type StoreSimulation struct {
	config          SimulationConfig
	products        []models.Product
	customers       []models.Customer
	employees       []models.Employee
	suppliers       []models.Supplier
	warehouses      []models.Warehouse
	shelves         []models.DisplayShelf
	currentDate     time.Time
	orderCounter    int
	transferCounter int
	invoiceCounter  int
}

// NewStoreSimulation creates a new simulation instance
func NewStoreSimulation(config SimulationConfig) (*StoreSimulation, error) {
	sim := &StoreSimulation{
		config:      config,
		currentDate: config.StartDate,
	}

	// Load existing data
	if err := sim.loadExistingData(); err != nil {
		return nil, fmt.Errorf("failed to load existing data: %w", err)
	}

	// Get the last counters from database
	if err := sim.initializeCounters(); err != nil {
		return nil, fmt.Errorf("failed to initialize counters: %w", err)
	}

	return sim, nil
}

// loadExistingData loads all necessary data from database
func (s *StoreSimulation) loadExistingData() error {
	// Load products
	if err := s.config.DB.Find(&s.products).Error; err != nil {
		return fmt.Errorf("failed to load products: %w", err)
	}

	// Load customers
	if err := s.config.DB.Find(&s.customers).Error; err != nil {
		return fmt.Errorf("failed to load customers: %w", err)
	}

	// Load employees
	if err := s.config.DB.Find(&s.employees).Error; err != nil {
		return fmt.Errorf("failed to load employees: %w", err)
	}

	// Load suppliers
	if err := s.config.DB.Find(&s.suppliers).Error; err != nil {
		return fmt.Errorf("failed to load suppliers: %w", err)
	}

	// Load warehouses
	if err := s.config.DB.Find(&s.warehouses).Error; err != nil {
		return fmt.Errorf("failed to load warehouses: %w", err)
	}

	// Load display shelves
	if err := s.config.DB.Find(&s.shelves).Error; err != nil {
		return fmt.Errorf("failed to load shelves: %w", err)
	}

	log.Printf("Loaded: %d products, %d customers, %d employees, %d suppliers, %d warehouses, %d shelves",
		len(s.products), len(s.customers), len(s.employees), len(s.suppliers), len(s.warehouses), len(s.shelves))

	return nil
}

// initializeCounters gets the last used counters from database
func (s *StoreSimulation) initializeCounters() error {
	// Get last purchase order number
	var lastOrder models.PurchaseOrder
	if err := s.config.DB.Order("order_id desc").First(&lastOrder).Error; err != nil {
		if err != gorm.ErrRecordNotFound {
			return err
		}
		s.orderCounter = 0
	} else {
		// Extract number from OrderNo (e.g., "PO202509001" -> 1)
		fmt.Sscanf(lastOrder.OrderNo, "PO%*d%d", &s.orderCounter)
	}

	// Get last stock transfer number
	var lastTransfer models.StockTransfer
	if err := s.config.DB.Order("transfer_id desc").First(&lastTransfer).Error; err != nil {
		if err != gorm.ErrRecordNotFound {
			return err
		}
		s.transferCounter = 0
	} else {
		fmt.Sscanf(lastTransfer.TransferCode, "ST%*d%d", &s.transferCounter)
	}

	// Get last invoice number
	var lastInvoice models.SalesInvoice
	if err := s.config.DB.Order("invoice_id desc").First(&lastInvoice).Error; err != nil {
		if err != gorm.ErrRecordNotFound {
			return err
		}
		s.invoiceCounter = 0
	} else {
		fmt.Sscanf(lastInvoice.InvoiceNo, "INV%*d%d", &s.invoiceCounter)
	}

	return nil
}

// Run executes the simulation
func (s *StoreSimulation) Run() error {
	log.Printf("Starting simulation from %s to %s",
		s.config.StartDate.Format("2006-01-02"),
		s.config.EndDate.Format("2006-01-02"))

	for s.currentDate = s.config.StartDate; !s.currentDate.After(s.config.EndDate); s.currentDate = s.currentDate.AddDate(0, 0, 1) {
		log.Printf("\n=== Processing Date: %s ===", s.currentDate.Format("2006-01-02"))

		// Different activities based on date
		dayOfMonth := s.currentDate.Day()

		switch {
		case dayOfMonth == 1:
			// First day: Initial large purchase order
			if err := s.processInitialPurchaseOrders(); err != nil {
				return fmt.Errorf("failed to process initial purchase orders: %w", err)
			}

		case dayOfMonth == 2:
			// Second day: Initial stock transfer to shelves
			if err := s.processInitialStockTransfers(); err != nil {
				return fmt.Errorf("failed to process initial stock transfers: %w", err)
			}

		case dayOfMonth%7 == 1:
			// Weekly: Check and restock shelves from warehouse
			if err := s.processWeeklyRestock(); err != nil {
				return fmt.Errorf("failed to process weekly restock: %w", err)
			}
			// Also process daily sales
			if err := s.processDailySales(); err != nil {
				return fmt.Errorf("failed to process daily sales: %w", err)
			}

		case dayOfMonth%14 == 0:
			// Bi-weekly: Check warehouse and create purchase orders if needed
			if err := s.processBiWeeklyPurchaseOrders(); err != nil {
				return fmt.Errorf("failed to process bi-weekly purchase orders: %w", err)
			}
			// Also process daily sales
			if err := s.processDailySales(); err != nil {
				return fmt.Errorf("failed to process daily sales: %w", err)
			}

		default:
			// Regular days: Process daily sales
			if err := s.processDailySales(); err != nil {
				return fmt.Errorf("failed to process daily sales: %w", err)
			}
		}

		// Random events (10% chance each day)
		if rand.Float64() < 0.1 {
			if err := s.processRandomEvent(); err != nil {
				log.Printf("Warning: Random event failed: %v", err)
			}
		}
	}

	log.Println("\n✅ Simulation completed successfully!")
	s.printSimulationSummary()
	return nil
}

// processInitialPurchaseOrders creates initial purchase orders for stocking
func (s *StoreSimulation) processInitialPurchaseOrders() error {
	log.Println("📦 Creating initial purchase orders...")

	// Group products by supplier
	productsBySupplier := make(map[uint][]models.Product)
	for _, product := range s.products {
		productsBySupplier[product.SupplierID] = append(productsBySupplier[product.SupplierID], product)
	}

	// Create purchase order for each supplier
	for supplierID, products := range productsBySupplier {
		// Select random employee (preferably manager or supervisor)
		employee := s.getRandomEmployee("manager")

		// Generate order number
		s.orderCounter++
		orderNo := fmt.Sprintf("PO%s%03d", s.currentDate.Format("200601"), s.orderCounter)

		// Start transaction for this order
		tx := s.config.DB.Begin()

		// Create purchase order
		order := models.PurchaseOrder{
			OrderNo:    orderNo,
			SupplierID: supplierID,
			EmployeeID: employee.EmployeeID,
			OrderDate:  s.currentDate,
			Status:     models.OrderReceived,
		}

		deliveryDate := s.currentDate.AddDate(0, 0, 1)
		order.DeliveryDate = &deliveryDate

		if err := tx.Create(&order).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to create purchase order: %w", err)
		}

		// Create order details
		var totalAmount float64
		for _, product := range products {
			// Order quantity: 100-500 units for initial stock
			quantity := 100 + rand.Intn(400)
			unitPrice := product.ImportPrice
			subtotal := float64(quantity) * unitPrice

			detail := models.PurchaseOrderDetail{
				OrderID:   order.OrderID,
				ProductID: product.ProductID,
				Quantity:  quantity,
				UnitPrice: unitPrice,
				Subtotal:  subtotal,
			}

			if err := tx.Create(&detail).Error; err != nil {
				tx.Rollback()
				return fmt.Errorf("failed to create order detail: %w", err)
			}

			totalAmount += subtotal

			// Create warehouse inventory entry
			batchCode := fmt.Sprintf("BATCH%s%04d", s.currentDate.Format("20060102"), product.ProductID)
			expiryDate := s.currentDate.AddDate(0, 3, 0) // 3 months expiry for most products

			inventory := models.WarehouseInventory{
				WarehouseID: s.warehouses[0].WarehouseID, // Use first warehouse
				ProductID:   product.ProductID,
				BatchCode:   batchCode,
				Quantity:    quantity,
				ImportDate:  s.currentDate,
				ExpiryDate:  &expiryDate,
				ImportPrice: unitPrice,
			}

			if err := tx.Create(&inventory).Error; err != nil {
				tx.Rollback()
				return fmt.Errorf("failed to create warehouse inventory: %w", err)
			}
		}

		// Update order total amount
		order.TotalAmount = totalAmount
		if err := tx.Model(&order).Update("total_amount", totalAmount).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to update order total: %w", err)
		}

		// Commit transaction
		if err := tx.Commit().Error; err != nil {
			return fmt.Errorf("failed to commit purchase order transaction: %w", err)
		}

		log.Printf("  ✓ Created order %s for supplier %d with %d products (Total: %.2f)",
			orderNo, supplierID, len(products), totalAmount)
	}

	return nil
}

// processInitialStockTransfers transfers products from warehouse to shelves
func (s *StoreSimulation) processInitialStockTransfers() error {
	log.Println("📤 Transferring initial stock to shelves...")

	// First, create shelf layouts for all products
	if err := s.createShelfLayouts(); err != nil {
		return fmt.Errorf("failed to create shelf layouts: %w", err)
	}

	// Get all warehouse inventory
	var inventories []models.WarehouseInventory
	if err := s.config.DB.Where("quantity > 0").Find(&inventories).Error; err != nil {
		return fmt.Errorf("failed to get warehouse inventory: %w", err)
	}

	// Group by product for easier processing
	inventoryByProduct := make(map[uint][]models.WarehouseInventory)
	for _, inv := range inventories {
		inventoryByProduct[inv.ProductID] = append(inventoryByProduct[inv.ProductID], inv)
	}

	// Transfer products to appropriate shelves
	for productID, invList := range inventoryByProduct {
		// Find product details
		var product models.Product
		if err := s.config.DB.First(&product, productID).Error; err != nil {
			continue
		}

		// Get shelf layout for this product
		var shelfLayout models.ShelfLayout
		if err := s.config.DB.Where("product_id = ?", productID).First(&shelfLayout).Error; err != nil {
			log.Printf("Warning: No shelf layout found for product %d", productID)
			continue
		}

		// Get shelf details
		var shelf models.DisplayShelf
		if err := s.config.DB.First(&shelf, shelfLayout.ShelfID).Error; err != nil {
			continue
		}

		// Transfer 30-50% of inventory to shelf
		for _, inv := range invList {
			transferQuantity := int(float64(inv.Quantity) * (0.3 + rand.Float64()*0.2))
			if transferQuantity <= 0 {
				continue
			}

			// Create stock transfer
			if err := s.createStockTransfer(product, inv, shelf, transferQuantity); err != nil {
				log.Printf("Warning: Failed to transfer product %d: %v", productID, err)
				continue
			}
		}
	}

	return nil
}

// createShelfLayouts creates shelf layout configurations for all products
func (s *StoreSimulation) createShelfLayouts() error {
	log.Println("🗂️ Creating shelf layouts...")

	// Clear existing layouts to avoid conflicts
	if err := s.config.DB.Exec("TRUNCATE TABLE shelf_layout RESTART IDENTITY").Error; err != nil {
		log.Printf("Warning: Could not clear shelf layouts: %v", err)
	}

	// Create layouts for each product based on category
	for _, product := range s.products {
		// Find appropriate shelf for this product category
		var shelf models.DisplayShelf
		if err := s.config.DB.Where("category_id = ?", product.CategoryID).First(&shelf).Error; err != nil {
			// Skip products without matching shelf
			continue
		}

		// Create shelf layout
		layout := models.ShelfLayout{
			ShelfID:      shelf.ShelfID,
			ProductID:    product.ProductID,
			MaxQuantity:  200,
			PositionCode: fmt.Sprintf("POS-%d-%d", shelf.ShelfID, product.ProductID),
		}

		if err := s.config.DB.Create(&layout).Error; err != nil {
			log.Printf("Warning: Failed to create layout for product %d: %v", product.ProductID, err)
		}
	}

	// Count created layouts
	var count int64
	s.config.DB.Model(&models.ShelfLayout{}).Count(&count)
	log.Printf("  ✓ Created %d shelf layouts", count)

	return nil
}

// createStockTransfer creates a stock transfer record and updates inventories
func (s *StoreSimulation) createStockTransfer(product models.Product, warehouseInv models.WarehouseInventory, shelf models.DisplayShelf, quantity int) error {
	s.transferCounter++
	transferCode := fmt.Sprintf("ST%s%04d", s.currentDate.Format("200601"), s.transferCounter)

	// Select random warehouse employee
	employee := s.getRandomEmployee("warehouse")

	// Start transaction
	tx := s.config.DB.Begin()

	// Create transfer record
	transfer := models.StockTransfer{
		TransferCode:    transferCode,
		ProductID:       product.ProductID,
		FromWarehouseID: warehouseInv.WarehouseID,
		ToShelfID:       shelf.ShelfID,
		Quantity:        quantity,
		TransferDate:    s.currentDate,
		EmployeeID:      employee.EmployeeID,
		BatchCode:       warehouseInv.BatchCode,
		ExpiryDate:      warehouseInv.ExpiryDate,
		ImportPrice:     warehouseInv.ImportPrice,
		SellingPrice:    product.SellingPrice,
	}

	if err := tx.Create(&transfer).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to create transfer: %w", err)
	}

	// Update warehouse inventory (decrease)
	if err := tx.Model(&warehouseInv).Update("quantity", gorm.Expr("quantity - ?", quantity)).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to update warehouse inventory: %w", err)
	}

	// Create or update shelf batch inventory
	var shelfBatch models.ShelfBatchInventory
	err := tx.Where("shelf_id = ? AND product_id = ? AND batch_code = ?",
		shelf.ShelfID, product.ProductID, warehouseInv.BatchCode).First(&shelfBatch).Error

	if err == gorm.ErrRecordNotFound {
		// Create new shelf batch
		shelfBatch = models.ShelfBatchInventory{
			ShelfID:      shelf.ShelfID,
			ProductID:    product.ProductID,
			BatchCode:    warehouseInv.BatchCode,
			Quantity:     quantity,
			ExpiryDate:   warehouseInv.ExpiryDate,
			StockedDate:  s.currentDate,
			ImportPrice:  warehouseInv.ImportPrice,
			CurrentPrice: product.SellingPrice,
		}
		if err := tx.Create(&shelfBatch).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to create shelf batch: %w", err)
		}
	} else if err == nil {
		// Update existing batch
		if err := tx.Model(&shelfBatch).Update("quantity", gorm.Expr("quantity + ?", quantity)).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to update shelf batch: %w", err)
		}
	} else {
		tx.Rollback()
		return fmt.Errorf("failed to check shelf batch: %w", err)
	}

	// Commit transaction
	if err := tx.Commit().Error; err != nil {
		return fmt.Errorf("failed to commit transfer: %w", err)
	}

	log.Printf("  ✓ Transferred %d units of %s (Batch: %s) to shelf %d",
		quantity, product.ProductName, warehouseInv.BatchCode, shelf.ShelfID)

	return nil
}

// processDailySales generates daily sales transactions
func (s *StoreSimulation) processDailySales() error {
	// Skip Sundays
	if s.currentDate.Weekday() == time.Sunday {
		log.Println("🚫 Store closed on Sunday")
		return nil
	}

	log.Println("💰 Processing daily sales...")

	// Number of sales for the day (varies by day of week)
	numSales := s.calculateDailySalesCount()

	for i := 0; i < numSales; i++ {
		if err := s.createSalesInvoice(); err != nil {
			log.Printf("Warning: Failed to create sale %d: %v", i+1, err)
			continue
		}
	}

	log.Printf("  ✓ Processed %d sales transactions", numSales)
	return nil
}

// calculateDailySalesCount determines number of sales based on day of week
func (s *StoreSimulation) calculateDailySalesCount() int {
	base := s.config.AverageDailySales
	if base == 0 {
		base = 50 // Default
	}

	// Vary by day of week
	switch s.currentDate.Weekday() {
	case time.Saturday:
		return base + rand.Intn(30) // Weekend: more sales
	case time.Friday:
		return base + rand.Intn(20) // Friday: busy
	case time.Monday:
		return base - rand.Intn(10) // Monday: slower
	default:
		return base - 10 + rand.Intn(20) // Normal variation
	}
}

// createSalesInvoice creates a single sales transaction
func (s *StoreSimulation) createSalesInvoice() error {
	// Select random customer (70% chance of registered customer)
	var customer *models.Customer
	if rand.Float64() < 0.7 && len(s.customers) > 0 {
		customer = &s.customers[rand.Intn(len(s.customers))]
	}

	// Select random cashier
	cashier := s.getRandomEmployee("cashier")

	// Generate invoice number
	s.invoiceCounter++
	invoiceNo := fmt.Sprintf("INV%s%05d", s.currentDate.Format("200601"), s.invoiceCounter)

	// Start transaction
	tx := s.config.DB.Begin()

	// Create invoice
	invoice := models.SalesInvoice{
		InvoiceNo:   invoiceNo,
		EmployeeID:  cashier.EmployeeID,
		InvoiceDate: s.currentDate.Add(time.Hour * time.Duration(8+rand.Intn(12))), // Random time 8AM-8PM
	}

	if customer != nil {
		invoice.CustomerID = &customer.CustomerID
	}

	// Random payment method
	paymentMethods := []models.PaymentMethod{
		models.PaymentCash, models.PaymentCash, models.PaymentCash, // 60% cash
		models.PaymentCard, models.PaymentCard, // 40% card
	}
	method := paymentMethods[rand.Intn(len(paymentMethods))]
	invoice.PaymentMethod = &method

	if err := tx.Create(&invoice).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to create invoice: %w", err)
	}

	// Add 1-10 random products
	numProducts := 1 + rand.Intn(10)
	var subtotal, discountTotal float64
	successfulProducts := 0

	for i := 0; i < numProducts; i++ {
		// Get random product with available stock
		product, shelfBatch, err := s.getRandomAvailableProduct(tx)
		if err != nil {
			continue
		}

		// Quantity: 1-5 units typically
		quantity := 1 + rand.Intn(5)
		if quantity > shelfBatch.Quantity {
			quantity = shelfBatch.Quantity
		}
		if quantity <= 0 {
			continue
		}

		// Calculate prices
		unitPrice := shelfBatch.CurrentPrice
		discountPct := shelfBatch.DiscountPercent
		discountAmt := unitPrice * float64(quantity) * discountPct / 100
		itemSubtotal := (unitPrice * float64(quantity)) - discountAmt

		// Create invoice detail
		detail := models.SalesInvoiceDetail{
			InvoiceID:          invoice.InvoiceID,
			ProductID:          product.ProductID,
			Quantity:           quantity,
			UnitPrice:          unitPrice,
			DiscountPercentage: discountPct,
			DiscountAmount:     discountAmt,
			Subtotal:           itemSubtotal,
		}

		if err := tx.Create(&detail).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to create invoice detail: %w", err)
		}

		// Update shelf batch inventory
		if err := tx.Model(&shelfBatch).Update("quantity", gorm.Expr("quantity - ?", quantity)).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to update shelf inventory: %w", err)
		}

		subtotal += itemSubtotal
		discountTotal += discountAmt
		successfulProducts++
	}

	// If no products were added, rollback the transaction
	if successfulProducts == 0 {
		tx.Rollback()
		return fmt.Errorf("no products could be added to invoice")
	}

	// Calculate tax (8% VAT)
	taxAmount := subtotal * 0.08
	totalAmount := subtotal + taxAmount

	// Update invoice totals
	updates := map[string]interface{}{
		"subtotal":        subtotal,
		"discount_amount": discountTotal,
		"tax_amount":      taxAmount,
		"total_amount":    totalAmount,
	}

	// Calculate loyalty points if customer exists
	if customer != nil {
		pointsEarned := int(totalAmount / 10000) // 1 point per 10,000 VND
		updates["points_earned"] = pointsEarned

		// Update customer spending and points
		if err := tx.Model(customer).Updates(map[string]interface{}{
			"total_spending": gorm.Expr("total_spending + ?", totalAmount),
			"loyalty_points": gorm.Expr("loyalty_points + ?", pointsEarned),
		}).Error; err != nil {
			log.Printf("Warning: Failed to update customer points: %v", err)
		}
	}

	if err := tx.Model(&invoice).Updates(updates).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to update invoice totals: %w", err)
	}

	// Commit transaction
	if err := tx.Commit().Error; err != nil {
		return fmt.Errorf("failed to commit invoice: %w", err)
	}

	return nil
}

// getRandomAvailableProduct gets a random product with available stock on shelf
func (s *StoreSimulation) getRandomAvailableProduct(tx *gorm.DB) (*models.Product, *models.ShelfBatchInventory, error) {
	var batches []models.ShelfBatchInventory
	if err := tx.Where("quantity > 0").Order("RANDOM()").Limit(10).Find(&batches).Error; err != nil {
		return nil, nil, err
	}

	if len(batches) == 0 {
		return nil, nil, fmt.Errorf("no products available on shelves")
	}

	// Select random batch
	batch := &batches[rand.Intn(len(batches))]

	// Get product details
	var product models.Product
	if err := tx.First(&product, batch.ProductID).Error; err != nil {
		return nil, nil, err
	}

	return &product, batch, nil
}

// processWeeklyRestock checks and restocks shelves from warehouse
func (s *StoreSimulation) processWeeklyRestock() error {
	log.Println("📦 Weekly restock check...")

	// Check shelf inventory levels
	var lowStockItems []struct {
		ProductID uint
		ShelfID   uint
		Quantity  int
	}

	query := `
		SELECT product_id, shelf_id, SUM(quantity) as quantity
		FROM shelf_batch_inventory
		GROUP BY product_id, shelf_id
		HAVING SUM(quantity) < ?
	`

	if err := s.config.DB.Raw(query, s.config.MinShelfStock).Scan(&lowStockItems).Error; err != nil {
		return fmt.Errorf("failed to check low stock: %w", err)
	}

	log.Printf("  Found %d low stock items", len(lowStockItems))

	// Restock each low stock item
	for _, item := range lowStockItems {
		// Find available stock in warehouse
		var warehouseInv models.WarehouseInventory
		err := s.config.DB.Where("product_id = ? AND quantity > 0", item.ProductID).
			Order("import_date ASC"). // FIFO
			First(&warehouseInv).Error

		if err != nil {
			log.Printf("  ⚠ No warehouse stock for product %d", item.ProductID)
			continue
		}

		// Get product and shelf details
		var product models.Product
		var shelf models.DisplayShelf
		s.config.DB.First(&product, item.ProductID)
		s.config.DB.First(&shelf, item.ShelfID)

		// Transfer quantity (up to 50 units or available amount)
		transferQty := 50
		if warehouseInv.Quantity < transferQty {
			transferQty = warehouseInv.Quantity
		}

		if err := s.createStockTransfer(product, warehouseInv, shelf, transferQty); err != nil {
			log.Printf("  Warning: Failed to restock product %d: %v", item.ProductID, err)
		}
	}

	return nil
}

// processBiWeeklyPurchaseOrders checks warehouse stock and creates purchase orders
func (s *StoreSimulation) processBiWeeklyPurchaseOrders() error {
	log.Println("📋 Bi-weekly purchase order check...")

	// Check warehouse inventory levels
	var lowStockProducts []struct {
		ProductID  uint
		SupplierID uint
		TotalQty   int
	}

	query := `
		SELECT p.product_id, p.supplier_id, COALESCE(SUM(wi.quantity), 0) as total_qty
		FROM products p
		LEFT JOIN warehouse_inventory wi ON p.product_id = wi.product_id
		GROUP BY p.product_id, p.supplier_id
		HAVING COALESCE(SUM(wi.quantity), 0) < ?
	`

	if err := s.config.DB.Raw(query, s.config.MinWarehouseStock).Scan(&lowStockProducts).Error; err != nil {
		return fmt.Errorf("failed to check warehouse stock: %w", err)
	}

	if len(lowStockProducts) == 0 {
		log.Println("  ✓ Warehouse stock levels adequate")
		return nil
	}

	// Group by supplier
	ordersBySupplier := make(map[uint][]struct {
		ProductID uint
		Quantity  int
	})

	for _, item := range lowStockProducts {
		// Order quantity: enough to reach 200 units
		orderQty := 200 - item.TotalQty
		if orderQty < 50 {
			orderQty = 50 // Minimum order
		}

		ordersBySupplier[item.SupplierID] = append(ordersBySupplier[item.SupplierID], struct {
			ProductID uint
			Quantity  int
		}{
			ProductID: item.ProductID,
			Quantity:  orderQty,
		})
	}

	// Create purchase orders
	for supplierID, items := range ordersBySupplier {
		if err := s.createPurchaseOrder(supplierID, items); err != nil {
			log.Printf("Warning: Failed to create order for supplier %d: %v", supplierID, err)
		}
	}

	return nil
}

// createPurchaseOrder creates a purchase order and updates warehouse on delivery
func (s *StoreSimulation) createPurchaseOrder(supplierID uint, items []struct {
	ProductID uint
	Quantity  int
}) error {
	// Generate order number
	s.orderCounter++
	orderNo := fmt.Sprintf("PO%s%03d", s.currentDate.Format("200601"), s.orderCounter)

	// Select employee
	employee := s.getRandomEmployee("manager")

	// Start transaction
	tx := s.config.DB.Begin()

	// Create order
	deliveryDate := s.currentDate.AddDate(0, 0, 2) // 2 days delivery
	order := models.PurchaseOrder{
		OrderNo:      orderNo,
		SupplierID:   supplierID,
		EmployeeID:   employee.EmployeeID,
		OrderDate:    s.currentDate,
		DeliveryDate: &deliveryDate,
		Status:       models.OrderReceived,
	}

	if err := tx.Create(&order).Error; err != nil {
		tx.Rollback()
		return err
	}

	var totalAmount float64

	// Create order details and warehouse inventory
	for _, item := range items {
		// Get product details
		var product models.Product
		if err := tx.First(&product, item.ProductID).Error; err != nil {
			continue
		}

		// Create order detail
		unitPrice := product.ImportPrice
		subtotal := float64(item.Quantity) * unitPrice

		detail := models.PurchaseOrderDetail{
			OrderID:   order.OrderID,
			ProductID: item.ProductID,
			Quantity:  item.Quantity,
			UnitPrice: unitPrice,
			Subtotal:  subtotal,
		}

		if err := tx.Create(&detail).Error; err != nil {
			tx.Rollback()
			return err
		}

		// Create warehouse inventory
		batchCode := fmt.Sprintf("BATCH%s%04d", s.currentDate.Format("20060102"), item.ProductID)
		expiryDate := s.currentDate.AddDate(0, 3, 0) // 3 months expiry

		inventory := models.WarehouseInventory{
			WarehouseID: s.warehouses[0].WarehouseID,
			ProductID:   item.ProductID,
			BatchCode:   batchCode,
			Quantity:    item.Quantity,
			ImportDate:  deliveryDate,
			ExpiryDate:  &expiryDate,
			ImportPrice: unitPrice,
		}

		if err := tx.Create(&inventory).Error; err != nil {
			tx.Rollback()
			return err
		}

		totalAmount += subtotal
	}

	// Update order total
	if err := tx.Model(&order).Update("total_amount", totalAmount).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Commit
	if err := tx.Commit().Error; err != nil {
		return err
	}

	log.Printf("  ✓ Created order %s for supplier %d (%d items, Total: %.2f)",
		orderNo, supplierID, len(items), totalAmount)

	return nil
}

// processRandomEvent creates random events like promotions, returns, etc.
func (s *StoreSimulation) processRandomEvent() error {
	events := []string{"promotion", "bulk_sale", "near_expiry_discount"}
	event := events[rand.Intn(len(events))]

	switch event {
	case "promotion":
		log.Println("🎉 Special promotion day - 10% off selected items")
		// Could implement promotion logic here

	case "bulk_sale":
		log.Println("📦 Bulk sale to business customer")
		// Create a large invoice

	case "near_expiry_discount":
		log.Println("⏰ Applying discounts to near-expiry products")
		// Update near-expiry product prices
		s.applyNearExpiryDiscounts()
	}

	return nil
}

// applyNearExpiryDiscounts applies discounts to products nearing expiry
func (s *StoreSimulation) applyNearExpiryDiscounts() error {
	// Find products expiring within 7 days
	expiryThreshold := s.currentDate.AddDate(0, 0, 7)

	return s.config.DB.Model(&models.ShelfBatchInventory{}).
		Where("expiry_date <= ? AND expiry_date > ? AND quantity > 0", expiryThreshold, s.currentDate).
		Updates(map[string]interface{}{
			"discount_percent": 30,
			"is_near_expiry":   true,
		}).Error
}

// Helper functions

// getRandomEmployee returns a random employee of specified type
func (s *StoreSimulation) getRandomEmployee(role string) *models.Employee {
	var candidates []models.Employee

	for _, emp := range s.employees {
		switch role {
		case "manager":
			if emp.EmployeeCode == "EMP001" {
				candidates = append(candidates, emp)
			}
		case "cashier":
			if emp.EmployeeCode == "EMP003" || emp.EmployeeCode == "EMP006" {
				candidates = append(candidates, emp)
			}
		case "warehouse":
			if emp.EmployeeCode == "EMP005" {
				candidates = append(candidates, emp)
			}
		default:
			candidates = s.employees
		}
	}

	if len(candidates) == 0 {
		return &s.employees[rand.Intn(len(s.employees))]
	}

	return &candidates[rand.Intn(len(candidates))]
}

// printSimulationSummary prints summary statistics
func (s *StoreSimulation) printSimulationSummary() {
	log.Println("\n=== Simulation Summary ===")

	// Count totals
	var orderCount, invoiceCount, transferCount int64
	s.config.DB.Model(&models.PurchaseOrder{}).Count(&orderCount)
	s.config.DB.Model(&models.SalesInvoice{}).Count(&invoiceCount)
	s.config.DB.Model(&models.StockTransfer{}).Count(&transferCount)

	// Calculate revenue
	var totalRevenue struct {
		Total float64
	}
	s.config.DB.Model(&models.SalesInvoice{}).
		Select("SUM(total_amount) as total").
		Where("invoice_date >= ? AND invoice_date <= ?", s.config.StartDate, s.config.EndDate).
		Scan(&totalRevenue)

	log.Printf("📊 Purchase Orders: %d", orderCount)
	log.Printf("💰 Sales Invoices: %d", invoiceCount)
	log.Printf("📦 Stock Transfers: %d", transferCount)
	log.Printf("💵 Total Revenue: %.2f VND", totalRevenue.Total)
}

// RunSimulation is the main entry point for the simulation
func RunSimulation(db *gorm.DB, startDate, endDate time.Time) error {
	config := SimulationConfig{
		StartDate:         startDate,
		EndDate:           endDate,
		DB:                db,
		MinShelfStock:     20,
		MinWarehouseStock: 50,
		AverageDailySales: 8, // Increase daily sales to ensure 100+ invoices (8*20 days = 160+ invoices)
		RestockThreshold:  0.3,
	}

	sim, err := NewStoreSimulation(config)
	if err != nil {
		return fmt.Errorf("failed to create simulation: %w", err)
	}

	return sim.Run()
}
