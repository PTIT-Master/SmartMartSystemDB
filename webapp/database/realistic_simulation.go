package database

import (
	"fmt"
	"log"
	"math/rand"
	"strings"
	"time"

	"github.com/supermarket/models"
	"gorm.io/gorm"
)

// RealisticSimulation handles a more realistic store simulation
type RealisticSimulation struct {
	db                 *gorm.DB
	startDate          time.Time
	endDate            time.Time
	currentDate        time.Time
	products           []models.Product
	customers          []models.Customer
	employees          []models.Employee
	suppliers          []models.Supplier
	warehouses         []models.Warehouse
	shelves            []models.DisplayShelf
	orderCounter       int
	transferCounter    int
	invoiceCounter     int
	dailySalesTarget   map[uint]int // Target daily sales per product
	productRestockDays map[uint]int // Last restock day for each product
}

// RunRealisticSimulation executes a realistic 30-day simulation
func RunRealisticSimulation(db *gorm.DB, startDate, endDate time.Time) error {
	sim := &RealisticSimulation{
		db:                 db,
		startDate:          startDate,
		endDate:            endDate,
		currentDate:        startDate,
		dailySalesTarget:   make(map[uint]int),
		productRestockDays: make(map[uint]int),
	}

	// Initialize simulation
	if err := sim.initialize(); err != nil {
		return fmt.Errorf("failed to initialize: %w", err)
	}

	// Run daily operations
	return sim.runDailyOperations()
}

func (s *RealisticSimulation) initialize() error {
	log.Println("🚀 Initializing realistic simulation...")

	// Load master data
	if err := s.db.Find(&s.products).Error; err != nil {
		return fmt.Errorf("failed to load products: %w", err)
	}
	if err := s.db.Find(&s.customers).Error; err != nil {
		return fmt.Errorf("failed to load customers: %w", err)
	}
	if err := s.db.Find(&s.employees).Error; err != nil {
		return fmt.Errorf("failed to load employees: %w", err)
	}
	if err := s.db.Find(&s.suppliers).Error; err != nil {
		return fmt.Errorf("failed to load suppliers: %w", err)
	}
	if err := s.db.Find(&s.warehouses).Error; err != nil {
		return fmt.Errorf("failed to load warehouses: %w", err)
	}
	if err := s.db.Find(&s.shelves).Error; err != nil {
		return fmt.Errorf("failed to load shelves: %w", err)
	}

	// Initialize counters
	var lastOrder models.PurchaseOrder
	if err := s.db.Order("order_id desc").First(&lastOrder).Error; err == nil {
		fmt.Sscanf(lastOrder.OrderNo, "PO%*d%d", &s.orderCounter)
	}

	var lastTransfer models.StockTransfer
	if err := s.db.Order("transfer_id desc").First(&lastTransfer).Error; err == nil {
		fmt.Sscanf(lastTransfer.TransferCode, "ST%*d%d", &s.transferCounter)
	}

	var lastInvoice models.SalesInvoice
	if err := s.db.Order("invoice_id desc").First(&lastInvoice).Error; err == nil {
		fmt.Sscanf(lastInvoice.InvoiceNo, "INV%*d%d", &s.invoiceCounter)
	}

	// Calculate daily sales targets (to sell warehouse stock in ~3 days)
	for _, product := range s.products {
		// Base on category: Food/Beverages = high volume, Electronics = low volume
		switch product.CategoryID {
		case 1, 2: // Food, Beverages
			s.dailySalesTarget[product.ProductID] = 15 + rand.Intn(20) // 15-35 units/day
		case 3: // Electronics
			s.dailySalesTarget[product.ProductID] = 2 + rand.Intn(3) // 2-5 units/day
		default:
			s.dailySalesTarget[product.ProductID] = 8 + rand.Intn(12) // 8-20 units/day
		}
	}

	// Create shelf layouts
	return s.createShelfLayouts()
}

func (s *RealisticSimulation) runDailyOperations() error {
	totalDays := int(s.endDate.Sub(s.startDate).Hours()/24) + 1

	for day := 0; day < totalDays; day++ {
		s.currentDate = s.startDate.AddDate(0, 0, day)
		log.Printf("\n=== Day %d: %s ===", day+1, s.currentDate.Format("2006-01-02"))

		if day == 0 {
			// Day 1: Initial modest stocking
			if err := s.initialStocking(); err != nil {
				return fmt.Errorf("day 1 initial stocking failed: %w", err)
			}
		} else {
			// Daily operations
			log.Println("  📊 Checking warehouse stock levels...")
			// 1. Check and order from suppliers if warehouse is low
			if err := s.checkAndOrderFromSuppliers(); err != nil {
				log.Printf("Warning: supplier ordering failed: %v", err)
			}

			log.Println("  🚛 Restocking shelves from warehouse...")
			// 2. Transfer stock from warehouse to shelves as needed
			if err := s.restockShelves(); err != nil {
				log.Printf("Warning: shelf restocking failed: %v", err)
			}

			log.Println("  💰 Processing daily sales...")
			// 3. Process daily sales
			if err := s.processDailySales(); err != nil {
				log.Printf("Warning: daily sales failed: %v", err)
			}

			// 4. Create special scenarios for last days
			if day >= totalDays-3 {
				s.createEndScenarios()
			}
		}
	}

	s.printSummary()
	return nil
}

func (s *RealisticSimulation) initialStocking() error {
	log.Println("  📦 Initial stocking (0.3-day supply - very small to trigger frequent reorders)...")

	// Group products by supplier
	productsBySupplier := make(map[uint][]models.Product)
	for _, p := range s.products {
		productsBySupplier[p.SupplierID] = append(productsBySupplier[p.SupplierID], p)
	}

	for supplierID, products := range productsBySupplier {
		// Create purchase order
		order, err := s.createPurchaseOrder(supplierID)
		if err != nil {
			return err
		}

		tx := s.db.Begin()
		var totalAmount float64

		for _, product := range products {
			// Order 1-day supply initially
			dailyTarget := s.dailySalesTarget[product.ProductID]
			quantity := max(1, dailyTarget) // 1 day supply, minimum 1 unit
			subtotal := float64(quantity) * product.ImportPrice

			// Create order detail
			detail := models.PurchaseOrderDetail{
				OrderID:   order.OrderID,
				ProductID: product.ProductID,
				Quantity:  quantity,
				UnitPrice: product.ImportPrice,
				Subtotal:  subtotal,
			}
			if err := tx.Create(&detail).Error; err != nil {
				tx.Rollback()
				return err
			}

			// Add to warehouse
			if err := s.addToWarehouse(tx, product, quantity); err != nil {
				tx.Rollback()
				return err
			}

			// Transfer most to shelf initially (keep some in warehouse)
			shelfQty := max(1, quantity*8/10) // Transfer 80% to shelf
			if shelfQty > 0 {
				if err := s.transferToShelfWithTx(tx, product, shelfQty); err != nil {
					log.Printf("    Warning: Failed initial shelf transfer for %s: %v", product.ProductName, err)
				}
			}

			totalAmount += subtotal
		}

		// Update order total
		if err := tx.Model(&order).Update("total_amount", totalAmount).Error; err != nil {
			tx.Rollback()
			return err
		}

		if err := tx.Commit().Error; err != nil {
			return err
		}

		log.Printf("    ✓ Supplier %d: %d products, %.0f VND", supplierID, len(products), totalAmount)
	}

	return nil
}

func (s *RealisticSimulation) checkAndOrderFromSuppliers() error {
	for _, product := range s.products {
		// Check warehouse stock
		var warehouseQty int
		s.db.Model(&models.WarehouseInventory{}).
			Where("product_id = ? AND quantity > 0", product.ProductID).
			Select("COALESCE(SUM(quantity), 0)").
			Scan(&warehouseQty)

		dailyTarget := s.dailySalesTarget[product.ProductID]
		// Reorder when less than 1 day supply (very aggressive reordering)
		reorderThreshold := max(1, dailyTarget) // 1 day supply

		if warehouseQty < reorderThreshold {
			// Check if we already ordered recently (avoid duplicate orders)
			lastRestock, exists := s.productRestockDays[product.ProductID]
			currentDay := int(s.currentDate.Sub(s.startDate).Hours() / 24)

			if !exists || currentDay-lastRestock >= 1 { // Allow reorder every day
				// Order 2-day supply (ensure enough stock)
				orderQty := max(1, dailyTarget*2) // 2 day supply, minimum 1
				// DEBUG: Log calculation details
				if orderQty <= 0 {
					log.Printf("    WARN: Calculated non-positive orderQty %d for %s (dailyTarget: %d)", orderQty, product.ProductName, dailyTarget)
					continue
				}
				if err := s.orderProduct(product, orderQty); err != nil {
					log.Printf("    Failed to order %s: %v", product.ProductName, err)
				} else {
					s.productRestockDays[product.ProductID] = currentDay
					log.Printf("    🛒 REORDER: %d units of %s (warehouse: %d, threshold: %d)", orderQty, product.ProductName, warehouseQty, reorderThreshold)
				}
			} else {
				log.Printf("    ⏳ %s needs reorder (warehouse: %d) but ordered recently (day %d)", product.ProductName, warehouseQty, lastRestock)
			}
		}
	}
	return nil
}

func (s *RealisticSimulation) restockShelves() error {
	for _, product := range s.products {
		// Check shelf stock
		var shelfQty int
		s.db.Model(&models.ShelfInventory{}).
			Where("product_id = ?", product.ProductID).
			Select("COALESCE(SUM(current_quantity), 0)").
			Scan(&shelfQty)

		dailyTarget := s.dailySalesTarget[product.ProductID]

		// Restock if below 0.3 daily target (restock very aggressively)
		restock_threshold := max(1, dailyTarget*3/10) // 0.3 daily target
		if shelfQty < restock_threshold {
			needed := dailyTarget - shelfQty // Try to have 1 day on shelf

			// Ensure needed is positive
			if needed <= 0 {
				continue
			}

			// Get warehouse stock (FIFO)
			var warehouseInv models.WarehouseInventory
			if err := s.db.Where("product_id = ? AND quantity > 0", product.ProductID).
				Order("expiry_date ASC, batch_code ASC").
				First(&warehouseInv).Error; err == nil {

				transferQty := needed
				if warehouseInv.Quantity < needed {
					transferQty = warehouseInv.Quantity
				}

				// Ensure transferQty is positive before transfer
				if transferQty > 0 {
					if err := s.createStockTransfer(product, warehouseInv, transferQty); err != nil {
						log.Printf("    Failed transfer %s: %v", product.ProductName, err)
					} else {
						log.Printf("    📦→🏬 RESTOCK: %d units of %s to shelf (shelf: %d→%d)",
							transferQty, product.ProductName, shelfQty, shelfQty+transferQty)
					}
				}
			} else {
				log.Printf("    ⚠️ %s shelf low (%d/%d) but no warehouse stock available", product.ProductName, shelfQty, dailyTarget)
			}
		}
	}
	return nil
}

func (s *RealisticSimulation) processDailySales() error {
	numCustomers := 20 + rand.Intn(30) // 20-50 customers/day
	log.Printf("  💰 Processing %d customers...", numCustomers)

	successfulSales := 0
	for i := 0; i < numCustomers; i++ {
		if err := s.createSale(); err == nil {
			successfulSales++
		}
	}

	if successfulSales > 0 {
		log.Printf("    ✓ Completed %d sales", successfulSales)
	}
	return nil
}

func (s *RealisticSimulation) createSale() error {
	// First check if there are any products available on shelf
	var availableCount int64
	s.db.Raw(`
		SELECT COUNT(*) 
		FROM shelf_batch_inventory 
		WHERE quantity > 0
	`).Scan(&availableCount)

	if availableCount == 0 {
		// No products available, skip this sale
		return fmt.Errorf("no products available on shelf")
	}

	// Select customer (70% members)
	var customerID *uint
	if rand.Float64() < 0.7 && len(s.customers) > 0 {
		customer := s.customers[rand.Intn(len(s.customers))]
		customerID = &customer.CustomerID
	}

	employee := s.getRandomEmployee("cashier")
	s.invoiceCounter++
	invoiceNo := fmt.Sprintf("INV%s%04d", s.currentDate.Format("200601"), s.invoiceCounter)

	tx := s.db.Begin()

	paymentMethod := s.getPaymentMethod()
	invoice := models.SalesInvoice{
		InvoiceNo:     invoiceNo,
		CustomerID:    customerID,
		EmployeeID:    employee.EmployeeID,
		InvoiceDate:   s.currentDate.Add(time.Hour * time.Duration(8+rand.Intn(12))),
		PaymentMethod: &paymentMethod,
	}

	if err := tx.Create(&invoice).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Buy 1-8 random items
	numItems := 1 + rand.Intn(8)
	var subtotal float64
	var itemsAdded int

	for j := 0; j < numItems; j++ {
		// Get random available product from shelf
		var availableProduct struct {
			ShelfBatchID uint
			ProductID    uint
			Quantity     int
			CurrentPrice float64
		}

		if err := tx.Raw(`
			SELECT shelf_batch_id, product_id, quantity, current_price
			FROM shelf_batch_inventory
			WHERE quantity > 0
			ORDER BY RANDOM()
			LIMIT 1
		`).Scan(&availableProduct).Error; err != nil || availableProduct.ProductID == 0 {
			continue
		}

		// Purchase 1-3 units
		purchaseQty := 1 + rand.Intn(3)
		if purchaseQty > availableProduct.Quantity {
			purchaseQty = availableProduct.Quantity
		}

		itemSubtotal := float64(purchaseQty) * availableProduct.CurrentPrice

		detail := models.SalesInvoiceDetail{
			InvoiceID: invoice.InvoiceID,
			ProductID: availableProduct.ProductID,
			Quantity:  purchaseQty,
			UnitPrice: availableProduct.CurrentPrice,
			Subtotal:  itemSubtotal,
		}

		if err := tx.Create(&detail).Error; err != nil {
			tx.Rollback()
			return err
		}

		// Deduct from shelf batch - ensure no negative quantities
		if err := tx.Model(&models.ShelfBatchInventory{}).
			Where("shelf_batch_id = ? AND quantity >= ?", availableProduct.ShelfBatchID, purchaseQty).
			Update("quantity", gorm.Expr("quantity - ?", purchaseQty)).Error; err != nil {
			tx.Rollback()
			return err
		}

		// Update shelf inventory - ensure no negative quantities
		if err := tx.Model(&models.ShelfInventory{}).
			Where("product_id = ? AND current_quantity >= ?", availableProduct.ProductID, purchaseQty).
			Update("current_quantity", gorm.Expr("current_quantity - ?", purchaseQty)).Error; err != nil {
			tx.Rollback()
			return err
		}

		subtotal += itemSubtotal
		itemsAdded++
	}

	// If no items were added, rollback the invoice
	if itemsAdded == 0 {
		tx.Rollback()
		return fmt.Errorf("no items could be added to invoice")
	}

	// Update invoice totals
	taxAmount := subtotal * 0.10
	totalAmount := subtotal + taxAmount

	if err := tx.Model(&invoice).Updates(map[string]interface{}{
		"subtotal":     subtotal,
		"tax_amount":   taxAmount,
		"total_amount": totalAmount,
	}).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Update customer if applicable
	if customerID != nil {
		points := int(totalAmount / 10000)
		tx.Model(&models.Customer{}).
			Where("customer_id = ?", *customerID).
			Updates(map[string]interface{}{
				"total_spending": gorm.Expr("total_spending + ?", totalAmount),
				"loyalty_points": gorm.Expr("loyalty_points + ?", points),
			})
	}

	return tx.Commit().Error
}

func (s *RealisticSimulation) createEndScenarios() {
	// Create various scenarios for testing
	numProducts := len(s.products)
	if numProducts < 10 {
		return
	}

	// Some expired products
	for i := 0; i < 2; i++ {
		product := s.products[rand.Intn(numProducts)]
		expiredDate := s.currentDate.AddDate(0, 0, -rand.Intn(5)-1)
		s.db.Model(&models.ShelfBatchInventory{}).
			Where("product_id = ? AND quantity > 0", product.ProductID).
			Limit(1).
			Update("expiry_date", expiredDate)
	}

	// Some near-expiry
	for i := 0; i < 3; i++ {
		product := s.products[rand.Intn(numProducts)]
		nearExpiryDate := time.Now().AddDate(0, 0, rand.Intn(7)+1)
		s.db.Model(&models.ShelfBatchInventory{}).
			Where("product_id = ? AND quantity > 0", product.ProductID).
			Limit(1).
			Update("expiry_date", nearExpiryDate)
	}

	// Some out of stock in warehouse
	for i := 0; i < 2; i++ {
		product := s.products[rand.Intn(numProducts)]
		s.db.Model(&models.WarehouseInventory{}).
			Where("product_id = ?", product.ProductID).
			Update("quantity", 0)
	}
}

// Helper methods

func (s *RealisticSimulation) createPurchaseOrder(supplierID uint) (*models.PurchaseOrder, error) {
	s.orderCounter++
	orderNo := fmt.Sprintf("PO%s%03d", s.currentDate.Format("200601"), s.orderCounter)
	employee := s.getRandomEmployee("manager")

	order := models.PurchaseOrder{
		OrderNo:    orderNo,
		SupplierID: supplierID,
		EmployeeID: employee.EmployeeID,
		OrderDate:  s.currentDate,
		Status:     models.OrderReceived,
	}

	deliveryDate := s.currentDate
	order.DeliveryDate = &deliveryDate

	if err := s.db.Create(&order).Error; err != nil {
		return nil, err
	}

	return &order, nil
}

func (s *RealisticSimulation) orderProduct(product models.Product, quantity int) error {
	// DEBUG: Add validation and logging
	if quantity < 0 {
		return fmt.Errorf("cannot order negative quantity %d for product %s", quantity, product.ProductName)
	}

	// Skip ordering if quantity is zero
	if quantity == 0 {
		log.Printf("    INFO: Skipping order - zero quantity for product %s", product.ProductName)
		return nil
	}

	order, err := s.createPurchaseOrder(product.SupplierID)
	if err != nil {
		return err
	}

	tx := s.db.Begin()

	detail := models.PurchaseOrderDetail{
		OrderID:   order.OrderID,
		ProductID: product.ProductID,
		Quantity:  quantity,
		UnitPrice: product.ImportPrice,
		Subtotal:  float64(quantity) * product.ImportPrice,
	}

	if err := tx.Create(&detail).Error; err != nil {
		tx.Rollback()
		return err
	}

	if err := s.addToWarehouse(tx, product, quantity); err != nil {
		tx.Rollback()
		return err
	}

	if err := tx.Model(&order).Update("total_amount", detail.Subtotal).Error; err != nil {
		tx.Rollback()
		return err
	}

	return tx.Commit().Error
}

func (s *RealisticSimulation) addToWarehouse(tx *gorm.DB, product models.Product, quantity int) error {
	// Ensure quantity is never negative (allow zero for edge cases)
	if quantity < 0 {
		log.Printf("    WARN: Attempted to add negative quantity %d for product %s", quantity, product.ProductName)
		return fmt.Errorf("cannot add negative quantity %d to warehouse for product %s", quantity, product.ProductName)
	}

	// Skip adding if quantity is zero
	if quantity == 0 {
		log.Printf("    INFO: Skipping add to warehouse - zero quantity for product %s", product.ProductName)
		return nil
	}

	batchCode := fmt.Sprintf("BATCH%s%04d", s.currentDate.Format("20060102"), product.ProductID)

	// Calculate expiry based on current date and requirements
	expiryDate := s.calculateExpiry(product)

	inventory := models.WarehouseInventory{
		WarehouseID: s.warehouses[0].WarehouseID,
		ProductID:   product.ProductID,
		BatchCode:   batchCode,
		Quantity:    quantity,
		ImportDate:  s.currentDate,
		ExpiryDate:  &expiryDate,
		ImportPrice: product.ImportPrice,
	}

	return tx.Create(&inventory).Error
}

func (s *RealisticSimulation) calculateExpiry(product models.Product) time.Time {
	daysRemaining := int(s.endDate.Sub(s.currentDate).Hours() / 24)

	// Create varied expiry scenarios
	if daysRemaining <= 5 {
		random := rand.Float64()
		switch {
		case random < 0.15: // 15% expired
			return time.Now().AddDate(0, 0, -rand.Intn(3)-1)
		case random < 0.30: // 15% near expiry
			return time.Now().AddDate(0, 0, rand.Intn(7)+1)
		}
	}

	// Normal expiry
	if product.ShelfLifeDays != nil && *product.ShelfLifeDays > 0 {
		return s.currentDate.AddDate(0, 0, int(*product.ShelfLifeDays))
	}
	return s.currentDate.AddDate(0, 3, 0)
}

func (s *RealisticSimulation) transferToShelfWithTx(tx *gorm.DB, product models.Product, quantity int) error {
	// Find warehouse inventory for this product (FIFO)
	var warehouseInv models.WarehouseInventory
	if err := tx.Where("product_id = ? AND quantity >= ?", product.ProductID, quantity).
		Order("expiry_date ASC").First(&warehouseInv).Error; err != nil {
		return err
	}

	// Find shelf for this product category
	var shelf models.DisplayShelf
	if err := tx.Where("category_id = ?", product.CategoryID).First(&shelf).Error; err != nil {
		return err
	}

	s.transferCounter++
	transferCode := fmt.Sprintf("ST%s%04d", s.currentDate.Format("200601"), s.transferCounter)

	// Create stock transfer record
	transfer := models.StockTransfer{
		TransferCode:    transferCode,
		ProductID:       product.ProductID,
		FromWarehouseID: warehouseInv.WarehouseID,
		ToShelfID:       shelf.ShelfID,
		Quantity:        quantity,
		TransferDate:    s.currentDate,
		EmployeeID:      s.getRandomEmployee("warehouse").EmployeeID,
		BatchCode:       warehouseInv.BatchCode,
		ExpiryDate:      warehouseInv.ExpiryDate,
		ImportPrice:     warehouseInv.ImportPrice,
		SellingPrice:    product.SellingPrice,
	}

	if err := tx.Create(&transfer).Error; err != nil {
		return err
	}

	// Update warehouse - ensure no negative quantities
	if warehouseInv.Quantity < quantity {
		return fmt.Errorf("insufficient warehouse stock: have %d, need %d", warehouseInv.Quantity, quantity)
	}

	// Calculate new quantity and update directly
	newQuantity := warehouseInv.Quantity - quantity
	if err := tx.Model(&warehouseInv).Update("quantity", newQuantity).Error; err != nil {
		return err
	}

	// Create shelf batch
	shelfBatch := models.ShelfBatchInventory{
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
		return err
	}

	// Update shelf inventory
	var shelfInv models.ShelfInventory
	if err := tx.Where("shelf_id = ? AND product_id = ?", shelf.ShelfID, product.ProductID).
		First(&shelfInv).Error; err == gorm.ErrRecordNotFound {

		shelfInv = models.ShelfInventory{
			ShelfID:         shelf.ShelfID,
			ProductID:       product.ProductID,
			CurrentQuantity: quantity,
			LastRestocked:   s.currentDate,
		}
		if err := tx.Create(&shelfInv).Error; err != nil {
			return err
		}
	} else {
		if err := tx.Model(&shelfInv).
			Update("current_quantity", gorm.Expr("current_quantity + ?", quantity)).Error; err != nil {
			return err
		}
	}

	return nil
}

func (s *RealisticSimulation) transferToShelfInitial(tx *gorm.DB, product models.Product, quantity int) error {
	// Get warehouse inventory
	var warehouseInv models.WarehouseInventory
	if err := tx.Where("product_id = ? AND quantity >= ?", product.ProductID, quantity).
		Order("expiry_date ASC").
		First(&warehouseInv).Error; err != nil {
		return err
	}

	// Find appropriate shelf
	var shelf models.DisplayShelf
	if err := tx.Where("category_id = ?", product.CategoryID).First(&shelf).Error; err != nil {
		return err
	}

	s.transferCounter++
	transferCode := fmt.Sprintf("ST%s%04d", s.currentDate.Format("200601"), s.transferCounter)

	// Create transfer
	transfer := models.StockTransfer{
		TransferCode:    transferCode,
		ProductID:       product.ProductID,
		FromWarehouseID: warehouseInv.WarehouseID,
		ToShelfID:       shelf.ShelfID,
		Quantity:        quantity,
		TransferDate:    s.currentDate,
		EmployeeID:      s.getRandomEmployee("warehouse").EmployeeID,
		BatchCode:       warehouseInv.BatchCode,
		ExpiryDate:      warehouseInv.ExpiryDate,
		ImportPrice:     warehouseInv.ImportPrice,
		SellingPrice:    product.SellingPrice,
	}

	if err := tx.Create(&transfer).Error; err != nil {
		return err
	}

	// Update warehouse - ensure no negative quantities
	if warehouseInv.Quantity < quantity {
		tx.Rollback()
		return fmt.Errorf("insufficient warehouse stock: have %d, need %d", warehouseInv.Quantity, quantity)
	}
	// Calculate new quantity and update directly
	newQuantity := warehouseInv.Quantity - quantity
	if err := tx.Model(&warehouseInv).Update("quantity", newQuantity).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Create shelf batch
	shelfBatch := models.ShelfBatchInventory{
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
		return err
	}

	// Warehouse inventory already updated above

	// Update shelf inventory
	var shelfInv models.ShelfInventory
	if err := tx.Where("shelf_id = ? AND product_id = ?", shelf.ShelfID, product.ProductID).
		First(&shelfInv).Error; err == gorm.ErrRecordNotFound {

		shelfInv = models.ShelfInventory{
			ShelfID:         shelf.ShelfID,
			ProductID:       product.ProductID,
			CurrentQuantity: quantity,
			LastRestocked:   s.currentDate,
		}
		if err := tx.Create(&shelfInv).Error; err != nil {
			tx.Rollback()
			return err
		}
	} else {
		if err := tx.Model(&shelfInv).
			Update("current_quantity", gorm.Expr("current_quantity + ?", quantity)).Error; err != nil {
			tx.Rollback()
			return err
		}
	}

	return tx.Commit().Error
}

func (s *RealisticSimulation) createStockTransfer(product models.Product, warehouseInv models.WarehouseInventory, quantity int) error {
	// Find shelf
	var shelf models.DisplayShelf
	if err := s.db.Where("category_id = ?", product.CategoryID).First(&shelf).Error; err != nil {
		return err
	}

	s.transferCounter++
	transferCode := fmt.Sprintf("ST%s%04d", s.currentDate.Format("200601"), s.transferCounter)

	tx := s.db.Begin()

	transfer := models.StockTransfer{
		TransferCode:    transferCode,
		ProductID:       product.ProductID,
		FromWarehouseID: warehouseInv.WarehouseID,
		ToShelfID:       shelf.ShelfID,
		Quantity:        quantity,
		TransferDate:    s.currentDate,
		EmployeeID:      s.getRandomEmployee("warehouse").EmployeeID,
		BatchCode:       warehouseInv.BatchCode,
		ExpiryDate:      warehouseInv.ExpiryDate,
		ImportPrice:     warehouseInv.ImportPrice,
		SellingPrice:    product.SellingPrice,
	}

	if err := tx.Create(&transfer).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Update warehouse - ensure no negative quantities
	if warehouseInv.Quantity < quantity {
		tx.Rollback()
		return fmt.Errorf("insufficient warehouse stock: have %d, need %d", warehouseInv.Quantity, quantity)
	}
	// Calculate new quantity and update directly
	newQuantity := warehouseInv.Quantity - quantity
	if err := tx.Model(&warehouseInv).Update("quantity", newQuantity).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Update or create shelf batch
	var shelfBatch models.ShelfBatchInventory
	err := tx.Where("shelf_id = ? AND product_id = ? AND batch_code = ?",
		shelf.ShelfID, product.ProductID, warehouseInv.BatchCode).
		First(&shelfBatch).Error

	if err == gorm.ErrRecordNotFound {
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
			return err
		}
	} else {
		if err := tx.Model(&shelfBatch).
			Update("quantity", gorm.Expr("quantity + ?", quantity)).Error; err != nil {
			tx.Rollback()
			return err
		}
	}

	// Update shelf inventory
	var shelfInv models.ShelfInventory
	if err := tx.Where("shelf_id = ? AND product_id = ?", shelf.ShelfID, product.ProductID).
		First(&shelfInv).Error; err == gorm.ErrRecordNotFound {

		shelfInv = models.ShelfInventory{
			ShelfID:         shelf.ShelfID,
			ProductID:       product.ProductID,
			CurrentQuantity: quantity,
			LastRestocked:   s.currentDate,
		}
		if err := tx.Create(&shelfInv).Error; err != nil {
			tx.Rollback()
			return err
		}
	} else {
		if err := tx.Model(&shelfInv).Updates(map[string]interface{}{
			"current_quantity": gorm.Expr("current_quantity + ?", quantity),
			"last_restocked":   s.currentDate,
		}).Error; err != nil {
			tx.Rollback()
			return err
		}
	}

	return tx.Commit().Error
}

func (s *RealisticSimulation) createShelfLayouts() error {
	// Clear existing
	s.db.Exec("TRUNCATE TABLE shelf_layout RESTART IDENTITY")

	for _, product := range s.products {
		var shelf models.DisplayShelf
		if err := s.db.Where("category_id = ?", product.CategoryID).First(&shelf).Error; err != nil {
			continue
		}

		layout := models.ShelfLayout{
			ShelfID:      shelf.ShelfID,
			ProductID:    product.ProductID,
			MaxQuantity:  200,
			PositionCode: fmt.Sprintf("POS-%d-%d", shelf.ShelfID, product.ProductID),
		}

		s.db.Create(&layout)
	}

	return nil
}

func (s *RealisticSimulation) getRandomEmployee(role string) models.Employee {
	if len(s.employees) == 0 {
		return models.Employee{EmployeeID: 1}
	}

	// Simple role matching: 1=Manager, 2=Supervisor, 3=Cashier, 4=Warehouse
	for _, emp := range s.employees {
		switch role {
		case "manager":
			if emp.PositionID == 1 || emp.PositionID == 2 {
				return emp
			}
		case "cashier":
			if emp.PositionID == 3 {
				return emp
			}
		case "warehouse":
			if emp.PositionID == 4 {
				return emp
			}
		}
	}

	return s.employees[rand.Intn(len(s.employees))]
}

func (s *RealisticSimulation) getPaymentMethod() models.PaymentMethod {
	r := rand.Float64()
	switch {
	case r < 0.4:
		return models.PaymentCash
	case r < 0.7:
		return models.PaymentCard
	case r < 0.9:
		return models.PaymentTransfer
	default:
		return models.PaymentVoucher
	}
}

func (s *RealisticSimulation) printSummary() {
	log.Println("\n" + strings.Repeat("═", 50))
	log.Println("REALISTIC SIMULATION SUMMARY")
	log.Println(strings.Repeat("═", 50))

	// Statistics
	var stats struct {
		Orders    int64
		Transfers int64
		Invoices  int64
		Revenue   float64
	}

	s.db.Model(&models.PurchaseOrder{}).
		Where("order_date BETWEEN ? AND ?", s.startDate, s.endDate).
		Count(&stats.Orders)

	s.db.Model(&models.StockTransfer{}).
		Where("transfer_date BETWEEN ? AND ?", s.startDate, s.endDate).
		Count(&stats.Transfers)

	s.db.Model(&models.SalesInvoice{}).
		Where("invoice_date BETWEEN ? AND ?", s.startDate, s.endDate).
		Count(&stats.Invoices)

	s.db.Model(&models.SalesInvoice{}).
		Where("invoice_date BETWEEN ? AND ?", s.startDate, s.endDate).
		Select("COALESCE(SUM(total_amount), 0)").
		Scan(&stats.Revenue)

	log.Printf("Purchase Orders: %d", stats.Orders)
	log.Printf("Stock Transfers: %d", stats.Transfers)
	log.Printf("Sales Invoices: %d", stats.Invoices)
	log.Printf("Total Revenue: %.0f VND", stats.Revenue)

	// Inventory status
	var expired, nearExpiry, outOfStock, lowStock int64

	s.db.Model(&models.ShelfBatchInventory{}).
		Where("expiry_date < ? AND quantity > 0", time.Now()).
		Count(&expired)

	s.db.Model(&models.ShelfBatchInventory{}).
		Where("expiry_date BETWEEN ? AND ? AND quantity > 0",
			time.Now(), time.Now().AddDate(0, 0, 7)).
		Count(&nearExpiry)

	s.db.Raw(`
		SELECT COUNT(DISTINCT product_id) 
		FROM supermarket.products p 
		WHERE NOT EXISTS (
			SELECT 1 FROM warehouse_inventory wi 
			WHERE wi.product_id = p.product_id AND wi.quantity > 0
		)
	`).Scan(&outOfStock)

	s.db.Raw(`
		SELECT COUNT(DISTINCT product_id)
		FROM (
			SELECT product_id, SUM(quantity) as total
			FROM warehouse_inventory
			GROUP BY product_id
			HAVING SUM(quantity) > 0 AND SUM(quantity) < 10
		) AS low
	`).Scan(&lowStock)

	log.Println("\nInventory Status:")
	log.Printf("  Expired: %d batches", expired)
	log.Printf("  Near Expiry: %d batches", nearExpiry)
	log.Printf("  Out of Stock: %d products", outOfStock)
	log.Printf("  Low Stock: %d products", lowStock)

	log.Println(strings.Repeat("═", 50))
}
