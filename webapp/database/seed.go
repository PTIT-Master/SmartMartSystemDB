package database

import (
	"fmt"
	"log"
	"time"

	"github.com/supermarket/models"
	"gorm.io/gorm"
)

// SeedData seeds initial data into empty tables
func SeedData(db *gorm.DB) error {
	log.Println("Checking if database needs seeding...")

	// Check if data already exists
	var count int64
	db.Model(&models.Product{}).Count(&count)
	if count > 0 {
		log.Println("Database already has data. Skipping seed.")
		return nil
	}

	log.Println("Database is empty. Starting seed process...")

	// Use transaction for data integrity
	return db.Transaction(func(tx *gorm.DB) error {
		// Set search path
		if err := tx.Exec("SET search_path TO supermarket").Error; err != nil {
			return fmt.Errorf("failed to set search path: %w", err)
		}

		// 1. Seed Warehouses
		warehouseMap, err := seedWarehouses(tx)
		if err != nil {
			return fmt.Errorf("failed to seed warehouses: %w", err)
		}

		// 2. Seed Product Categories
		categoryMap, err := seedProductCategories(tx)
		if err != nil {
			return fmt.Errorf("failed to seed product categories: %w", err)
		}

		// 3. Seed Positions
		positionMap, err := seedPositions(tx)
		if err != nil {
			return fmt.Errorf("failed to seed positions: %w", err)
		}

		// 4. Seed Membership Levels
		membershipMap, err := seedMembershipLevels(tx)
		if err != nil {
			return fmt.Errorf("failed to seed membership levels: %w", err)
		}

		// 5. Seed Suppliers
		supplierMap, err := seedSuppliers(tx)
		if err != nil {
			return fmt.Errorf("failed to seed suppliers: %w", err)
		}

		// 6. Seed Employees
		employeeMap, err := seedEmployees(tx, positionMap)
		if err != nil {
			return fmt.Errorf("failed to seed employees: %w", err)
		}

		// 7. Seed Products
		productMap, err := seedProducts(tx, categoryMap, supplierMap)
		if err != nil {
			return fmt.Errorf("failed to seed products: %w", err)
		}

		// 8. Seed Display Shelves
		shelfMap, err := seedDisplayShelves(tx, categoryMap)
		if err != nil {
			return fmt.Errorf("failed to seed display shelves: %w", err)
		}

		// 9. Seed Discount Rules
		if err := seedDiscountRules(tx, categoryMap); err != nil {
			return fmt.Errorf("failed to seed discount rules: %w", err)
		}

		// 10. Seed Customers
		customerMap, err := seedCustomers(tx, membershipMap)
		if err != nil {
			return fmt.Errorf("failed to seed customers: %w", err)
		}

		// 11. Seed Initial Inventory
		if err := seedWarehouseInventory(tx, warehouseMap, productMap); err != nil {
			return fmt.Errorf("failed to seed warehouse inventory: %w", err)
		}

		// 12. Seed Shelf Layout and Inventory
		if err := seedShelfData(tx, shelfMap, productMap); err != nil {
			return fmt.Errorf("failed to seed shelf data: %w", err)
		}

		// 13. Seed Employee Work Hours
		if err := seedEmployeeWorkHours(tx, employeeMap); err != nil {
			return fmt.Errorf("failed to seed employee work hours: %w", err)
		}

		// 14. Seed Purchase Orders
		if err := seedPurchaseOrders(tx, employeeMap, supplierMap, productMap); err != nil {
			return fmt.Errorf("failed to seed purchase orders: %w", err)
		}

		// 15. Seed Stock Transfers
		if err := seedStockTransfers(tx, warehouseMap, shelfMap, productMap, employeeMap); err != nil {
			return fmt.Errorf("failed to seed stock transfers: %w", err)
		}

		// 16. Seed Sales Invoices
		if err := seedSalesInvoices(tx, customerMap, employeeMap, productMap); err != nil {
			return fmt.Errorf("failed to seed sales invoices: %w", err)
		}

		log.Println("✅ Database seeded successfully!")
		return nil
	})
}

func seedWarehouses(tx *gorm.DB) (map[string]uint, error) {
	warehouses := []models.Warehouse{
		{
			WarehouseCode: "WH001",
			WarehouseName: "Kho chính",
			Location:      strPtr("Tầng hầm B1"),
			Capacity:      intPtr(10000),
		},
		{
			WarehouseCode: "WH002",
			WarehouseName: "Kho phụ",
			Location:      strPtr("Tầng hầm B2"),
			Capacity:      intPtr(5000),
		},
	}

	if err := tx.Create(&warehouses).Error; err != nil {
		return nil, err
	}
	log.Printf("  ✓ Seeded %d warehouses", len(warehouses))

	// Return warehouse ID map
	warehouseMap := make(map[string]uint)
	for _, wh := range warehouses {
		warehouseMap[wh.WarehouseCode] = wh.WarehouseID
	}
	return warehouseMap, nil
}

func seedProductCategories(tx *gorm.DB) (map[string]uint, error) {
	categories := []models.ProductCategory{
		{CategoryName: "Văn phòng phẩm", Description: strPtr("Đồ dùng văn phòng, học tập")},
		{CategoryName: "Đồ gia dụng", Description: strPtr("Đồ dùng gia đình")},
		{CategoryName: "Đồ điện tử", Description: strPtr("Thiết bị điện tử tiêu dùng")},
		{CategoryName: "Đồ bếp", Description: strPtr("Dụng cụ nhà bếp")},
		{CategoryName: "Thực phẩm", Description: strPtr("Thực phẩm các loại")},
		{CategoryName: "Đồ uống", Description: strPtr("Nước giải khát, đồ uống các loại")},
		{CategoryName: "Mỹ phẩm", Description: strPtr("Mỹ phẩm và chăm sóc cá nhân")},
		{CategoryName: "Thời trang", Description: strPtr("Quần áo, giày dép, phụ kiện")},
	}

	if err := tx.Create(&categories).Error; err != nil {
		return nil, err
	}
	log.Printf("  ✓ Seeded %d product categories", len(categories))

	// Return category ID map
	categoryMap := make(map[string]uint)
	for _, cat := range categories {
		categoryMap[cat.CategoryName] = cat.CategoryID
	}
	return categoryMap, nil
}

func seedPositions(tx *gorm.DB) (map[string]uint, error) {
	positions := []models.Position{
		{PositionCode: "MGR", PositionName: "Quản lý", BaseSalary: 15000000, HourlyRate: 100000},
		{PositionCode: "SUP", PositionName: "Giám sát", BaseSalary: 10000000, HourlyRate: 70000},
		{PositionCode: "CASH", PositionName: "Thu ngân", BaseSalary: 7000000, HourlyRate: 50000},
		{PositionCode: "SALE", PositionName: "Nhân viên bán hàng", BaseSalary: 6000000, HourlyRate: 45000},
		{PositionCode: "STOCK", PositionName: "Nhân viên kho", BaseSalary: 6500000, HourlyRate: 48000},
		{PositionCode: "SEC", PositionName: "Bảo vệ", BaseSalary: 5500000, HourlyRate: 40000},
	}

	if err := tx.Create(&positions).Error; err != nil {
		return nil, err
	}
	log.Printf("  ✓ Seeded %d positions", len(positions))

	// Return position ID map
	positionMap := make(map[string]uint)
	for _, pos := range positions {
		positionMap[pos.PositionCode] = pos.PositionID
	}
	return positionMap, nil
}

func seedMembershipLevels(tx *gorm.DB) (map[string]uint, error) {
	levels := []models.MembershipLevel{
		{LevelName: "Bronze", MinSpending: 0, DiscountPercentage: 0, PointsMultiplier: 1.0},
		{LevelName: "Silver", MinSpending: 5000000, DiscountPercentage: 3, PointsMultiplier: 1.2},
		{LevelName: "Gold", MinSpending: 20000000, DiscountPercentage: 5, PointsMultiplier: 1.5},
		{LevelName: "Platinum", MinSpending: 50000000, DiscountPercentage: 8, PointsMultiplier: 2.0},
		{LevelName: "Diamond", MinSpending: 100000000, DiscountPercentage: 10, PointsMultiplier: 2.5},
	}

	if err := tx.Create(&levels).Error; err != nil {
		return nil, err
	}
	log.Printf("  ✓ Seeded %d membership levels", len(levels))

	// Return membership level ID map
	membershipMap := make(map[string]uint)
	for _, level := range levels {
		membershipMap[level.LevelName] = level.LevelID
	}
	return membershipMap, nil
}

func seedSuppliers(tx *gorm.DB) (map[string]uint, error) {
	suppliers := []models.Supplier{
		{
			SupplierCode:  "SUP001",
			SupplierName:  "Công ty TNHH Thực phẩm Sài Gòn",
			ContactPerson: strPtr("Nguyễn Văn A"),
			Phone:         strPtr("0901234567"),
			Email:         strPtr("contact@sgfood.vn"),
			Address:       strPtr("123 Nguyễn Văn Cừ, Q5, TP.HCM"),
		},
		{
			SupplierCode:  "SUP002",
			SupplierName:  "Công ty CP Điện tử Việt Nam",
			ContactPerson: strPtr("Trần Thị B"),
			Phone:         strPtr("0912345678"),
			Email:         strPtr("sales@vnelec.com"),
			Address:       strPtr("456 Lý Thường Kiệt, Q10, TP.HCM"),
		},
		{
			SupplierCode:  "SUP003",
			SupplierName:  "Công ty TNHH Văn phòng phẩm Á Châu",
			ContactPerson: strPtr("Lê Văn C"),
			Phone:         strPtr("0923456789"),
			Email:         strPtr("info@acoffice.vn"),
			Address:       strPtr("789 Cách Mạng Tháng 8, Q3, TP.HCM"),
		},
		{
			SupplierCode:  "SUP004",
			SupplierName:  "Công ty CP Đồ gia dụng Minh Long",
			ContactPerson: strPtr("Phạm Thị D"),
			Phone:         strPtr("0934567890"),
			Email:         strPtr("contact@minhlong.vn"),
			Address:       strPtr("321 Võ Văn Tần, Q3, TP.HCM"),
		},
		{
			SupplierCode:  "SUP005",
			SupplierName:  "Công ty TNHH Nước giải khát Tân Hiệp Phát",
			ContactPerson: strPtr("Hoàng Văn E"),
			Phone:         strPtr("0945678901"),
			Email:         strPtr("sales@thp.vn"),
			Address:       strPtr("654 Quốc lộ 1A, Bình Dương"),
		},
	}

	if err := tx.Create(&suppliers).Error; err != nil {
		return nil, err
	}
	log.Printf("  ✓ Seeded %d suppliers", len(suppliers))

	// Return supplier ID map
	supplierMap := make(map[string]uint)
	for _, sup := range suppliers {
		supplierMap[sup.SupplierCode] = sup.SupplierID
	}
	return supplierMap, nil
}

func seedEmployees(tx *gorm.DB, positionMap map[string]uint) (map[string]uint, error) {
	hireDate, _ := time.Parse("2006-01-02", "2024-01-01")

	employees := []models.Employee{
		{
			EmployeeCode: "EMP001",
			FullName:     "Nguyễn Quản Lý",
			PositionID:   positionMap["MGR"],
			Phone:        strPtr("0901111111"),
			Email:        strPtr("manager@supermarket.vn"),
			HireDate:     hireDate,
		},
		{
			EmployeeCode: "EMP002",
			FullName:     "Trần Giám Sát",
			PositionID:   positionMap["SUP"],
			Phone:        strPtr("0902222222"),
			Email:        strPtr("supervisor@supermarket.vn"),
			HireDate:     hireDate.AddDate(0, 0, 14),
		},
		{
			EmployeeCode: "EMP003",
			FullName:     "Lê Thu Ngân",
			PositionID:   positionMap["CASH"],
			Phone:        strPtr("0903333333"),
			Email:        strPtr("cashier1@supermarket.vn"),
			HireDate:     hireDate.AddDate(0, 1, 0),
		},
		{
			EmployeeCode: "EMP004",
			FullName:     "Phạm Bán Hàng",
			PositionID:   positionMap["SALE"],
			Phone:        strPtr("0904444444"),
			Email:        strPtr("sales1@supermarket.vn"),
			HireDate:     hireDate.AddDate(0, 1, 14),
		},
		{
			EmployeeCode: "EMP005",
			FullName:     "Hoàng Thủ Kho",
			PositionID:   positionMap["STOCK"],
			Phone:        strPtr("0905555555"),
			Email:        strPtr("stock1@supermarket.vn"),
			HireDate:     hireDate.AddDate(0, 2, 0),
		},
		{
			EmployeeCode: "EMP006",
			FullName:     "Võ Thu Ngân 2",
			PositionID:   positionMap["CASH"],
			Phone:        strPtr("0906666666"),
			Email:        strPtr("cashier2@supermarket.vn"),
			HireDate:     hireDate.AddDate(0, 2, 15),
		},
	}

	if err := tx.Create(&employees).Error; err != nil {
		return nil, err
	}
	log.Printf("  ✓ Seeded %d employees", len(employees))

	// Return employee ID map
	employeeMap := make(map[string]uint)
	for _, emp := range employees {
		employeeMap[emp.EmployeeCode] = emp.EmployeeID
	}
	return employeeMap, nil
}

func seedProducts(tx *gorm.DB, categoryMap map[string]uint, supplierMap map[string]uint) (map[string]uint, error) {
	products := []models.Product{
		// Văn phòng phẩm (SUP003)
		{ProductCode: "VPP001", ProductName: "Bút bi Thiên Long", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Cây", ImportPrice: 3000, SellingPrice: 5000, ShelfLifeDays: intPtr(365), LowStockThreshold: 20},
		{ProductCode: "VPP002", ProductName: "Vở học sinh 96 trang", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Quyển", ImportPrice: 8000, SellingPrice: 12000, ShelfLifeDays: intPtr(365), LowStockThreshold: 30},
		{ProductCode: "VPP003", ProductName: "Bút chì 2B", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Cây", ImportPrice: 2000, SellingPrice: 3500, ShelfLifeDays: intPtr(365), LowStockThreshold: 25},

		// Đồ gia dụng (SUP004)
		{ProductCode: "GD001", ProductName: "Chảo chống dính 26cm", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 150000, SellingPrice: 250000, LowStockThreshold: 5},
		{ProductCode: "GD002", ProductName: "Bộ nồi inox 3 món", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Bộ", ImportPrice: 350000, SellingPrice: 550000, LowStockThreshold: 3},
		{ProductCode: "GD003", ProductName: "Khăn tắm cotton", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 45000, SellingPrice: 75000, LowStockThreshold: 10},

		// Đồ điện tử (SUP002)
		{ProductCode: "DT001", ProductName: "Tai nghe Bluetooth", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 200000, SellingPrice: 350000, LowStockThreshold: 10},
		{ProductCode: "DT002", ProductName: "Sạc dự phòng 10000mAh", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 180000, SellingPrice: 300000, LowStockThreshold: 8},
		{ProductCode: "DT003", ProductName: "Cáp USB Type-C", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 25000, SellingPrice: 50000, LowStockThreshold: 15},

		// Thực phẩm (SUP001)
		{ProductCode: "TP001", ProductName: "Gạo ST25 5kg", CategoryID: categoryMap["Thực phẩm"], SupplierID: supplierMap["SUP001"], Unit: "Bao", ImportPrice: 120000, SellingPrice: 180000, ShelfLifeDays: intPtr(180), LowStockThreshold: 10},
		{ProductCode: "TP002", ProductName: "Mì gói Hảo Hảo", CategoryID: categoryMap["Thực phẩm"], SupplierID: supplierMap["SUP001"], Unit: "Thùng", ImportPrice: 85000, SellingPrice: 115000, ShelfLifeDays: intPtr(180), LowStockThreshold: 20},
		{ProductCode: "TP003", ProductName: "Dầu ăn Tường An 1L", CategoryID: categoryMap["Thực phẩm"], SupplierID: supplierMap["SUP001"], Unit: "Chai", ImportPrice: 35000, SellingPrice: 52000, ShelfLifeDays: intPtr(365), LowStockThreshold: 15},

		// Đồ uống (SUP005)
		{ProductCode: "DU001", ProductName: "Nước suối Aquafina 500ml", CategoryID: categoryMap["Đồ uống"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 80000, SellingPrice: 120000, ShelfLifeDays: intPtr(365), LowStockThreshold: 15},
		{ProductCode: "DU002", ProductName: "Trà xanh không độ", CategoryID: categoryMap["Đồ uống"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 140000, SellingPrice: 200000, ShelfLifeDays: intPtr(180), LowStockThreshold: 10},
		{ProductCode: "DU003", ProductName: "Coca Cola 330ml", CategoryID: categoryMap["Đồ uống"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 180000, SellingPrice: 260000, ShelfLifeDays: intPtr(365), LowStockThreshold: 12},
	}

	if err := tx.Create(&products).Error; err != nil {
		return nil, err
	}
	log.Printf("  ✓ Seeded %d products", len(products))

	// Return product ID map
	productMap := make(map[string]uint)
	for _, product := range products {
		productMap[product.ProductCode] = product.ProductID
	}
	return productMap, nil
}

func seedDisplayShelves(tx *gorm.DB, categoryMap map[string]uint) (map[string]uint, error) {
	shelves := []models.DisplayShelf{
		{ShelfCode: "SH001", ShelfName: "Quầy văn phòng phẩm 1", CategoryID: categoryMap["Văn phòng phẩm"], Location: strPtr("Khu A - Tầng 1"), MaxCapacity: intPtr(500)},
		{ShelfCode: "SH002", ShelfName: "Quầy đồ gia dụng 1", CategoryID: categoryMap["Đồ gia dụng"], Location: strPtr("Khu B - Tầng 1"), MaxCapacity: intPtr(200)},
		{ShelfCode: "SH003", ShelfName: "Quầy điện tử 1", CategoryID: categoryMap["Đồ điện tử"], Location: strPtr("Khu C - Tầng 1"), MaxCapacity: intPtr(300)},
		{ShelfCode: "SH004", ShelfName: "Quầy thực phẩm khô", CategoryID: categoryMap["Thực phẩm"], Location: strPtr("Khu D - Tầng 1"), MaxCapacity: intPtr(800)},
		{ShelfCode: "SH005", ShelfName: "Quầy đồ uống", CategoryID: categoryMap["Đồ uống"], Location: strPtr("Khu E - Tầng 1"), MaxCapacity: intPtr(600)},
		{ShelfCode: "SH006", ShelfName: "Quầy văn phòng phẩm 2", CategoryID: categoryMap["Văn phòng phẩm"], Location: strPtr("Khu A - Tầng 2"), MaxCapacity: intPtr(400)},
	}

	if err := tx.Create(&shelves).Error; err != nil {
		return nil, err
	}
	log.Printf("  ✓ Seeded %d display shelves", len(shelves))

	// Return shelf ID map
	shelfMap := make(map[string]uint)
	for _, shelf := range shelves {
		shelfMap[shelf.ShelfCode] = shelf.ShelfID
	}
	return shelfMap, nil
}

func seedDiscountRules(tx *gorm.DB, categoryMap map[string]uint) error {
	rules := []models.DiscountRule{
		{CategoryID: categoryMap["Thực phẩm"], DaysBeforeExpiry: 7, DiscountPercentage: 30, RuleName: strPtr("Thực phẩm - giảm 30%")},
		{CategoryID: categoryMap["Thực phẩm"], DaysBeforeExpiry: 3, DiscountPercentage: 50, RuleName: strPtr("Thực phẩm - giảm 50%")},
		{CategoryID: categoryMap["Đồ uống"], DaysBeforeExpiry: 10, DiscountPercentage: 20, RuleName: strPtr("Đồ uống - giảm 20%")},
		{CategoryID: categoryMap["Đồ uống"], DaysBeforeExpiry: 5, DiscountPercentage: 40, RuleName: strPtr("Đồ uống - giảm 40%")},
	}

	if err := tx.Create(&rules).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d discount rules", len(rules))
	return nil
}

func seedCustomers(tx *gorm.DB, membershipMap map[string]uint) (map[string]uint, error) {
	regDate, _ := time.Parse("2006-01-02", "2024-01-01")

	customers := []models.Customer{
		{
			CustomerCode:      strPtr("CUST001"),
			FullName:          strPtr("Nguyễn Văn Khách"),
			Phone:             strPtr("0971234567"),
			Email:             strPtr("customer1@gmail.com"),
			MembershipCardNo:  strPtr("MB001"),
			MembershipLevelID: uintPtr(membershipMap["Bronze"]),
			RegistrationDate:  regDate,
			TotalSpending:     2500000,
			LoyaltyPoints:     250,
		},
		{
			CustomerCode:      strPtr("CUST002"),
			FullName:          strPtr("Trần Thị Mai"),
			Phone:             strPtr("0981234567"),
			Email:             strPtr("customer2@gmail.com"),
			MembershipCardNo:  strPtr("MB002"),
			MembershipLevelID: uintPtr(membershipMap["Silver"]),
			RegistrationDate:  regDate,
			TotalSpending:     8000000,
			LoyaltyPoints:     960,
		},
		{
			CustomerCode:      strPtr("CUST003"),
			FullName:          strPtr("Lê Hoàng Nam"),
			Phone:             strPtr("0991234567"),
			Email:             strPtr("customer3@gmail.com"),
			MembershipCardNo:  strPtr("MB003"),
			MembershipLevelID: uintPtr(membershipMap["Gold"]),
			RegistrationDate:  regDate,
			TotalSpending:     25000000,
			LoyaltyPoints:     3750,
		},
		{
			CustomerCode:      strPtr("CUST004"),
			FullName:          strPtr("Phạm Thúy Hằng"),
			Phone:             strPtr("0961234567"),
			Email:             strPtr("customer4@gmail.com"),
			MembershipCardNo:  strPtr("MB004"),
			MembershipLevelID: uintPtr(membershipMap["Bronze"]),
			RegistrationDate:  regDate,
			TotalSpending:     1500000,
			LoyaltyPoints:     150,
		},
		{
			CustomerCode:      strPtr("CUST005"),
			FullName:          strPtr("Hoàng Minh Tuấn"),
			Phone:             strPtr("0951234567"),
			Email:             strPtr("customer5@gmail.com"),
			MembershipCardNo:  strPtr("MB005"),
			MembershipLevelID: uintPtr(membershipMap["Platinum"]),
			RegistrationDate:  regDate,
			TotalSpending:     55000000,
			LoyaltyPoints:     11000,
		},
	}

	if err := tx.Create(&customers).Error; err != nil {
		return nil, err
	}
	log.Printf("  ✓ Seeded %d customers", len(customers))

	// Return customer ID map
	customerMap := make(map[string]uint)
	for _, customer := range customers {
		if customer.CustomerCode != nil {
			customerMap[*customer.CustomerCode] = customer.CustomerID
		}
	}
	return customerMap, nil
}

func seedWarehouseInventory(tx *gorm.DB, warehouseMap map[string]uint, productMap map[string]uint) error {
	importDate := time.Now().AddDate(0, 0, -30)
	expiryDate := time.Now().AddDate(0, 6, 0)
	mainWarehouseID := warehouseMap["WH001"]

	inventory := []models.WarehouseInventory{
		// Văn phòng phẩm
		{WarehouseID: mainWarehouseID, ProductID: productMap["VPP001"], BatchCode: "VPP001-2024-01", Quantity: 500, ImportDate: importDate, ImportPrice: 3000},
		{WarehouseID: mainWarehouseID, ProductID: productMap["VPP002"], BatchCode: "VPP002-2024-01", Quantity: 300, ImportDate: importDate, ImportPrice: 8000},
		{WarehouseID: mainWarehouseID, ProductID: productMap["VPP003"], BatchCode: "VPP003-2024-01", Quantity: 400, ImportDate: importDate, ImportPrice: 2000},

		// Đồ gia dụng
		{WarehouseID: mainWarehouseID, ProductID: productMap["GD001"], BatchCode: "GD001-2024-01", Quantity: 50, ImportDate: importDate, ImportPrice: 150000},
		{WarehouseID: mainWarehouseID, ProductID: productMap["GD002"], BatchCode: "GD002-2024-01", Quantity: 30, ImportDate: importDate, ImportPrice: 350000},
		{WarehouseID: mainWarehouseID, ProductID: productMap["GD003"], BatchCode: "GD003-2024-01", Quantity: 100, ImportDate: importDate, ImportPrice: 45000},

		// Đồ điện tử
		{WarehouseID: mainWarehouseID, ProductID: productMap["DT001"], BatchCode: "DT001-2024-01", Quantity: 80, ImportDate: importDate, ImportPrice: 200000},
		{WarehouseID: mainWarehouseID, ProductID: productMap["DT002"], BatchCode: "DT002-2024-01", Quantity: 60, ImportDate: importDate, ImportPrice: 180000},
		{WarehouseID: mainWarehouseID, ProductID: productMap["DT003"], BatchCode: "DT003-2024-01", Quantity: 150, ImportDate: importDate, ImportPrice: 25000},

		// Thực phẩm (có hạn sử dụng)
		{WarehouseID: mainWarehouseID, ProductID: productMap["TP001"], BatchCode: "TP001-2024-01", Quantity: 100, ImportDate: importDate, ExpiryDate: &expiryDate, ImportPrice: 120000},
		{WarehouseID: mainWarehouseID, ProductID: productMap["TP002"], BatchCode: "TP002-2024-01", Quantity: 200, ImportDate: importDate, ExpiryDate: &expiryDate, ImportPrice: 85000},
		{WarehouseID: mainWarehouseID, ProductID: productMap["TP003"], BatchCode: "TP003-2024-01", Quantity: 150, ImportDate: importDate, ImportPrice: 35000},

		// Đồ uống
		{WarehouseID: mainWarehouseID, ProductID: productMap["DU001"], BatchCode: "DU001-2024-01", Quantity: 150, ImportDate: importDate, ImportPrice: 80000},
		{WarehouseID: mainWarehouseID, ProductID: productMap["DU002"], BatchCode: "DU002-2024-01", Quantity: 100, ImportDate: importDate, ExpiryDate: &expiryDate, ImportPrice: 140000},
		{WarehouseID: mainWarehouseID, ProductID: productMap["DU003"], BatchCode: "DU003-2024-01", Quantity: 120, ImportDate: importDate, ImportPrice: 180000},
	}

	if err := tx.Create(&inventory).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d warehouse inventory items", len(inventory))
	return nil
}

func seedShelfData(tx *gorm.DB, shelfMap map[string]uint, productMap map[string]uint) error {
	// Shelf Layout
	layouts := []models.ShelfLayout{
		// Văn phòng phẩm
		{ShelfID: shelfMap["SH001"], ProductID: productMap["VPP001"], PositionCode: "A1", MaxQuantity: 100},
		{ShelfID: shelfMap["SH001"], ProductID: productMap["VPP002"], PositionCode: "A2", MaxQuantity: 80},
		{ShelfID: shelfMap["SH001"], ProductID: productMap["VPP003"], PositionCode: "A3", MaxQuantity: 120},

		// Đồ gia dụng
		{ShelfID: shelfMap["SH002"], ProductID: productMap["GD001"], PositionCode: "B1", MaxQuantity: 20},
		{ShelfID: shelfMap["SH002"], ProductID: productMap["GD002"], PositionCode: "B2", MaxQuantity: 15},
		{ShelfID: shelfMap["SH002"], ProductID: productMap["GD003"], PositionCode: "B3", MaxQuantity: 40},

		// Điện tử
		{ShelfID: shelfMap["SH003"], ProductID: productMap["DT001"], PositionCode: "C1", MaxQuantity: 30},
		{ShelfID: shelfMap["SH003"], ProductID: productMap["DT002"], PositionCode: "C2", MaxQuantity: 25},
		{ShelfID: shelfMap["SH003"], ProductID: productMap["DT003"], PositionCode: "C3", MaxQuantity: 50},

		// Thực phẩm
		{ShelfID: shelfMap["SH004"], ProductID: productMap["TP001"], PositionCode: "D1", MaxQuantity: 50},
		{ShelfID: shelfMap["SH004"], ProductID: productMap["TP002"], PositionCode: "D2", MaxQuantity: 100},
		{ShelfID: shelfMap["SH004"], ProductID: productMap["TP003"], PositionCode: "D3", MaxQuantity: 80},

		// Đồ uống
		{ShelfID: shelfMap["SH005"], ProductID: productMap["DU001"], PositionCode: "E1", MaxQuantity: 60},
		{ShelfID: shelfMap["SH005"], ProductID: productMap["DU002"], PositionCode: "E2", MaxQuantity: 50},
		{ShelfID: shelfMap["SH005"], ProductID: productMap["DU003"], PositionCode: "E3", MaxQuantity: 55},
	}

	if err := tx.Create(&layouts).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d shelf layouts", len(layouts))

	// Shelf Inventory
	inventories := []models.ShelfInventory{
		// Văn phòng phẩm
		{ShelfID: shelfMap["SH001"], ProductID: productMap["VPP001"], CurrentQuantity: 50},
		{ShelfID: shelfMap["SH001"], ProductID: productMap["VPP002"], CurrentQuantity: 40},
		{ShelfID: shelfMap["SH001"], ProductID: productMap["VPP003"], CurrentQuantity: 60},

		// Đồ gia dụng
		{ShelfID: shelfMap["SH002"], ProductID: productMap["GD001"], CurrentQuantity: 10},
		{ShelfID: shelfMap["SH002"], ProductID: productMap["GD002"], CurrentQuantity: 8},
		{ShelfID: shelfMap["SH002"], ProductID: productMap["GD003"], CurrentQuantity: 20},

		// Điện tử
		{ShelfID: shelfMap["SH003"], ProductID: productMap["DT001"], CurrentQuantity: 15},
		{ShelfID: shelfMap["SH003"], ProductID: productMap["DT002"], CurrentQuantity: 12},
		{ShelfID: shelfMap["SH003"], ProductID: productMap["DT003"], CurrentQuantity: 25},

		// Thực phẩm
		{ShelfID: shelfMap["SH004"], ProductID: productMap["TP001"], CurrentQuantity: 25},
		{ShelfID: shelfMap["SH004"], ProductID: productMap["TP002"], CurrentQuantity: 50},
		{ShelfID: shelfMap["SH004"], ProductID: productMap["TP003"], CurrentQuantity: 40},

		// Đồ uống
		{ShelfID: shelfMap["SH005"], ProductID: productMap["DU001"], CurrentQuantity: 30},
		{ShelfID: shelfMap["SH005"], ProductID: productMap["DU002"], CurrentQuantity: 25},
		{ShelfID: shelfMap["SH005"], ProductID: productMap["DU003"], CurrentQuantity: 28},
	}

	if err := tx.Create(&inventories).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d shelf inventory items", len(inventories))
	return nil
}

func seedEmployeeWorkHours(tx *gorm.DB, employeeMap map[string]uint) error {
	// Seed work hours for September 2025 (up to 14th)
	// Assuming 8-hour work days, Mon-Sat
	workHours := []models.EmployeeWorkHour{}

	// Generate work hours for first 2 weeks of September 2025
	startDate, _ := time.Parse("2006-01-02", "2025-09-01")
	endDate, _ := time.Parse("2006-01-02", "2025-09-14")

	for date := startDate; !date.After(endDate); date = date.AddDate(0, 0, 1) {
		// Skip Sundays
		if date.Weekday() == time.Sunday {
			continue
		}

		// Morning shift employees (8:00 - 16:00)
		morningShift := []string{"EMP001", "EMP003", "EMP005"} // Manager, Cashier1, Stock1
		for _, empCode := range morningShift {
			empID := employeeMap[empCode]
			checkIn := time.Date(date.Year(), date.Month(), date.Day(), 8, 0, 0, 0, time.Local)
			checkOut := time.Date(date.Year(), date.Month(), date.Day(), 16, 0, 0, 0, time.Local)
			workHours = append(workHours, models.EmployeeWorkHour{
				EmployeeID:   empID,
				WorkDate:     date,
				CheckInTime:  &checkIn,
				CheckOutTime: &checkOut,
				TotalHours:   8.0,
			})
		}

		// Afternoon shift employees (14:00 - 22:00)
		afternoonShift := []string{"EMP002", "EMP004", "EMP006"} // Supervisor, Sales1, Cashier2
		for _, empCode := range afternoonShift {
			empID := employeeMap[empCode]
			checkIn := time.Date(date.Year(), date.Month(), date.Day(), 14, 0, 0, 0, time.Local)
			checkOut := time.Date(date.Year(), date.Month(), date.Day(), 22, 0, 0, 0, time.Local)
			workHours = append(workHours, models.EmployeeWorkHour{
				EmployeeID:   empID,
				WorkDate:     date,
				CheckInTime:  &checkIn,
				CheckOutTime: &checkOut,
				TotalHours:   8.0,
			})
		}
	}

	if err := tx.Create(&workHours).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d employee work hour records", len(workHours))
	return nil
}

func seedPurchaseOrders(tx *gorm.DB, employeeMap map[string]uint, supplierMap map[string]uint, productMap map[string]uint) error {
	// Create purchase orders from August 2025 to replenish stock
	orderDate1, _ := time.Parse("2006-01-02", "2025-08-10")
	orderDate2, _ := time.Parse("2006-01-02", "2025-08-20")
	orderDate3, _ := time.Parse("2006-01-02", "2025-09-01")

	orders := []models.PurchaseOrder{
		{
			OrderNo:      "PO-2025-08-001",
			SupplierID:   supplierMap["SUP003"], // Office supplies
			EmployeeID:   employeeMap["EMP005"], // Stock manager
			OrderDate:    orderDate1,
			DeliveryDate: timePtr(orderDate1.AddDate(0, 0, 3)),
			TotalAmount:  2500000,
			Status:       models.OrderReceived,
			Notes:        strPtr("Đơn nhập văn phòng phẩm tháng 8"),
		},
		{
			OrderNo:      "PO-2025-08-002",
			SupplierID:   supplierMap["SUP001"], // Food supplier
			EmployeeID:   employeeMap["EMP005"], // Stock manager
			OrderDate:    orderDate2,
			DeliveryDate: timePtr(orderDate2.AddDate(0, 0, 2)),
			TotalAmount:  5800000,
			Status:       models.OrderReceived,
			Notes:        strPtr("Đơn nhập thực phẩm định kỳ"),
		},
		{
			OrderNo:      "PO-2025-09-001",
			SupplierID:   supplierMap["SUP005"], // Beverage supplier
			EmployeeID:   employeeMap["EMP005"], // Stock manager
			OrderDate:    orderDate3,
			DeliveryDate: timePtr(orderDate3.AddDate(0, 0, 2)),
			TotalAmount:  3600000,
			Status:       models.OrderReceived,
			Notes:        strPtr("Đơn nhập đồ uống tháng 9"),
		},
	}

	if err := tx.Create(&orders).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d purchase orders", len(orders))

	// Get the order IDs for the details
	orderIDs := make([]uint, len(orders))
	for i, order := range orders {
		orderIDs[i] = order.OrderID
	}

	// Seed purchase order details
	details := []models.PurchaseOrderDetail{
		// Order 1 - Office supplies
		{OrderID: orderIDs[0], ProductID: productMap["VPP001"], Quantity: 200, UnitPrice: 3000, Subtotal: 600000},
		{OrderID: orderIDs[0], ProductID: productMap["VPP002"], Quantity: 150, UnitPrice: 8000, Subtotal: 1200000},
		{OrderID: orderIDs[0], ProductID: productMap["VPP003"], Quantity: 300, UnitPrice: 2000, Subtotal: 600000},

		// Order 2 - Food
		{OrderID: orderIDs[1], ProductID: productMap["TP001"], Quantity: 30, UnitPrice: 120000, Subtotal: 3600000},
		{OrderID: orderIDs[1], ProductID: productMap["TP002"], Quantity: 20, UnitPrice: 85000, Subtotal: 1700000},
		{OrderID: orderIDs[1], ProductID: productMap["TP003"], Quantity: 15, UnitPrice: 35000, Subtotal: 525000},

		// Order 3 - Beverages
		{OrderID: orderIDs[2], ProductID: productMap["DU001"], Quantity: 20, UnitPrice: 80000, Subtotal: 1600000},
		{OrderID: orderIDs[2], ProductID: productMap["DU002"], Quantity: 10, UnitPrice: 140000, Subtotal: 1400000},
		{OrderID: orderIDs[2], ProductID: productMap["DU003"], Quantity: 10, UnitPrice: 180000, Subtotal: 1800000},
	}

	if err := tx.Create(&details).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d purchase order details", len(details))
	return nil
}

func seedStockTransfers(tx *gorm.DB, warehouseMap map[string]uint, shelfMap map[string]uint, productMap map[string]uint, employeeMap map[string]uint) error {
	// Transfer stock from warehouse to shelves after receiving
	transferDate1, _ := time.Parse("2006-01-02 15:04:05", "2025-08-13 10:00:00")
	transferDate2, _ := time.Parse("2006-01-02 15:04:05", "2025-08-22 14:00:00")
	transferDate3, _ := time.Parse("2006-01-02 15:04:05", "2025-09-03 09:00:00")

	transfers := []models.StockTransfer{
		// Transfer office supplies to shelf
		{TransferCode: "ST-2025-08-001", ProductID: productMap["VPP001"], FromWarehouseID: warehouseMap["WH001"], ToShelfID: shelfMap["SH001"], Quantity: 50, TransferDate: transferDate1, EmployeeID: employeeMap["EMP005"], BatchCode: strPtr("VPP001-2024-01"), Notes: strPtr("Chuyển hàng ra quầy văn phòng phẩm")},
		{TransferCode: "ST-2025-08-002", ProductID: productMap["VPP002"], FromWarehouseID: warehouseMap["WH001"], ToShelfID: shelfMap["SH001"], Quantity: 40, TransferDate: transferDate1, EmployeeID: employeeMap["EMP005"], BatchCode: strPtr("VPP002-2024-01")},
		{TransferCode: "ST-2025-08-003", ProductID: productMap["VPP003"], FromWarehouseID: warehouseMap["WH001"], ToShelfID: shelfMap["SH001"], Quantity: 60, TransferDate: transferDate1, EmployeeID: employeeMap["EMP005"], BatchCode: strPtr("VPP003-2024-01")},

		// Transfer food to shelf
		{TransferCode: "ST-2025-08-004", ProductID: productMap["TP001"], FromWarehouseID: warehouseMap["WH001"], ToShelfID: shelfMap["SH004"], Quantity: 25, TransferDate: transferDate2, EmployeeID: employeeMap["EMP005"], BatchCode: strPtr("TP001-2024-01"), Notes: strPtr("Chuyển thực phẩm ra quầy")},
		{TransferCode: "ST-2025-08-005", ProductID: productMap["TP002"], FromWarehouseID: warehouseMap["WH001"], ToShelfID: shelfMap["SH004"], Quantity: 50, TransferDate: transferDate2, EmployeeID: employeeMap["EMP005"], BatchCode: strPtr("TP002-2024-01")},
		{TransferCode: "ST-2025-08-006", ProductID: productMap["TP003"], FromWarehouseID: warehouseMap["WH001"], ToShelfID: shelfMap["SH004"], Quantity: 40, TransferDate: transferDate2, EmployeeID: employeeMap["EMP005"], BatchCode: strPtr("TP003-2024-01")},

		// Transfer beverages to shelf
		{TransferCode: "ST-2025-09-001", ProductID: productMap["DU001"], FromWarehouseID: warehouseMap["WH001"], ToShelfID: shelfMap["SH005"], Quantity: 30, TransferDate: transferDate3, EmployeeID: employeeMap["EMP005"], BatchCode: strPtr("DU001-2024-01"), Notes: strPtr("Chuyển đồ uống ra quầy")},
		{TransferCode: "ST-2025-09-002", ProductID: productMap["DU002"], FromWarehouseID: warehouseMap["WH001"], ToShelfID: shelfMap["SH005"], Quantity: 25, TransferDate: transferDate3, EmployeeID: employeeMap["EMP005"], BatchCode: strPtr("DU002-2024-01")},
		{TransferCode: "ST-2025-09-003", ProductID: productMap["DU003"], FromWarehouseID: warehouseMap["WH001"], ToShelfID: shelfMap["SH005"], Quantity: 28, TransferDate: transferDate3, EmployeeID: employeeMap["EMP005"], BatchCode: strPtr("DU003-2024-01")},
	}

	if err := tx.Create(&transfers).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d stock transfers", len(transfers))
	return nil
}

func seedSalesInvoices(tx *gorm.DB, customerMap map[string]uint, employeeMap map[string]uint, productMap map[string]uint) error {
	// Create sales from September 1-14, 2025
	invoices := []models.SalesInvoice{
		// September 2
		{
			InvoiceNo:      "INV-2025-09-001",
			CustomerID:     uintPtr(customerMap["CUST001"]), // Customer 1
			EmployeeID:     employeeMap["EMP003"],           // Cashier
			InvoiceDate:    time.Date(2025, 9, 2, 10, 30, 0, 0, time.Local),
			Subtotal:       47000,
			DiscountAmount: 0,
			TaxAmount:      4700,
			TotalAmount:    51700,
			PaymentMethod:  paymentMethodPtr(models.PaymentCash),
			PointsEarned:   47,
			PointsUsed:     0,
		},
		// September 5
		{
			InvoiceNo:      "INV-2025-09-002",
			CustomerID:     uintPtr(customerMap["CUST002"]), // Customer 2
			EmployeeID:     employeeMap["EMP006"],           // Cashier 2
			InvoiceDate:    time.Date(2025, 9, 5, 14, 15, 0, 0, time.Local),
			Subtotal:       385000,
			DiscountAmount: 11550, // 3% member discount
			TaxAmount:      37345,
			TotalAmount:    410795,
			PaymentMethod:  paymentMethodPtr(models.PaymentCard),
			PointsEarned:   462, // 1.2x multiplier
			PointsUsed:     100,
		},
		// September 8
		{
			InvoiceNo:      "INV-2025-09-003",
			CustomerID:     uintPtr(customerMap["CUST003"]), // Customer 3
			EmployeeID:     employeeMap["EMP003"],
			InvoiceDate:    time.Date(2025, 9, 8, 11, 45, 0, 0, time.Local),
			Subtotal:       850000,
			DiscountAmount: 42500, // 5% gold discount
			TaxAmount:      80750,
			TotalAmount:    888250,
			PaymentMethod:  paymentMethodPtr(models.PaymentCard),
			PointsEarned:   1275, // 1.5x multiplier
			PointsUsed:     500,
		},
		// September 10 - Walk-in customer (no membership)
		{
			InvoiceNo:      "INV-2025-09-004",
			CustomerID:     nil, // No member
			EmployeeID:     employeeMap["EMP006"],
			InvoiceDate:    time.Date(2025, 9, 10, 16, 20, 0, 0, time.Local),
			Subtotal:       120000,
			DiscountAmount: 0,
			TaxAmount:      12000,
			TotalAmount:    132000,
			PaymentMethod:  paymentMethodPtr(models.PaymentCash),
			PointsEarned:   0,
			PointsUsed:     0,
		},
		// September 12
		{
			InvoiceNo:      "INV-2025-09-005",
			CustomerID:     uintPtr(customerMap["CUST004"]), // Customer 4
			EmployeeID:     employeeMap["EMP003"],
			InvoiceDate:    time.Date(2025, 9, 12, 9, 30, 0, 0, time.Local),
			Subtotal:       235000,
			DiscountAmount: 0,
			TaxAmount:      23500,
			TotalAmount:    258500,
			PaymentMethod:  paymentMethodPtr(models.PaymentCard),
			PointsEarned:   235,
			PointsUsed:     0,
		},
		// September 14 (today)
		{
			InvoiceNo:      "INV-2025-09-006",
			CustomerID:     uintPtr(customerMap["CUST005"]), // Customer 5
			EmployeeID:     employeeMap["EMP006"],
			InvoiceDate:    time.Date(2025, 9, 14, 10, 00, 0, 0, time.Local),
			Subtotal:       550000,
			DiscountAmount: 44000, // 8% platinum discount
			TaxAmount:      50600,
			TotalAmount:    556600,
			PaymentMethod:  paymentMethodPtr(models.PaymentCard),
			PointsEarned:   1100, // 2x multiplier
			PointsUsed:     1000,
		},
	}

	if err := tx.Create(&invoices).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d sales invoices", len(invoices))

	// Get the invoice IDs that were just created
	var createdInvoices []models.SalesInvoice
	tx.Order("invoice_id").Find(&createdInvoices)

	// Seed sales invoice details
	details := []models.SalesInvoiceDetail{
		// Invoice 1 - Small purchase
		{InvoiceID: createdInvoices[0].InvoiceID, ProductID: productMap["VPP001"], Quantity: 2, UnitPrice: 5000, DiscountPercentage: 0, DiscountAmount: 0, Subtotal: 10000},
		{InvoiceID: createdInvoices[0].InvoiceID, ProductID: productMap["VPP002"], Quantity: 3, UnitPrice: 12000, DiscountPercentage: 0, DiscountAmount: 0, Subtotal: 36000},

		// Invoice 2 - Medium purchase
		{InvoiceID: createdInvoices[1].InvoiceID, ProductID: productMap["TP001"], Quantity: 2, UnitPrice: 180000, DiscountPercentage: 0, DiscountAmount: 0, Subtotal: 360000},
		{InvoiceID: createdInvoices[1].InvoiceID, ProductID: productMap["VPP003"], Quantity: 5, UnitPrice: 3500, DiscountPercentage: 0, DiscountAmount: 0, Subtotal: 17500},

		// Invoice 3 - Large purchase
		{InvoiceID: createdInvoices[2].InvoiceID, ProductID: productMap["DT001"], Quantity: 2, UnitPrice: 350000, DiscountPercentage: 0, DiscountAmount: 0, Subtotal: 700000},
		{InvoiceID: createdInvoices[2].InvoiceID, ProductID: productMap["DT002"], Quantity: 1, UnitPrice: 300000, DiscountPercentage: 0, DiscountAmount: 0, Subtotal: 300000},

		// Invoice 4 - Walk-in customer
		{InvoiceID: createdInvoices[3].InvoiceID, ProductID: productMap["DU001"], Quantity: 1, UnitPrice: 120000, DiscountPercentage: 0, DiscountAmount: 0, Subtotal: 120000},

		// Invoice 5
		{InvoiceID: createdInvoices[4].InvoiceID, ProductID: productMap["TP002"], Quantity: 2, UnitPrice: 115000, DiscountPercentage: 0, DiscountAmount: 0, Subtotal: 230000},
		{InvoiceID: createdInvoices[4].InvoiceID, ProductID: productMap["VPP001"], Quantity: 1, UnitPrice: 5000, DiscountPercentage: 0, DiscountAmount: 0, Subtotal: 5000},

		// Invoice 6 - Today's sale
		{InvoiceID: createdInvoices[5].InvoiceID, ProductID: productMap["GD001"], Quantity: 1, UnitPrice: 250000, DiscountPercentage: 0, DiscountAmount: 0, Subtotal: 250000},
		{InvoiceID: createdInvoices[5].InvoiceID, ProductID: productMap["DU002"], Quantity: 1, UnitPrice: 200000, DiscountPercentage: 0, DiscountAmount: 0, Subtotal: 200000},
		{InvoiceID: createdInvoices[5].InvoiceID, ProductID: productMap["DU003"], Quantity: 1, UnitPrice: 260000, DiscountPercentage: 0, DiscountAmount: 0, Subtotal: 260000},
	}

	if err := tx.Create(&details).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d sales invoice details", len(details))
	return nil
}

// Helper functions
func strPtr(s string) *string {
	return &s
}

func intPtr(i int) *int {
	return &i
}

func uintPtr(u uint) *uint {
	return &u
}

func floatPtr(f float64) *float64 {
	return &f
}

func timePtr(t time.Time) *time.Time {
	return &t
}

func paymentMethodPtr(pm models.PaymentMethod) *models.PaymentMethod {
	return &pm
}
