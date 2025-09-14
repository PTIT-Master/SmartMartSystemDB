package database

import (
	"fmt"
	"log"
	"strings"
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

		// 14. Seed Purchase Orders (this will also create warehouse inventory)
		if err := seedPurchaseOrders(tx, employeeMap, supplierMap, productMap, warehouseMap); err != nil {
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
		{CategoryName: "Thực phẩm - Đồ khô", Description: strPtr("Thực phẩm khô có hạn sử dụng dài")},
		{CategoryName: "Thực phẩm - Rau quả", Description: strPtr("Rau củ quả tươi sống có hạn ngắn")},
		{CategoryName: "Thực phẩm - Thịt cá", Description: strPtr("Thịt, cá và hải sản")},
		{CategoryName: "Thực phẩm - Sữa trứng", Description: strPtr("Sữa, trứng và các sản phẩm từ sữa")},
		{CategoryName: "Đồ uống - Có cồn", Description: strPtr("Bia, rượu và đồ uống có cồn")},
		{CategoryName: "Đồ uống - Không cồn", Description: strPtr("Nước ngọt, nước suối và đồ uống không cồn")},
		{CategoryName: "Đồ uống - Nóng", Description: strPtr("Cà phê, trà và đồ uống nóng")},
		{CategoryName: "Mỹ phẩm - Chăm sóc da", Description: strPtr("Kem dưỡng da, sữa rửa mặt")},
		{CategoryName: "Mỹ phẩm - Trang điểm", Description: strPtr("Son, phấn và đồ trang điểm")},
		{CategoryName: "Mỹ phẩm - Vệ sinh cá nhân", Description: strPtr("Dầu gội, kem đánh răng, xà phòng")},
		{CategoryName: "Thời trang - Nam", Description: strPtr("Quần áo nam và phụ kiện")},
		{CategoryName: "Thời trang - Nữ", Description: strPtr("Quần áo nữ và phụ kiện")},
		{CategoryName: "Thời trang - Unisex", Description: strPtr("Đồ dùng chung cho nam nữ")},
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
		// Văn phòng phẩm (15 sản phẩm) - SUP003
		{ProductCode: "VPP001", ProductName: "Bút bi Thiên Long", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Cây", ImportPrice: 3000, SellingPrice: 5000, ShelfLifeDays: intPtr(365), LowStockThreshold: 20},
		{ProductCode: "VPP002", ProductName: "Vở học sinh 96 trang", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Quyển", ImportPrice: 8000, SellingPrice: 12000, ShelfLifeDays: intPtr(365), LowStockThreshold: 30},
		{ProductCode: "VPP003", ProductName: "Bút chì 2B", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Cây", ImportPrice: 2000, SellingPrice: 3500, ShelfLifeDays: intPtr(365), LowStockThreshold: 25},
		{ProductCode: "VPP004", ProductName: "Thước kẻ nhựa 30cm", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Cái", ImportPrice: 5000, SellingPrice: 8000, ShelfLifeDays: intPtr(365), LowStockThreshold: 15},
		{ProductCode: "VPP005", ProductName: "Gôm tẩy Hồng Hà", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Cái", ImportPrice: 1500, SellingPrice: 3000, ShelfLifeDays: intPtr(365), LowStockThreshold: 30},
		{ProductCode: "VPP006", ProductName: "Bút máy học sinh", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Cây", ImportPrice: 15000, SellingPrice: 25000, ShelfLifeDays: intPtr(365), LowStockThreshold: 10},
		{ProductCode: "VPP007", ProductName: "Giấy A4 Double A", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Ream", ImportPrice: 45000, SellingPrice: 65000, ShelfLifeDays: intPtr(365), LowStockThreshold: 20},
		{ProductCode: "VPP008", ProductName: "Keo dán UHU", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Tuýp", ImportPrice: 8000, SellingPrice: 12000, ShelfLifeDays: intPtr(730), LowStockThreshold: 25},
		{ProductCode: "VPP009", ProductName: "Bìa hồ sơ", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Cái", ImportPrice: 3000, SellingPrice: 5000, ShelfLifeDays: intPtr(365), LowStockThreshold: 20},
		{ProductCode: "VPP010", ProductName: "Kẹp giấy", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Hộp", ImportPrice: 12000, SellingPrice: 18000, ShelfLifeDays: intPtr(365), LowStockThreshold: 15},
		{ProductCode: "VPP011", ProductName: "Bút dạ quang", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Cây", ImportPrice: 8000, SellingPrice: 12000, ShelfLifeDays: intPtr(365), LowStockThreshold: 20},
		{ProductCode: "VPP012", ProductName: "Stapler kim bấm", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Cái", ImportPrice: 35000, SellingPrice: 55000, ShelfLifeDays: intPtr(365), LowStockThreshold: 8},
		{ProductCode: "VPP013", ProductName: "Kim bấm số 10", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Hộp", ImportPrice: 5000, SellingPrice: 8000, ShelfLifeDays: intPtr(365), LowStockThreshold: 25},
		{ProductCode: "VPP014", ProductName: "Bảng viết bút lông", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Cái", ImportPrice: 150000, SellingPrice: 250000, ShelfLifeDays: intPtr(365), LowStockThreshold: 5},
		{ProductCode: "VPP015", ProductName: "Máy tính Casio FX-580", CategoryID: categoryMap["Văn phòng phẩm"], SupplierID: supplierMap["SUP003"], Unit: "Cái", ImportPrice: 280000, SellingPrice: 450000, ShelfLifeDays: intPtr(365), LowStockThreshold: 10},

		// Đồ gia dụng (15 sản phẩm) - SUP004
		{ProductCode: "GD001", ProductName: "Chảo chống dính 26cm", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 150000, SellingPrice: 250000, LowStockThreshold: 5},
		{ProductCode: "GD002", ProductName: "Bộ nồi inox 3 món", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Bộ", ImportPrice: 350000, SellingPrice: 550000, LowStockThreshold: 3},
		{ProductCode: "GD003", ProductName: "Khăn tắm cotton", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 45000, SellingPrice: 75000, LowStockThreshold: 10},
		{ProductCode: "GD004", ProductName: "Bộ dao inox 6 món", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Bộ", ImportPrice: 120000, SellingPrice: 200000, LowStockThreshold: 8},
		{ProductCode: "GD005", ProductName: "Thớt gỗ cao su", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 35000, SellingPrice: 60000, LowStockThreshold: 15},
		{ProductCode: "GD006", ProductName: "Bộ chén đĩa sứ", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Bộ", ImportPrice: 180000, SellingPrice: 300000, LowStockThreshold: 6},
		{ProductCode: "GD007", ProductName: "Gương soi trang điểm", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 80000, SellingPrice: 130000, LowStockThreshold: 12},
		{ProductCode: "GD008", ProductName: "Thùng rác có nắp", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 65000, SellingPrice: 110000, LowStockThreshold: 10},
		{ProductCode: "GD009", ProductName: "Dây phơi quần áo", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 25000, SellingPrice: 45000, LowStockThreshold: 20},
		{ProductCode: "GD010", ProductName: "Bộ ly thủy tinh", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Bộ", ImportPrice: 90000, SellingPrice: 150000, LowStockThreshold: 10},
		{ProductCode: "GD011", ProductName: "Giá để giày dép", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 120000, SellingPrice: 200000, LowStockThreshold: 8},
		{ProductCode: "GD012", ProductName: "Rổ đựng đồ đa năng", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 55000, SellingPrice: 90000, LowStockThreshold: 15},
		{ProductCode: "GD013", ProductName: "Kệ gia vị 3 tầng", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 85000, SellingPrice: 140000, LowStockThreshold: 8},
		{ProductCode: "GD014", ProductName: "Bàn ủi hơi nước", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 300000, SellingPrice: 480000, LowStockThreshold: 5},
		{ProductCode: "GD015", ProductName: "Tủ nhựa 5 ngăn", CategoryID: categoryMap["Đồ gia dụng"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 450000, SellingPrice: 750000, LowStockThreshold: 3},

		// Đồ điện tử (15 sản phẩm) - SUP002
		{ProductCode: "DT001", ProductName: "Tai nghe Bluetooth", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 200000, SellingPrice: 350000, LowStockThreshold: 10},
		{ProductCode: "DT002", ProductName: "Sạc dự phòng 10000mAh", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 180000, SellingPrice: 300000, LowStockThreshold: 8},
		{ProductCode: "DT003", ProductName: "Cáp USB Type-C", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 25000, SellingPrice: 50000, LowStockThreshold: 15},
		{ProductCode: "DT004", ProductName: "Loa Bluetooth mini", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 150000, SellingPrice: 250000, LowStockThreshold: 12},
		{ProductCode: "DT005", ProductName: "Chuột không dây", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 80000, SellingPrice: 130000, LowStockThreshold: 20},
		{ProductCode: "DT006", ProductName: "Bàn phím gaming", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 350000, SellingPrice: 580000, LowStockThreshold: 8},
		{ProductCode: "DT007", ProductName: "Webcam HD 720p", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 120000, SellingPrice: 200000, LowStockThreshold: 15},
		{ProductCode: "DT008", ProductName: "Đèn LED USB", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 35000, SellingPrice: 60000, LowStockThreshold: 25},
		{ProductCode: "DT009", ProductName: "Hub USB 4 cổng", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 65000, SellingPrice: 110000, LowStockThreshold: 18},
		{ProductCode: "DT010", ProductName: "Thẻ nhớ MicroSD 32GB", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 90000, SellingPrice: 150000, LowStockThreshold: 20},
		{ProductCode: "DT011", ProductName: "Giá đỡ điện thoại", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 45000, SellingPrice: 75000, LowStockThreshold: 22},
		{ProductCode: "DT012", ProductName: "Ốp lưng iPhone", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 30000, SellingPrice: 55000, LowStockThreshold: 30},
		{ProductCode: "DT013", ProductName: "Miếng dán màn hình", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 15000, SellingPrice: 30000, LowStockThreshold: 40},
		{ProductCode: "DT014", ProductName: "Pin AA Panasonic", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Vỉ", ImportPrice: 12000, SellingPrice: 20000, LowStockThreshold: 35},
		{ProductCode: "DT015", ProductName: "Đồng hồ thông minh", CategoryID: categoryMap["Đồ điện tử"], SupplierID: supplierMap["SUP002"], Unit: "Cái", ImportPrice: 800000, SellingPrice: 1300000, LowStockThreshold: 5},

		// Đồ bếp (10 sản phẩm) - SUP004
		{ProductCode: "DB001", ProductName: "Nồi cơm điện 1.8L", CategoryID: categoryMap["Đồ bếp"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 380000, SellingPrice: 650000, LowStockThreshold: 5},
		{ProductCode: "DB002", ProductName: "Máy xay sinh tố", CategoryID: categoryMap["Đồ bếp"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 250000, SellingPrice: 420000, LowStockThreshold: 8},
		{ProductCode: "DB003", ProductName: "Ấm đun nước siêu tốc", CategoryID: categoryMap["Đồ bếp"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 180000, SellingPrice: 300000, LowStockThreshold: 10},
		{ProductCode: "DB004", ProductName: "Bếp gas hồng ngoại", CategoryID: categoryMap["Đồ bếp"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 450000, SellingPrice: 750000, LowStockThreshold: 6},
		{ProductCode: "DB005", ProductName: "Lò vi sóng 20L", CategoryID: categoryMap["Đồ bếp"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 1200000, SellingPrice: 1950000, LowStockThreshold: 3},
		{ProductCode: "DB006", ProductName: "Máy pha cà phê", CategoryID: categoryMap["Đồ bếp"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 650000, SellingPrice: 1100000, LowStockThreshold: 4},
		{ProductCode: "DB007", ProductName: "Nồi áp suất 5L", CategoryID: categoryMap["Đồ bếp"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 320000, SellingPrice: 520000, LowStockThreshold: 6},
		{ProductCode: "DB008", ProductName: "Máy nướng bánh mì", CategoryID: categoryMap["Đồ bếp"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 280000, SellingPrice: 450000, LowStockThreshold: 8},
		{ProductCode: "DB009", ProductName: "Bộ dao thớt inox", CategoryID: categoryMap["Đồ bếp"], SupplierID: supplierMap["SUP004"], Unit: "Bộ", ImportPrice: 95000, SellingPrice: 160000, LowStockThreshold: 12},
		{ProductCode: "DB010", ProductName: "Máy đánh trứng cầm tay", CategoryID: categoryMap["Đồ bếp"], SupplierID: supplierMap["SUP004"], Unit: "Cái", ImportPrice: 85000, SellingPrice: 140000, LowStockThreshold: 10},

		// Thực phẩm - Đồ khô (8 sản phẩm) - SUP001
		{ProductCode: "TP001", ProductName: "Gạo ST25 5kg", CategoryID: categoryMap["Thực phẩm - Đồ khô"], SupplierID: supplierMap["SUP001"], Unit: "Bao", ImportPrice: 120000, SellingPrice: 180000, ShelfLifeDays: intPtr(180), LowStockThreshold: 10},
		{ProductCode: "TP002", ProductName: "Mì gói Hảo Hảo", CategoryID: categoryMap["Thực phẩm - Đồ khô"], SupplierID: supplierMap["SUP001"], Unit: "Thùng", ImportPrice: 85000, SellingPrice: 115000, ShelfLifeDays: intPtr(180), LowStockThreshold: 20},
		{ProductCode: "TP003", ProductName: "Dầu ăn Tường An 1L", CategoryID: categoryMap["Thực phẩm - Đồ khô"], SupplierID: supplierMap["SUP001"], Unit: "Chai", ImportPrice: 35000, SellingPrice: 52000, ShelfLifeDays: intPtr(365), LowStockThreshold: 15},
		{ProductCode: "TP004", ProductName: "Muối I-ốt 500g", CategoryID: categoryMap["Thực phẩm - Đồ khô"], SupplierID: supplierMap["SUP001"], Unit: "Gói", ImportPrice: 8000, SellingPrice: 12000, ShelfLifeDays: intPtr(730), LowStockThreshold: 25},
		{ProductCode: "TP005", ProductName: "Đường cát trắng 1kg", CategoryID: categoryMap["Thực phẩm - Đồ khô"], SupplierID: supplierMap["SUP001"], Unit: "Gói", ImportPrice: 18000, SellingPrice: 25000, ShelfLifeDays: intPtr(365), LowStockThreshold: 20},
		{ProductCode: "TP006", ProductName: "Nước mắm Phú Quốc", CategoryID: categoryMap["Thực phẩm - Đồ khô"], SupplierID: supplierMap["SUP001"], Unit: "Chai", ImportPrice: 45000, SellingPrice: 70000, ShelfLifeDays: intPtr(730), LowStockThreshold: 15},
		{ProductCode: "TP007", ProductName: "Bột mì đa dụng 1kg", CategoryID: categoryMap["Thực phẩm - Đồ khô"], SupplierID: supplierMap["SUP001"], Unit: "Gói", ImportPrice: 22000, SellingPrice: 35000, ShelfLifeDays: intPtr(365), LowStockThreshold: 18},
		{ProductCode: "TP008", ProductName: "Bánh quy Oreo", CategoryID: categoryMap["Thực phẩm - Đồ khô"], SupplierID: supplierMap["SUP001"], Unit: "Gói", ImportPrice: 15000, SellingPrice: 25000, ShelfLifeDays: intPtr(120), LowStockThreshold: 25},

		// Thực phẩm - Rau quả (5 sản phẩm) - SUP001
		{ProductCode: "TP009", ProductName: "Cà rốt 1kg", CategoryID: categoryMap["Thực phẩm - Rau quả"], SupplierID: supplierMap["SUP001"], Unit: "Kg", ImportPrice: 15000, SellingPrice: 25000, ShelfLifeDays: intPtr(7), LowStockThreshold: 20},
		{ProductCode: "TP010", ProductName: "Khoai tây 1kg", CategoryID: categoryMap["Thực phẩm - Rau quả"], SupplierID: supplierMap["SUP001"], Unit: "Kg", ImportPrice: 18000, SellingPrice: 28000, ShelfLifeDays: intPtr(10), LowStockThreshold: 15},
		{ProductCode: "TP011", ProductName: "Bắp cải 1kg", CategoryID: categoryMap["Thực phẩm - Rau quả"], SupplierID: supplierMap["SUP001"], Unit: "Kg", ImportPrice: 12000, SellingPrice: 20000, ShelfLifeDays: intPtr(5), LowStockThreshold: 25},
		{ProductCode: "TP012", ProductName: "Táo Fuji 1kg", CategoryID: categoryMap["Thực phẩm - Rau quả"], SupplierID: supplierMap["SUP001"], Unit: "Kg", ImportPrice: 35000, SellingPrice: 55000, ShelfLifeDays: intPtr(14), LowStockThreshold: 12},
		{ProductCode: "TP013", ProductName: "Chuối tiêu 1kg", CategoryID: categoryMap["Thực phẩm - Rau quả"], SupplierID: supplierMap["SUP001"], Unit: "Kg", ImportPrice: 25000, SellingPrice: 40000, ShelfLifeDays: intPtr(3), LowStockThreshold: 18},

		// Thực phẩm - Thịt cá (4 sản phẩm) - SUP001
		{ProductCode: "TP014", ProductName: "Thịt heo ba chỉ 500g", CategoryID: categoryMap["Thực phẩm - Thịt cá"], SupplierID: supplierMap["SUP001"], Unit: "Gói", ImportPrice: 65000, SellingPrice: 95000, ShelfLifeDays: intPtr(5), LowStockThreshold: 15},
		{ProductCode: "TP015", ProductName: "Cá thu đông lạnh", CategoryID: categoryMap["Thực phẩm - Thịt cá"], SupplierID: supplierMap["SUP001"], Unit: "Con", ImportPrice: 85000, SellingPrice: 120000, ShelfLifeDays: intPtr(90), LowStockThreshold: 12},
		{ProductCode: "TP016", ProductName: "Tôm đông lạnh 500g", CategoryID: categoryMap["Thực phẩm - Thịt cá"], SupplierID: supplierMap["SUP001"], Unit: "Gói", ImportPrice: 120000, SellingPrice: 180000, ShelfLifeDays: intPtr(90), LowStockThreshold: 10},
		{ProductCode: "TP017", ProductName: "Xúc xích Đức Việt", CategoryID: categoryMap["Thực phẩm - Thịt cá"], SupplierID: supplierMap["SUP001"], Unit: "Gói", ImportPrice: 55000, SellingPrice: 85000, ShelfLifeDays: intPtr(60), LowStockThreshold: 20},

		// Thực phẩm - Sữa trứng (3 sản phẩm) - SUP001
		{ProductCode: "TP018", ProductName: "Trứng gà hộp 10 quả", CategoryID: categoryMap["Thực phẩm - Sữa trứng"], SupplierID: supplierMap["SUP001"], Unit: "Hộp", ImportPrice: 30000, SellingPrice: 45000, ShelfLifeDays: intPtr(30), LowStockThreshold: 30},
		{ProductCode: "TP019", ProductName: "Sữa tươi Vinamilk 1L", CategoryID: categoryMap["Thực phẩm - Sữa trứng"], SupplierID: supplierMap["SUP001"], Unit: "Hộp", ImportPrice: 28000, SellingPrice: 42000, ShelfLifeDays: intPtr(7), LowStockThreshold: 30},
		{ProductCode: "TP020", ProductName: "Phô mai lát Laughing Cow", CategoryID: categoryMap["Thực phẩm - Sữa trứng"], SupplierID: supplierMap["SUP001"], Unit: "Hộp", ImportPrice: 35000, SellingPrice: 55000, ShelfLifeDays: intPtr(60), LowStockThreshold: 18},

		// Đồ uống - Có cồn (3 sản phẩm) - SUP005
		{ProductCode: "DU001", ProductName: "Bia Saigon lon 330ml", CategoryID: categoryMap["Đồ uống - Có cồn"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 220000, SellingPrice: 320000, ShelfLifeDays: intPtr(365), LowStockThreshold: 10},
		{ProductCode: "DU002", ProductName: "Bia Heineken lon 330ml", CategoryID: categoryMap["Đồ uống - Có cồn"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 280000, SellingPrice: 420000, ShelfLifeDays: intPtr(365), LowStockThreshold: 8},
		{ProductCode: "DU003", ProductName: "Rượu vang Đà Lạt", CategoryID: categoryMap["Đồ uống - Có cồn"], SupplierID: supplierMap["SUP005"], Unit: "Chai", ImportPrice: 120000, SellingPrice: 180000, ShelfLifeDays: intPtr(730), LowStockThreshold: 15},

		// Đồ uống - Không cồn (8 sản phẩm) - SUP005
		{ProductCode: "DU004", ProductName: "Nước suối Aquafina 500ml", CategoryID: categoryMap["Đồ uống - Không cồn"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 80000, SellingPrice: 120000, ShelfLifeDays: intPtr(365), LowStockThreshold: 15},
		{ProductCode: "DU005", ProductName: "Coca Cola 330ml", CategoryID: categoryMap["Đồ uống - Không cồn"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 180000, SellingPrice: 260000, ShelfLifeDays: intPtr(365), LowStockThreshold: 12},
		{ProductCode: "DU006", ProductName: "Pepsi lon 330ml", CategoryID: categoryMap["Đồ uống - Không cồn"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 175000, SellingPrice: 250000, ShelfLifeDays: intPtr(365), LowStockThreshold: 12},
		{ProductCode: "DU007", ProductName: "Nước cam Tropicana", CategoryID: categoryMap["Đồ uống - Không cồn"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 200000, SellingPrice: 290000, ShelfLifeDays: intPtr(180), LowStockThreshold: 8},
		{ProductCode: "DU008", ProductName: "Nước dừa Cocoxim", CategoryID: categoryMap["Đồ uống - Không cồn"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 180000, SellingPrice: 260000, ShelfLifeDays: intPtr(365), LowStockThreshold: 12},
		{ProductCode: "DU009", ProductName: "Nước tăng lực RedBull", CategoryID: categoryMap["Đồ uống - Không cồn"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 280000, SellingPrice: 400000, ShelfLifeDays: intPtr(365), LowStockThreshold: 8},
		{ProductCode: "DU010", ProductName: "Sữa chua uống TH", CategoryID: categoryMap["Đồ uống - Không cồn"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 120000, SellingPrice: 180000, ShelfLifeDays: intPtr(15), LowStockThreshold: 18},
		{ProductCode: "DU011", ProductName: "Nước khoáng LaVie", CategoryID: categoryMap["Đồ uống - Không cồn"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 90000, SellingPrice: 135000, ShelfLifeDays: intPtr(365), LowStockThreshold: 16},

		// Đồ uống - Nóng (4 sản phẩm) - SUP005
		{ProductCode: "DU012", ProductName: "Cà phê Nescafe Gold", CategoryID: categoryMap["Đồ uống - Nóng"], SupplierID: supplierMap["SUP005"], Unit: "Lọ", ImportPrice: 85000, SellingPrice: 130000, ShelfLifeDays: intPtr(730), LowStockThreshold: 20},
		{ProductCode: "DU013", ProductName: "Trà xanh không độ", CategoryID: categoryMap["Đồ uống - Nóng"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 140000, SellingPrice: 200000, ShelfLifeDays: intPtr(180), LowStockThreshold: 10},
		{ProductCode: "DU014", ProductName: "Trà đá Lipton chai", CategoryID: categoryMap["Đồ uống - Nóng"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 150000, SellingPrice: 220000, ShelfLifeDays: intPtr(180), LowStockThreshold: 14},
		{ProductCode: "DU015", ProductName: "Trà sữa Lipton", CategoryID: categoryMap["Đồ uống - Nóng"], SupplierID: supplierMap["SUP005"], Unit: "Thùng", ImportPrice: 160000, SellingPrice: 230000, ShelfLifeDays: intPtr(180), LowStockThreshold: 15},

		// Mỹ phẩm - Chăm sóc da (4 sản phẩm) - SUP001, SUP002
		{ProductCode: "MP001", ProductName: "Kem chống nắng Nivea", CategoryID: categoryMap["Mỹ phẩm - Chăm sóc da"], SupplierID: supplierMap["SUP001"], Unit: "Tuýp", ImportPrice: 65000, SellingPrice: 110000, ShelfLifeDays: intPtr(365), LowStockThreshold: 15},
		{ProductCode: "MP002", ProductName: "Sữa rửa mặt Cetaphil", CategoryID: categoryMap["Mỹ phẩm - Chăm sóc da"], SupplierID: supplierMap["SUP001"], Unit: "Chai", ImportPrice: 180000, SellingPrice: 280000, ShelfLifeDays: intPtr(365), LowStockThreshold: 10},
		{ProductCode: "MP003", ProductName: "Nước hoa hồng Mamonde", CategoryID: categoryMap["Mỹ phẩm - Chăm sóc da"], SupplierID: supplierMap["SUP002"], Unit: "Chai", ImportPrice: 120000, SellingPrice: 190000, ShelfLifeDays: intPtr(365), LowStockThreshold: 8},
		{ProductCode: "MP004", ProductName: "Kem dưỡng da Olay", CategoryID: categoryMap["Mỹ phẩm - Chăm sóc da"], SupplierID: supplierMap["SUP002"], Unit: "Lọ", ImportPrice: 150000, SellingPrice: 240000, ShelfLifeDays: intPtr(365), LowStockThreshold: 10},

		// Mỹ phẩm - Trang điểm (3 sản phẩm) - SUP002, SUP003
		{ProductCode: "MP005", ProductName: "Son dưỡng môi Vaseline", CategoryID: categoryMap["Mỹ phẩm - Trang điểm"], SupplierID: supplierMap["SUP002"], Unit: "Cây", ImportPrice: 35000, SellingPrice: 60000, ShelfLifeDays: intPtr(365), LowStockThreshold: 18},
		{ProductCode: "MP006", ProductName: "Mascara Maybelline", CategoryID: categoryMap["Mỹ phẩm - Trang điểm"], SupplierID: supplierMap["SUP002"], Unit: "Cây", ImportPrice: 180000, SellingPrice: 290000, ShelfLifeDays: intPtr(365), LowStockThreshold: 8},
		{ProductCode: "MP007", ProductName: "Phấn phủ L'Oreal", CategoryID: categoryMap["Mỹ phẩm - Trang điểm"], SupplierID: supplierMap["SUP003"], Unit: "Hộp", ImportPrice: 250000, SellingPrice: 400000, ShelfLifeDays: intPtr(365), LowStockThreshold: 6},

		// Mỹ phẩm - Vệ sinh cá nhân (3 sản phẩm) - SUP001, SUP003
		{ProductCode: "MP008", ProductName: "Dầu gội Head & Shoulders", CategoryID: categoryMap["Mỹ phẩm - Vệ sinh cá nhân"], SupplierID: supplierMap["SUP001"], Unit: "Chai", ImportPrice: 85000, SellingPrice: 130000, ShelfLifeDays: intPtr(365), LowStockThreshold: 12},
		{ProductCode: "MP009", ProductName: "Kem đánh răng Colgate", CategoryID: categoryMap["Mỹ phẩm - Vệ sinh cá nhân"], SupplierID: supplierMap["SUP001"], Unit: "Tuýp", ImportPrice: 25000, SellingPrice: 40000, ShelfLifeDays: intPtr(730), LowStockThreshold: 20},
		{ProductCode: "MP010", ProductName: "Xịt khử mùi Rexona", CategoryID: categoryMap["Mỹ phẩm - Vệ sinh cá nhân"], SupplierID: supplierMap["SUP003"], Unit: "Chai", ImportPrice: 55000, SellingPrice: 90000, ShelfLifeDays: intPtr(365), LowStockThreshold: 15},

		// Thời trang - Nam (2 sản phẩm) - SUP003
		{ProductCode: "TT001", ProductName: "Quần jean nam", CategoryID: categoryMap["Thời trang - Nam"], SupplierID: supplierMap["SUP003"], Unit: "Cái", ImportPrice: 200000, SellingPrice: 350000, ShelfLifeDays: intPtr(365), LowStockThreshold: 10},
		{ProductCode: "TT002", ProductName: "Áo polo nam", CategoryID: categoryMap["Thời trang - Nam"], SupplierID: supplierMap["SUP003"], Unit: "Cái", ImportPrice: 120000, SellingPrice: 200000, ShelfLifeDays: intPtr(365), LowStockThreshold: 15},

		// Thời trang - Nữ (2 sản phẩm) - SUP003
		{ProductCode: "TT003", ProductName: "Váy maxi nữ", CategoryID: categoryMap["Thời trang - Nữ"], SupplierID: supplierMap["SUP003"], Unit: "Cái", ImportPrice: 180000, SellingPrice: 320000, ShelfLifeDays: intPtr(365), LowStockThreshold: 12},
		{ProductCode: "TT004", ProductName: "Túi xách nữ", CategoryID: categoryMap["Thời trang - Nữ"], SupplierID: supplierMap["SUP003"], Unit: "Cái", ImportPrice: 120000, SellingPrice: 220000, ShelfLifeDays: intPtr(365), LowStockThreshold: 8},

		// Thời trang - Unisex (3 sản phẩm) - SUP003
		{ProductCode: "TT005", ProductName: "Áo thun cotton unisex", CategoryID: categoryMap["Thời trang - Unisex"], SupplierID: supplierMap["SUP003"], Unit: "Cái", ImportPrice: 80000, SellingPrice: 150000, ShelfLifeDays: intPtr(365), LowStockThreshold: 20},
		{ProductCode: "TT006", ProductName: "Dép tông nam nữ", CategoryID: categoryMap["Thời trang - Unisex"], SupplierID: supplierMap["SUP003"], Unit: "Đôi", ImportPrice: 45000, SellingPrice: 80000, ShelfLifeDays: intPtr(365), LowStockThreshold: 15},
		{ProductCode: "TT007", ProductName: "Đồng hồ đeo tay", CategoryID: categoryMap["Thời trang - Unisex"], SupplierID: supplierMap["SUP003"], Unit: "Cái", ImportPrice: 150000, SellingPrice: 280000, ShelfLifeDays: intPtr(365), LowStockThreshold: 12},
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
		{ShelfCode: "SH004", ShelfName: "Quầy thực phẩm khô", CategoryID: categoryMap["Thực phẩm - Đồ khô"], Location: strPtr("Khu D - Tầng 1"), MaxCapacity: intPtr(800)},
		{ShelfCode: "SH005", ShelfName: "Quầy đồ uống không cồn", CategoryID: categoryMap["Đồ uống - Không cồn"], Location: strPtr("Khu E - Tầng 1"), MaxCapacity: intPtr(600)},
		{ShelfCode: "SH006", ShelfName: "Quầy văn phòng phẩm 2", CategoryID: categoryMap["Văn phòng phẩm"], Location: strPtr("Khu A - Tầng 2"), MaxCapacity: intPtr(400)},
		{ShelfCode: "SH007", ShelfName: "Quầy rau quả tươi", CategoryID: categoryMap["Thực phẩm - Rau quả"], Location: strPtr("Khu F - Tầng 1"), MaxCapacity: intPtr(300)},
		{ShelfCode: "SH008", ShelfName: "Quầy mỹ phẩm", CategoryID: categoryMap["Mỹ phẩm - Chăm sóc da"], Location: strPtr("Khu G - Tầng 1"), MaxCapacity: intPtr(250)},
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
		// Thực phẩm - Đồ khô (hạn dưới 5 ngày giảm 50%)
		{CategoryID: categoryMap["Thực phẩm - Đồ khô"], DaysBeforeExpiry: 5, DiscountPercentage: 50, RuleName: strPtr("Thực phẩm đồ khô - giảm 50% khi hạn dưới 5 ngày")},
		{CategoryID: categoryMap["Thực phẩm - Đồ khô"], DaysBeforeExpiry: 15, DiscountPercentage: 20, RuleName: strPtr("Thực phẩm đồ khô - giảm 20% khi hạn dưới 15 ngày")},

		// Thực phẩm - Rau quả (hạn dưới 1 ngày giảm 50%)
		{CategoryID: categoryMap["Thực phẩm - Rau quả"], DaysBeforeExpiry: 1, DiscountPercentage: 50, RuleName: strPtr("Rau quả - giảm 50% khi hạn dưới 1 ngày")},
		{CategoryID: categoryMap["Thực phẩm - Rau quả"], DaysBeforeExpiry: 3, DiscountPercentage: 30, RuleName: strPtr("Rau quả - giảm 30% khi hạn dưới 3 ngày")},

		// Thực phẩm - Thịt cá
		{CategoryID: categoryMap["Thực phẩm - Thịt cá"], DaysBeforeExpiry: 2, DiscountPercentage: 40, RuleName: strPtr("Thịt cá - giảm 40% khi hạn dưới 2 ngày")},
		{CategoryID: categoryMap["Thực phẩm - Thịt cá"], DaysBeforeExpiry: 5, DiscountPercentage: 20, RuleName: strPtr("Thịt cá - giảm 20% khi hạn dưới 5 ngày")},

		// Thực phẩm - Sữa trứng
		{CategoryID: categoryMap["Thực phẩm - Sữa trứng"], DaysBeforeExpiry: 3, DiscountPercentage: 35, RuleName: strPtr("Sữa trứng - giảm 35% khi hạn dưới 3 ngày")},
		{CategoryID: categoryMap["Thực phẩm - Sữa trứng"], DaysBeforeExpiry: 7, DiscountPercentage: 15, RuleName: strPtr("Sữa trứng - giảm 15% khi hạn dưới 7 ngày")},

		// Đồ uống - Có cồn
		{CategoryID: categoryMap["Đồ uống - Có cồn"], DaysBeforeExpiry: 30, DiscountPercentage: 25, RuleName: strPtr("Đồ uống có cồn - giảm 25% khi hạn dưới 30 ngày")},

		// Đồ uống - Không cồn
		{CategoryID: categoryMap["Đồ uống - Không cồn"], DaysBeforeExpiry: 10, DiscountPercentage: 20, RuleName: strPtr("Đồ uống không cồn - giảm 20% khi hạn dưới 10 ngày")},
		{CategoryID: categoryMap["Đồ uống - Không cồn"], DaysBeforeExpiry: 5, DiscountPercentage: 35, RuleName: strPtr("Đồ uống không cồn - giảm 35% khi hạn dưới 5 ngày")},

		// Đồ uống - Nóng
		{CategoryID: categoryMap["Đồ uống - Nóng"], DaysBeforeExpiry: 15, DiscountPercentage: 15, RuleName: strPtr("Đồ uống nóng - giảm 15% khi hạn dưới 15 ngày")},
	}

	if err := tx.Create(&rules).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d discount rules", len(rules))
	return nil
}

func seedCustomers(tx *gorm.DB, membershipMap map[string]uint) (map[string]uint, error) {
	// Generate 200 customers with realistic data
	firstNames := []string{"Nguyễn", "Trần", "Lê", "Phạm", "Hoàng", "Phan", "Vũ", "Võ", "Đặng", "Bùi",
		"Đỗ", "Hồ", "Ngô", "Dương", "Lý", "Mai", "Cao", "Tôn", "Trịnh", "Nông"}
	middleNames := []string{"Văn", "Thị", "Hoàng", "Minh", "Thúy", "Quốc", "Hữu", "Đức", "Thanh", "Kim",
		"Thu", "Hải", "Anh", "Bảo", "Công", "Duy", "Gia", "Hà", "Hùng", "Khánh"}
	lastNames := []string{"Khách", "Mai", "Nam", "Hằng", "Tuấn", "Linh", "Đức", "Hoa", "Long", "Phương",
		"Quân", "Hương", "Sơn", "Thảo", "Vinh", "Yến", "Bình", "Châu", "Dũng", "Giang",
		"Hiếu", "Khuê", "Loan", "Minh", "Nga", "Phát", "Quỳnh", "Sáng", "Tâm", "Uyên"}

	var customers []models.Customer
	baseRegDate, _ := time.Parse("2006-01-02", "2024-01-01")

	// Distribution: 40% Bronze, 30% Silver, 20% Gold, 8% Platinum, 2% Diamond
	membershipLevels := []string{
		"Bronze", "Bronze", "Bronze", "Bronze", // 40%
		"Silver", "Silver", "Silver", // 30%
		"Gold", "Gold", // 20%
		"Platinum", // 8%
		"Diamond",  // 2%
	}

	for i := 1; i <= 200; i++ {
		// Random name generation
		firstName := firstNames[i%len(firstNames)]
		middleName := middleNames[(i*3)%len(middleNames)]
		lastName := lastNames[(i*7)%len(lastNames)]
		fullName := fmt.Sprintf("%s %s %s", firstName, middleName, lastName)

		// Phone number generation (09xx-xxx-xxx)
		phonePrefix := []string{"090", "091", "092", "093", "094", "095", "096", "097", "098", "099"}
		phone := fmt.Sprintf("%s%07d", phonePrefix[i%len(phonePrefix)], 1000000+(i*12345)%8999999)

		// Email generation
		emailPrefix := fmt.Sprintf("customer%03d", i)
		emailDomains := []string{"gmail.com", "yahoo.com", "hotmail.com", "outlook.com"}
		email := fmt.Sprintf("%s@%s", emailPrefix, emailDomains[i%len(emailDomains)])

		// Membership level based on distribution
		levelIndex := (i - 1) % len(membershipLevels)
		membershipLevel := membershipLevels[levelIndex]

		// Registration date - spread over 8 months
		regDate := baseRegDate.AddDate(0, (i-1)%8, (i*3)%28)

		// Spending and points based on membership level
		var totalSpending float64
		var loyaltyPoints int
		switch membershipLevel {
		case "Bronze":
			totalSpending = float64(500000 + (i*50000)%4500000) // 0.5M - 5M
			loyaltyPoints = int(totalSpending / 10000)
		case "Silver":
			totalSpending = float64(5000000 + (i*100000)%15000000) // 5M - 20M
			loyaltyPoints = int(totalSpending * 1.2 / 10000)
		case "Gold":
			totalSpending = float64(20000000 + (i*500000)%30000000) // 20M - 50M
			loyaltyPoints = int(totalSpending * 1.5 / 10000)
		case "Platinum":
			totalSpending = float64(50000000 + (i*1000000)%50000000) // 50M - 100M
			loyaltyPoints = int(totalSpending * 2.0 / 10000)
		case "Diamond":
			totalSpending = float64(100000000 + (i*2000000)%100000000) // 100M - 200M
			loyaltyPoints = int(totalSpending * 2.5 / 10000)
		}

		customer := models.Customer{
			CustomerCode:      strPtr(fmt.Sprintf("CUST%03d", i)),
			FullName:          strPtr(fullName),
			Phone:             strPtr(phone),
			Email:             strPtr(email),
			MembershipCardNo:  strPtr(fmt.Sprintf("MB%03d", i)),
			MembershipLevelID: uintPtr(membershipMap[membershipLevel]),
			RegistrationDate:  regDate,
			TotalSpending:     totalSpending,
			LoyaltyPoints:     loyaltyPoints,
		}

		customers = append(customers, customer)
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
	// Warehouse inventory is now created by purchase orders
	// This function can be used for additional manual inventory adjustments if needed
	log.Printf("  ✓ Warehouse inventory created through purchase orders")
	return nil
}

func seedShelfData(tx *gorm.DB, shelfMap map[string]uint, productMap map[string]uint) error {
	// Comprehensive Shelf Layout for all purchased products
	layouts := []models.ShelfLayout{}

	// SH001: Văn phòng phẩm shelf (15 products)
	for i := 1; i <= 15; i++ {
		code := fmt.Sprintf("VPP%03d", i)
		if prodID, exists := productMap[code]; exists {
			posCode := fmt.Sprintf("A%d", i)
			maxQty := 100
			if i > 10 {
				maxQty = 50 // Smaller quantities for less common items
			}
			layouts = append(layouts, models.ShelfLayout{
				ShelfID:      shelfMap["SH001"],
				ProductID:    prodID,
				PositionCode: posCode,
				MaxQuantity:  maxQty,
			})
		}
	}

	// SH002: Đồ gia dụng shelf (15 home goods + 10 kitchen items)
	posCounter := 1
	for i := 1; i <= 15; i++ {
		code := fmt.Sprintf("GD%03d", i)
		if prodID, exists := productMap[code]; exists {
			posCode := fmt.Sprintf("B%d", posCounter)
			maxQty := 30
			if i <= 5 {
				maxQty = 20 // Expensive items have lower max quantity
			}
			layouts = append(layouts, models.ShelfLayout{
				ShelfID:      shelfMap["SH002"],
				ProductID:    prodID,
				PositionCode: posCode,
				MaxQuantity:  maxQty,
			})
			posCounter++
		}
	}
	// Add kitchen items to same shelf
	for i := 1; i <= 10; i++ {
		code := fmt.Sprintf("DB%03d", i)
		if prodID, exists := productMap[code]; exists {
			posCode := fmt.Sprintf("B%d", posCounter)
			maxQty := 15
			if i <= 5 {
				maxQty = 10 // Appliances have lower quantity
			}
			layouts = append(layouts, models.ShelfLayout{
				ShelfID:      shelfMap["SH002"],
				ProductID:    prodID,
				PositionCode: posCode,
				MaxQuantity:  maxQty,
			})
			posCounter++
		}
	}

	// SH003: Điện tử shelf (15 products)
	for i := 1; i <= 15; i++ {
		code := fmt.Sprintf("DT%03d", i)
		if prodID, exists := productMap[code]; exists {
			posCode := fmt.Sprintf("C%d", i)
			maxQty := 40
			if i <= 5 {
				maxQty = 25 // Higher value items
			} else if i > 10 {
				maxQty = 60 // Accessories
			}
			layouts = append(layouts, models.ShelfLayout{
				ShelfID:      shelfMap["SH003"],
				ProductID:    prodID,
				PositionCode: posCode,
				MaxQuantity:  maxQty,
			})
		}
	}

	// SH004: Thực phẩm khô shelf (20 food products)
	for i := 1; i <= 20; i++ {
		code := fmt.Sprintf("TP%03d", i)
		if prodID, exists := productMap[code]; exists {
			posCode := fmt.Sprintf("D%d", i)
			maxQty := 80
			if i <= 8 {
				maxQty = 100 // Dry goods can stock more
			} else if i <= 13 {
				maxQty = 60 // Fresh produce
			} else if i <= 17 {
				maxQty = 40 // Meat/seafood
			} else {
				maxQty = 120 // Dairy/eggs high turnover
			}
			layouts = append(layouts, models.ShelfLayout{
				ShelfID:      shelfMap["SH004"],
				ProductID:    prodID,
				PositionCode: posCode,
				MaxQuantity:  maxQty,
			})
		}
	}

	// SH005: Đồ uống shelf (15 beverages)
	for i := 1; i <= 15; i++ {
		code := fmt.Sprintf("DU%03d", i)
		if prodID, exists := productMap[code]; exists {
			posCode := fmt.Sprintf("E%d", i)
			maxQty := 60
			if i <= 3 {
				maxQty = 48 // Beer/wine cases
			} else if i <= 11 {
				maxQty = 72 // Soft drinks
			} else {
				maxQty = 40 // Coffee/tea
			}
			layouts = append(layouts, models.ShelfLayout{
				ShelfID:      shelfMap["SH005"],
				ProductID:    prodID,
				PositionCode: posCode,
				MaxQuantity:  maxQty,
			})
		}
	}

	// SH006: Văn phòng phẩm 2 - currently empty, can be used for overflow

	// SH007: Rau quả tươi - handled in SH004 with food products

	// SH008: Mỹ phẩm shelf (10 cosmetics + 7 fashion items)
	posCounter = 1
	for i := 1; i <= 10; i++ {
		code := fmt.Sprintf("MP%03d", i)
		if prodID, exists := productMap[code]; exists {
			posCode := fmt.Sprintf("G%d", posCounter)
			maxQty := 40
			if i <= 4 {
				maxQty = 30 // Skincare
			} else if i <= 7 {
				maxQty = 25 // Makeup
			} else {
				maxQty = 50 // Personal hygiene
			}
			layouts = append(layouts, models.ShelfLayout{
				ShelfID:      shelfMap["SH008"],
				ProductID:    prodID,
				PositionCode: posCode,
				MaxQuantity:  maxQty,
			})
			posCounter++
		}
	}
	// Add fashion items to cosmetics shelf
	for i := 1; i <= 7; i++ {
		code := fmt.Sprintf("TT%03d", i)
		if prodID, exists := productMap[code]; exists {
			posCode := fmt.Sprintf("G%d", posCounter)
			maxQty := 20
			if i <= 4 {
				maxQty = 15 // Clothing items
			}
			layouts = append(layouts, models.ShelfLayout{
				ShelfID:      shelfMap["SH008"],
				ProductID:    prodID,
				PositionCode: posCode,
				MaxQuantity:  maxQty,
			})
			posCounter++
		}
	}

	if err := tx.Create(&layouts).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d shelf layouts", len(layouts))

	// Shelf inventory will be created by stock transfers
	log.Printf("  ✓ Shelf inventory will be populated through stock transfers")
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

func seedPurchaseOrders(tx *gorm.DB, employeeMap map[string]uint, supplierMap map[string]uint, productMap map[string]uint, warehouseMap map[string]uint) error {
	// Get all products with their details for better planning
	var products []models.Product
	tx.Find(&products)
	productDetailMap := make(map[uint]models.Product)
	for _, p := range products {
		productDetailMap[p.ProductID] = p
	}

	// Main warehouse for receiving goods
	mainWarehouseID := warehouseMap["WH001"]

	// Initial stock order - before store opening (Aug 10, 2025)
	initialDate, _ := time.Parse("2006-01-02", "2025-08-10")

	// Create purchase orders with realistic quantities based on product types
	orders := []models.PurchaseOrder{}
	orderDetails := []models.PurchaseOrderDetail{}
	warehouseInventory := []models.WarehouseInventory{}

	// Order 1: Initial stock for Office Supplies (Aug 10)
	order1 := models.PurchaseOrder{
		OrderNo:      "PO-2025-08-001",
		SupplierID:   supplierMap["SUP003"],
		EmployeeID:   employeeMap["EMP005"],
		OrderDate:    initialDate,
		DeliveryDate: timePtr(initialDate.AddDate(0, 0, 2)),
		TotalAmount:  0,
		Status:       models.OrderReceived,
		Notes:        strPtr("Initial stock - Office supplies"),
	}
	if err := tx.Create(&order1).Error; err != nil {
		return err
	}

	// Add details for office supplies
	officeProducts := []string{"VPP001", "VPP002", "VPP003", "VPP004", "VPP005"}
	totalAmount := 0.0
	for _, code := range officeProducts {
		prodID := productMap[code]
		product := productDetailMap[prodID]
		quantity := 500                         // Initial high stock
		unitPrice := product.SellingPrice * 0.6 // Import at 60% of selling price
		subtotal := float64(quantity) * unitPrice
		totalAmount += subtotal

		detail := models.PurchaseOrderDetail{
			OrderID:   order1.OrderID,
			ProductID: prodID,
			Quantity:  quantity,
			UnitPrice: unitPrice,
			Subtotal:  subtotal,
		}
		orderDetails = append(orderDetails, detail)

		// Create warehouse inventory entry
		inventory := models.WarehouseInventory{
			WarehouseID: mainWarehouseID,
			ProductID:   prodID,
			BatchCode:   fmt.Sprintf("%s-2025-08-01", code),
			Quantity:    quantity,
			ImportDate:  *order1.DeliveryDate,
			ImportPrice: unitPrice,
		}
		warehouseInventory = append(warehouseInventory, inventory)
	}
	tx.Model(&order1).Update("total_amount", totalAmount)
	orders = append(orders, order1)

	// Order 2: Initial stock for Home Goods (Aug 11)
	order2 := models.PurchaseOrder{
		OrderNo:      "PO-2025-08-002",
		SupplierID:   supplierMap["SUP004"],
		EmployeeID:   employeeMap["EMP005"],
		OrderDate:    initialDate.AddDate(0, 0, 1),
		DeliveryDate: timePtr(initialDate.AddDate(0, 0, 3)),
		TotalAmount:  0,
		Status:       models.OrderReceived,
		Notes:        strPtr("Initial stock - Home goods & Kitchen"),
	}
	if err := tx.Create(&order2).Error; err != nil {
		return err
	}

	// Add details for home goods
	homeProducts := []string{"GD001", "GD002", "GD003", "DB001", "DB002"}
	totalAmount = 0.0
	for _, code := range homeProducts {
		prodID := productMap[code]
		product := productDetailMap[prodID]
		quantity := 100 // Lower quantity for expensive items
		if product.SellingPrice > 500000 {
			quantity = 50
		}
		unitPrice := product.SellingPrice * 0.6
		subtotal := float64(quantity) * unitPrice
		totalAmount += subtotal

		detail := models.PurchaseOrderDetail{
			OrderID:   order2.OrderID,
			ProductID: prodID,
			Quantity:  quantity,
			UnitPrice: unitPrice,
			Subtotal:  subtotal,
		}
		orderDetails = append(orderDetails, detail)

		inventory := models.WarehouseInventory{
			WarehouseID: mainWarehouseID,
			ProductID:   prodID,
			BatchCode:   fmt.Sprintf("%s-2025-08-02", code),
			Quantity:    quantity,
			ImportDate:  *order2.DeliveryDate,
			ImportPrice: unitPrice,
		}
		warehouseInventory = append(warehouseInventory, inventory)
	}
	tx.Model(&order2).Update("total_amount", totalAmount)
	orders = append(orders, order2)

	// Order 3: Initial stock for Electronics (Aug 12)
	order3 := models.PurchaseOrder{
		OrderNo:      "PO-2025-08-003",
		SupplierID:   supplierMap["SUP002"],
		EmployeeID:   employeeMap["EMP005"],
		OrderDate:    initialDate.AddDate(0, 0, 2),
		DeliveryDate: timePtr(initialDate.AddDate(0, 0, 4)),
		TotalAmount:  0,
		Status:       models.OrderReceived,
		Notes:        strPtr("Initial stock - Electronics"),
	}
	if err := tx.Create(&order3).Error; err != nil {
		return err
	}

	// Add electronics
	electronicsProducts := []string{"DT001", "DT002", "DT003", "DT004", "DT005"}
	totalAmount = 0.0
	for _, code := range electronicsProducts {
		prodID := productMap[code]
		product := productDetailMap[prodID]
		quantity := 200
		if product.SellingPrice > 300000 {
			quantity = 100
		}
		unitPrice := product.SellingPrice * 0.7 // Electronics have lower margin
		subtotal := float64(quantity) * unitPrice
		totalAmount += subtotal

		detail := models.PurchaseOrderDetail{
			OrderID:   order3.OrderID,
			ProductID: prodID,
			Quantity:  quantity,
			UnitPrice: unitPrice,
			Subtotal:  subtotal,
		}
		orderDetails = append(orderDetails, detail)

		inventory := models.WarehouseInventory{
			WarehouseID: mainWarehouseID,
			ProductID:   prodID,
			BatchCode:   fmt.Sprintf("%s-2025-08-03", code),
			Quantity:    quantity,
			ImportDate:  *order3.DeliveryDate,
			ImportPrice: unitPrice,
		}
		warehouseInventory = append(warehouseInventory, inventory)
	}
	tx.Model(&order3).Update("total_amount", totalAmount)
	orders = append(orders, order3)

	// Order 4: Initial stock for Food & Beverages (Aug 13)
	order4 := models.PurchaseOrder{
		OrderNo:      "PO-2025-08-004",
		SupplierID:   supplierMap["SUP001"],
		EmployeeID:   employeeMap["EMP005"],
		OrderDate:    initialDate.AddDate(0, 0, 3),
		DeliveryDate: timePtr(initialDate.AddDate(0, 0, 4)),
		TotalAmount:  0,
		Status:       models.OrderReceived,
		Notes:        strPtr("Initial stock - Food products"),
	}
	if err := tx.Create(&order4).Error; err != nil {
		return err
	}

	// Add ALL food products (TP001-TP020) with expiry dates
	totalAmount = 0.0
	for i := 1; i <= 20; i++ {
		code := fmt.Sprintf("TP%03d", i)
		if prodID, exists := productMap[code]; exists {
			product := productDetailMap[prodID]
			// Vary quantities based on product type
			quantity := 200
			var expiryDate *time.Time
			if i <= 8 {
				// Dry goods - longer shelf life, higher quantity
				quantity = 250
				e := initialDate.AddDate(0, 12, 0) // 12 months
				expiryDate = &e
			} else if i <= 13 {
				// Fresh produce - short shelf life
				quantity = 150
				e := initialDate.AddDate(0, 0, 7) // 7 days
				expiryDate = &e
			} else if i <= 17 {
				// Meat/seafood - frozen
				quantity = 100
				e := initialDate.AddDate(0, 3, 0) // 3 months
				expiryDate = &e
			} else {
				// Dairy/eggs
				quantity = 300
				e := initialDate.AddDate(0, 0, 30) // 30 days
				expiryDate = &e
			}
			unitPrice := product.SellingPrice * 0.5 // Higher margin for food
			subtotal := float64(quantity) * unitPrice
			totalAmount += subtotal

			detail := models.PurchaseOrderDetail{
				OrderID:   order4.OrderID,
				ProductID: prodID,
				Quantity:  quantity,
				UnitPrice: unitPrice,
				Subtotal:  subtotal,
			}
			orderDetails = append(orderDetails, detail)

			inventory := models.WarehouseInventory{
				WarehouseID: mainWarehouseID,
				ProductID:   prodID,
				BatchCode:   fmt.Sprintf("%s-2025-08-04", code),
				Quantity:    quantity,
				ImportDate:  *order4.DeliveryDate,
				ExpiryDate:  expiryDate,
				ImportPrice: unitPrice,
			}
			warehouseInventory = append(warehouseInventory, inventory)
		}
	}
	tx.Model(&order4).Update("total_amount", totalAmount)
	orders = append(orders, order4)

	// Order 5: Beverages (Aug 13)
	order5 := models.PurchaseOrder{
		OrderNo:      "PO-2025-08-005",
		SupplierID:   supplierMap["SUP005"],
		EmployeeID:   employeeMap["EMP005"],
		OrderDate:    initialDate.AddDate(0, 0, 3),
		DeliveryDate: timePtr(initialDate.AddDate(0, 0, 4)),
		TotalAmount:  0,
		Status:       models.OrderReceived,
		Notes:        strPtr("Initial stock - Beverages"),
	}
	if err := tx.Create(&order5).Error; err != nil {
		return err
	}

	// Add ALL beverages (DU001-DU015)
	totalAmount = 0.0
	for i := 1; i <= 15; i++ {
		code := fmt.Sprintf("DU%03d", i)
		if prodID, exists := productMap[code]; exists {
			product := productDetailMap[prodID]
			quantity := 300 // High demand for beverages
			var expiry *time.Time
			if i <= 3 {
				// Alcoholic beverages - longer shelf life
				quantity = 200
				e := initialDate.AddDate(2, 0, 0) // 2 years
				expiry = &e
			} else if i <= 11 {
				// Soft drinks, juices
				quantity = 350
				e := initialDate.AddDate(0, 6, 0) // 6 months
				expiry = &e
			} else {
				// Coffee, tea - dry products
				quantity = 250
				e := initialDate.AddDate(1, 0, 0) // 1 year
				expiry = &e
			}
			unitPrice := product.SellingPrice * 0.55
			subtotal := float64(quantity) * unitPrice
			totalAmount += subtotal

			detail := models.PurchaseOrderDetail{
				OrderID:   order5.OrderID,
				ProductID: prodID,
				Quantity:  quantity,
				UnitPrice: unitPrice,
				Subtotal:  subtotal,
			}
			orderDetails = append(orderDetails, detail)

			inventory := models.WarehouseInventory{
				WarehouseID: mainWarehouseID,
				ProductID:   prodID,
				BatchCode:   fmt.Sprintf("%s-2025-08-05", code),
				Quantity:    quantity,
				ImportDate:  *order5.DeliveryDate,
				ExpiryDate:  expiry,
				ImportPrice: unitPrice,
			}
			warehouseInventory = append(warehouseInventory, inventory)
		}
	}
	tx.Model(&order5).Update("total_amount", totalAmount)
	orders = append(orders, order5)

	// Order 6: Cosmetics and Fashion (Aug 14)
	order6 := models.PurchaseOrder{
		OrderNo:      "PO-2025-08-006",
		SupplierID:   supplierMap["SUP001"], // Can handle cosmetics/fashion too
		EmployeeID:   employeeMap["EMP005"],
		OrderDate:    initialDate.AddDate(0, 0, 4),
		DeliveryDate: timePtr(initialDate.AddDate(0, 0, 5)),
		TotalAmount:  0,
		Status:       models.OrderReceived,
		Notes:        strPtr("Initial stock - Cosmetics & Fashion"),
	}
	if err := tx.Create(&order6).Error; err != nil {
		return err
	}

	// Add cosmetics (MP001-MP010)
	totalAmount = 0.0
	for i := 1; i <= 10; i++ {
		code := fmt.Sprintf("MP%03d", i)
		if prodID, exists := productMap[code]; exists {
			product := productDetailMap[prodID]
			quantity := 150
			if i <= 4 {
				quantity = 120 // Skincare - moderate stock
			} else if i <= 7 {
				quantity = 100 // Makeup - lower stock
			} else {
				quantity = 200 // Personal hygiene - higher turnover
			}
			unitPrice := product.SellingPrice * 0.5
			subtotal := float64(quantity) * unitPrice
			totalAmount += subtotal

			detail := models.PurchaseOrderDetail{
				OrderID:   order6.OrderID,
				ProductID: prodID,
				Quantity:  quantity,
				UnitPrice: unitPrice,
				Subtotal:  subtotal,
			}
			orderDetails = append(orderDetails, detail)

			inventory := models.WarehouseInventory{
				WarehouseID: mainWarehouseID,
				ProductID:   prodID,
				BatchCode:   fmt.Sprintf("%s-2025-08-06", code),
				Quantity:    quantity,
				ImportDate:  *order6.DeliveryDate,
				ImportPrice: unitPrice,
			}
			warehouseInventory = append(warehouseInventory, inventory)
		}
	}

	// Add fashion items (TT001-TT007)
	for i := 1; i <= 7; i++ {
		code := fmt.Sprintf("TT%03d", i)
		if prodID, exists := productMap[code]; exists {
			product := productDetailMap[prodID]
			quantity := 80
			if i <= 4 {
				quantity = 60 // Clothing - lower stock due to sizes
			} else {
				quantity = 100 // Accessories
			}
			unitPrice := product.SellingPrice * 0.4 // Fashion has higher margin
			subtotal := float64(quantity) * unitPrice
			totalAmount += subtotal

			detail := models.PurchaseOrderDetail{
				OrderID:   order6.OrderID,
				ProductID: prodID,
				Quantity:  quantity,
				UnitPrice: unitPrice,
				Subtotal:  subtotal,
			}
			orderDetails = append(orderDetails, detail)

			inventory := models.WarehouseInventory{
				WarehouseID: mainWarehouseID,
				ProductID:   prodID,
				BatchCode:   fmt.Sprintf("%s-2025-08-06", code),
				Quantity:    quantity,
				ImportDate:  *order6.DeliveryDate,
				ImportPrice: unitPrice,
			}
			warehouseInventory = append(warehouseInventory, inventory)
		}
	}
	tx.Model(&order6).Update("total_amount", totalAmount)
	orders = append(orders, order6)

	// Restock orders based on sales patterns (weekly restocks)
	// Week 1 restock - Aug 22
	restockDate1 := initialDate.AddDate(0, 0, 12)
	order7 := models.PurchaseOrder{
		OrderNo:      "PO-2025-08-007",
		SupplierID:   supplierMap["SUP001"],
		EmployeeID:   employeeMap["EMP005"],
		OrderDate:    restockDate1,
		DeliveryDate: timePtr(restockDate1.AddDate(0, 0, 2)),
		TotalAmount:  0,
		Status:       models.OrderReceived,
		Notes:        strPtr("Weekly restock - Fast moving items"),
	}
	if err := tx.Create(&order7).Error; err != nil {
		return err
	}

	// Restock fast-moving items (food, beverages, office supplies)
	restockItems := []struct {
		code     string
		quantity int
	}{
		{"TP001", 100}, {"TP002", 80}, {"DU001", 150}, {"DU002", 100},
		{"VPP001", 200}, {"VPP002", 150},
	}
	totalAmount = 0.0
	for _, item := range restockItems {
		prodID := productMap[item.code]
		product := productDetailMap[prodID]
		unitPrice := product.SellingPrice * 0.6
		subtotal := float64(item.quantity) * unitPrice
		totalAmount += subtotal

		detail := models.PurchaseOrderDetail{
			OrderID:   order7.OrderID,
			ProductID: prodID,
			Quantity:  item.quantity,
			UnitPrice: unitPrice,
			Subtotal:  subtotal,
		}
		orderDetails = append(orderDetails, detail)

		var expiry *time.Time
		if strings.HasPrefix(item.code, "TP") || strings.HasPrefix(item.code, "DU") {
			e := restockDate1.AddDate(0, 4, 0)
			expiry = &e
		}

		inventory := models.WarehouseInventory{
			WarehouseID: mainWarehouseID,
			ProductID:   prodID,
			BatchCode:   fmt.Sprintf("%s-2025-08-R1", item.code),
			Quantity:    item.quantity,
			ImportDate:  *order6.DeliveryDate,
			ExpiryDate:  expiry,
			ImportPrice: unitPrice,
		}
		warehouseInventory = append(warehouseInventory, inventory)
	}
	tx.Model(&order7).Update("total_amount", totalAmount)
	orders = append(orders, order7)

	// Week 2 restock - Aug 29
	restockDate2 := initialDate.AddDate(0, 0, 19)
	order8 := models.PurchaseOrder{
		OrderNo:      "PO-2025-08-008",
		SupplierID:   supplierMap["SUP002"],
		EmployeeID:   employeeMap["EMP005"],
		OrderDate:    restockDate2,
		DeliveryDate: timePtr(restockDate2.AddDate(0, 0, 2)),
		TotalAmount:  0,
		Status:       models.OrderReceived,
		Notes:        strPtr("Weekly restock - Electronics"),
	}
	if err := tx.Create(&order8).Error; err != nil {
		return err
	}

	// Restock electronics
	electronicRestock := []struct {
		code     string
		quantity int
	}{
		{"DT001", 50}, {"DT002", 40}, {"DT003", 100},
	}
	totalAmount = 0.0
	for _, item := range electronicRestock {
		prodID := productMap[item.code]
		product := productDetailMap[prodID]
		unitPrice := product.SellingPrice * 0.7
		subtotal := float64(item.quantity) * unitPrice
		totalAmount += subtotal

		detail := models.PurchaseOrderDetail{
			OrderID:   order8.OrderID,
			ProductID: prodID,
			Quantity:  item.quantity,
			UnitPrice: unitPrice,
			Subtotal:  subtotal,
		}
		orderDetails = append(orderDetails, detail)

		inventory := models.WarehouseInventory{
			WarehouseID: mainWarehouseID,
			ProductID:   prodID,
			BatchCode:   fmt.Sprintf("%s-2025-08-R2", item.code),
			Quantity:    item.quantity,
			ImportDate:  *order8.DeliveryDate,
			ImportPrice: unitPrice,
		}
		warehouseInventory = append(warehouseInventory, inventory)
	}
	tx.Model(&order8).Update("total_amount", totalAmount)
	orders = append(orders, order8)

	// Week 3 restock - Sep 5
	restockDate3 := initialDate.AddDate(0, 0, 26)
	order9 := models.PurchaseOrder{
		OrderNo:      "PO-2025-09-001",
		SupplierID:   supplierMap["SUP004"],
		EmployeeID:   employeeMap["EMP005"],
		OrderDate:    restockDate3,
		DeliveryDate: timePtr(restockDate3.AddDate(0, 0, 2)),
		TotalAmount:  0,
		Status:       models.OrderReceived,
		Notes:        strPtr("Monthly restock - Home goods"),
	}
	if err := tx.Create(&order9).Error; err != nil {
		return err
	}

	// Restock home goods
	homeRestock := []struct {
		code     string
		quantity int
	}{
		{"GD001", 30}, {"GD002", 20}, {"DB001", 40},
	}
	totalAmount = 0.0
	for _, item := range homeRestock {
		prodID := productMap[item.code]
		product := productDetailMap[prodID]
		unitPrice := product.SellingPrice * 0.6
		subtotal := float64(item.quantity) * unitPrice
		totalAmount += subtotal

		detail := models.PurchaseOrderDetail{
			OrderID:   order9.OrderID,
			ProductID: prodID,
			Quantity:  item.quantity,
			UnitPrice: unitPrice,
			Subtotal:  subtotal,
		}
		orderDetails = append(orderDetails, detail)

		inventory := models.WarehouseInventory{
			WarehouseID: mainWarehouseID,
			ProductID:   prodID,
			BatchCode:   fmt.Sprintf("%s-2025-09-R1", item.code),
			Quantity:    item.quantity,
			ImportDate:  *order9.DeliveryDate,
			ImportPrice: unitPrice,
		}
		warehouseInventory = append(warehouseInventory, inventory)
	}
	tx.Model(&order9).Update("total_amount", totalAmount)
	orders = append(orders, order9)

	// Create all order details
	if err := tx.Create(&orderDetails).Error; err != nil {
		return err
	}

	// Create warehouse inventory entries
	if err := tx.Create(&warehouseInventory).Error; err != nil {
		return err
	}

	log.Printf("  ✓ Seeded %d purchase orders", len(orders))
	log.Printf("  ✓ Seeded %d purchase order details", len(orderDetails))
	log.Printf("  ✓ Created %d warehouse inventory entries", len(warehouseInventory))
	return nil
}

func seedStockTransfers(tx *gorm.DB, warehouseMap map[string]uint, shelfMap map[string]uint, productMap map[string]uint, employeeMap map[string]uint) error {
	// Get warehouse inventory to ensure we only transfer what exists
	var warehouseInventory []models.WarehouseInventory
	tx.Find(&warehouseInventory)

	// Create map for easy lookup: productID -> []inventory
	warehouseStock := make(map[uint][]models.WarehouseInventory)
	for _, inv := range warehouseInventory {
		warehouseStock[inv.ProductID] = append(warehouseStock[inv.ProductID], inv)
	}

	// Get shelf layouts to know which products go to which shelves
	var shelfLayouts []models.ShelfLayout
	tx.Find(&shelfLayouts)

	// Create map: productID -> shelfID
	productShelfMap := make(map[uint]uint)
	for _, layout := range shelfLayouts {
		productShelfMap[layout.ProductID] = layout.ShelfID
	}

	mainWarehouseID := warehouseMap["WH001"]
	transfers := []models.StockTransfer{}
	transferNo := 1

	// Initial transfer after receiving first orders (Aug 14, 2025 - day before opening)
	initialTransferDate, _ := time.Parse("2006-01-02 15:04:05", "2025-08-14 10:00:00")

	// Transfer initial stock to shelves for store opening
	// We'll transfer products based on shelf layouts and available inventory
	initialTransfers := []struct {
		productCode string
		quantity    int
		notes       string
	}{}

	// Build transfer list based on available warehouse inventory and shelf layouts
	for prodID, invList := range warehouseStock {
		if len(invList) == 0 {
			continue
		}

		// Check if this product has a shelf layout
		shelfID, hasShelf := productShelfMap[prodID]
		if !hasShelf {
			continue
		}

		// Find product code
		var productCode string
		for code, id := range productMap {
			if id == prodID {
				productCode = code
				break
			}
		}

		if productCode == "" {
			continue
		}

		// Get shelf layout to determine initial transfer quantity
		var shelfLayout models.ShelfLayout
		tx.Where("shelf_id = ? AND product_id = ?", shelfID, prodID).First(&shelfLayout)

		// Calculate initial transfer quantity (50-70% of max capacity)
		initialQty := shelfLayout.MaxQuantity * 6 / 10

		// Check available inventory
		totalAvailable := 0
		for _, inv := range invList {
			totalAvailable += inv.Quantity
		}

		if totalAvailable > 0 {
			if initialQty > totalAvailable {
				initialQty = totalAvailable / 2 // Transfer half of available
			}
			if initialQty > 0 {
				initialTransfers = append(initialTransfers, struct {
					productCode string
					quantity    int
					notes       string
				}{
					productCode: productCode,
					quantity:    initialQty,
					notes:       fmt.Sprintf("Initial shelf stock - %s", productCode),
				})
			}
		}
	}

	for _, item := range initialTransfers {
		productID := productMap[item.productCode]
		shelfID, exists := productShelfMap[productID]
		if !exists {
			continue // Skip if no shelf layout for this product
		}

		// Check if we have inventory for this product
		if invs, ok := warehouseStock[productID]; ok && len(invs) > 0 {
			// Find batch with sufficient quantity
			var selectedBatch string
			for _, inv := range invs {
				// Get current quantity from DB
				var currentInv models.WarehouseInventory
				tx.Where("warehouse_id = ? AND product_id = ? AND batch_code = ?",
					mainWarehouseID, productID, inv.BatchCode).First(&currentInv)
				if currentInv.Quantity >= item.quantity {
					selectedBatch = inv.BatchCode
					break
				}
			}

			if selectedBatch == "" {
				// If no single batch has enough, use first available batch with partial quantity
				for _, inv := range invs {
					var currentInv models.WarehouseInventory
					tx.Where("warehouse_id = ? AND product_id = ? AND batch_code = ?",
						mainWarehouseID, productID, inv.BatchCode).First(&currentInv)
					if currentInv.Quantity > 0 {
						selectedBatch = inv.BatchCode
						if item.quantity > currentInv.Quantity {
							item.quantity = currentInv.Quantity
						}
						break
					}
				}
			}

			if selectedBatch != "" && item.quantity > 0 {
				transfer := models.StockTransfer{
					TransferCode:    fmt.Sprintf("ST-2025-08-%03d", transferNo),
					ProductID:       productID,
					FromWarehouseID: mainWarehouseID,
					ToShelfID:       shelfID,
					Quantity:        item.quantity,
					TransferDate:    initialTransferDate,
					EmployeeID:      employeeMap["EMP005"],
					BatchCode:       strPtr(selectedBatch),
					Notes:           strPtr(item.notes),
				}
				transfers = append(transfers, transfer)
				transferNo++

				// Update warehouse inventory (decrease)
				tx.Model(&models.WarehouseInventory{}).
					Where("warehouse_id = ? AND product_id = ? AND batch_code = ?", mainWarehouseID, productID, selectedBatch).
					Update("quantity", gorm.Expr("quantity - ?", item.quantity))
			}
		}
	}

	// Weekly restocking transfers based on sales patterns
	// Week 1 restock (Aug 22) - Focus on fast-moving items
	week1Date, _ := time.Parse("2006-01-02 15:04:05", "2025-08-22 14:00:00")
	week1Restocks := []struct {
		productCode string
		quantity    int
	}{
		// Office supplies
		{"VPP001", 50}, {"VPP002", 40}, {"VPP003", 30}, {"VPP004", 25}, {"VPP005", 35},
		// Food products
		{"TP001", 30}, {"TP002", 50}, {"TP003", 40}, {"TP004", 60}, {"TP005", 45},
		// Beverages
		{"DU001", 40}, {"DU002", 35}, {"DU003", 30}, {"DU004", 50}, {"DU005", 45},
	}

	for _, item := range week1Restocks {
		productID := productMap[item.productCode]
		shelfID, exists := productShelfMap[productID]
		if !exists {
			continue
		}

		if invs, ok := warehouseStock[productID]; ok && len(invs) > 0 {
			batchCode := invs[len(invs)-1].BatchCode // Use latest batch

			transfer := models.StockTransfer{
				TransferCode:    fmt.Sprintf("ST-2025-08-%03d", transferNo),
				ProductID:       productID,
				FromWarehouseID: mainWarehouseID,
				ToShelfID:       shelfID,
				Quantity:        item.quantity,
				TransferDate:    week1Date,
				EmployeeID:      employeeMap["EMP005"],
				BatchCode:       strPtr(batchCode),
				Notes:           strPtr("Weekly restock"),
			}
			transfers = append(transfers, transfer)
			transferNo++

			tx.Model(&models.WarehouseInventory{}).
				Where("warehouse_id = ? AND product_id = ? AND batch_code = ?", mainWarehouseID, productID, batchCode).
				Update("quantity", gorm.Expr("quantity - ?", item.quantity))
		}
	}

	// Week 2 restock (Aug 29) - Electronics and home goods
	week2Date, _ := time.Parse("2006-01-02 15:04:05", "2025-08-29 09:00:00")
	week2Restocks := []struct {
		productCode string
		quantity    int
	}{
		// Electronics
		{"DT001", 20}, {"DT002", 15}, {"DT003", 30}, {"DT004", 25}, {"DT005", 20},
		// Home goods
		{"GD001", 10}, {"GD002", 8}, {"GD003", 15}, {"DB001", 12}, {"DB002", 10},
	}

	for _, item := range week2Restocks {
		productID := productMap[item.productCode]
		shelfID, exists := productShelfMap[productID]
		if !exists {
			continue
		}

		if invs, ok := warehouseStock[productID]; ok && len(invs) > 0 {
			batchCode := invs[len(invs)-1].BatchCode

			transfer := models.StockTransfer{
				TransferCode:    fmt.Sprintf("ST-2025-08-%03d", transferNo),
				ProductID:       productID,
				FromWarehouseID: mainWarehouseID,
				ToShelfID:       shelfID,
				Quantity:        item.quantity,
				TransferDate:    week2Date,
				EmployeeID:      employeeMap["EMP005"],
				BatchCode:       strPtr(batchCode),
				Notes:           strPtr("Weekly restock"),
			}
			transfers = append(transfers, transfer)
			transferNo++

			tx.Model(&models.WarehouseInventory{}).
				Where("warehouse_id = ? AND product_id = ? AND batch_code = ?", mainWarehouseID, productID, batchCode).
				Update("quantity", gorm.Expr("quantity - ?", item.quantity))
		}
	}

	// Week 3 restock (Sep 5) - Mixed categories for month-end push
	week3Date, _ := time.Parse("2006-01-02 15:04:05", "2025-09-05 10:00:00")
	week3Restocks := []struct {
		productCode string
		quantity    int
	}{
		// Food restock
		{"TP001", 30}, {"TP002", 20}, {"TP006", 25}, {"TP007", 30}, {"TP008", 40},
		// Beverages restock
		{"DU001", 50}, {"DU002", 40}, {"DU006", 35}, {"DU007", 30}, {"DU008", 45},
		// Office supplies restock
		{"VPP001", 60}, {"VPP006", 20}, {"VPP007", 30}, {"VPP008", 25}, {"VPP009", 35},
	}

	for _, item := range week3Restocks {
		productID := productMap[item.productCode]
		shelfID, exists := productShelfMap[productID]
		if !exists {
			continue
		}

		if invs, ok := warehouseStock[productID]; ok && len(invs) > 0 {
			// Check available quantity across all batches
			totalAvailable := 0
			var selectedBatch string
			for _, inv := range invs {
				// Get current quantity from DB
				var currentInv models.WarehouseInventory
				tx.Where("warehouse_id = ? AND product_id = ? AND batch_code = ?",
					mainWarehouseID, productID, inv.BatchCode).First(&currentInv)
				if currentInv.Quantity >= item.quantity {
					selectedBatch = inv.BatchCode
					totalAvailable = currentInv.Quantity
					break
				} else if currentInv.Quantity > 0 && currentInv.Quantity > totalAvailable {
					selectedBatch = inv.BatchCode
					totalAvailable = currentInv.Quantity
				}
			}

			if selectedBatch == "" || totalAvailable == 0 {
				continue // Skip if no inventory available
			}

			// Adjust quantity if not enough available
			transferQty := item.quantity
			if transferQty > totalAvailable {
				transferQty = totalAvailable
			}

			transfer := models.StockTransfer{
				TransferCode:    fmt.Sprintf("ST-2025-09-%03d", transferNo),
				ProductID:       productID,
				FromWarehouseID: mainWarehouseID,
				ToShelfID:       shelfID,
				Quantity:        transferQty,
				TransferDate:    week3Date,
				EmployeeID:      employeeMap["EMP005"],
				BatchCode:       strPtr(selectedBatch),
				Notes:           strPtr("Weekly restock"),
			}
			transfers = append(transfers, transfer)
			transferNo++

			tx.Model(&models.WarehouseInventory{}).
				Where("warehouse_id = ? AND product_id = ? AND batch_code = ?", mainWarehouseID, productID, selectedBatch).
				Update("quantity", gorm.Expr("quantity - ?", transferQty))
		}
	}

	// Create all transfers
	if err := tx.Create(&transfers).Error; err != nil {
		return err
	}

	// Update shelf inventory based on transfers
	for _, transfer := range transfers {
		// Check if shelf inventory exists
		var shelfInv models.ShelfInventory
		result := tx.Where("shelf_id = ? AND product_id = ?", transfer.ToShelfID, transfer.ProductID).First(&shelfInv)

		if result.Error == gorm.ErrRecordNotFound {
			// Create new shelf inventory
			newShelfInv := models.ShelfInventory{
				ShelfID:         transfer.ToShelfID,
				ProductID:       transfer.ProductID,
				CurrentQuantity: transfer.Quantity,
			}
			tx.Create(&newShelfInv)
		} else {
			// Update existing shelf inventory
			tx.Model(&shelfInv).Update("current_quantity", shelfInv.CurrentQuantity+transfer.Quantity)
		}
	}

	log.Printf("  ✓ Seeded %d stock transfers", len(transfers))
	log.Printf("  ✓ Updated shelf inventory based on transfers")
	return nil
}

func seedSalesInvoices(tx *gorm.DB, customerMap map[string]uint, employeeMap map[string]uint, productMap map[string]uint) error {
	// Load discount rules and product categories for realistic discount logic
	var discountRules []models.DiscountRule
	tx.Find(&discountRules)

	discountRuleMap := make(map[uint][]models.DiscountRule) // categoryID -> discount rules
	for _, rule := range discountRules {
		discountRuleMap[rule.CategoryID] = append(discountRuleMap[rule.CategoryID], rule)
	}

	// Load products to get category information
	var allProducts []models.Product
	tx.Find(&allProducts)

	productCategoryMap := make(map[uint]uint) // productID -> categoryID
	for _, product := range allProducts {
		productCategoryMap[product.ProductID] = product.CategoryID
	}

	// Create comprehensive daily sales from August 15 - September 14, 2025
	startDate, _ := time.Parse("2006-01-02", "2025-08-15")

	var invoices []models.SalesInvoice
	invoiceNo := 1

	// Generate daily sales for the entire month
	for day := 0; day < 31; day++ {
		currentDate := startDate.AddDate(0, 0, day)

		// Generate 15-17 sales per day (500 total for the month)
		salesPerDay := 15
		if currentDate.Weekday() == time.Saturday || currentDate.Weekday() == time.Sunday {
			salesPerDay = 17 // More sales on weekends
		} else if currentDate.Weekday() == time.Friday {
			salesPerDay = 16 // Moderate increase on Friday
		}
		for sale := 0; sale < salesPerDay; sale++ {
			// Distribute sales evenly from 9 AM to 9 PM (12 hours)
			hour := 9 + (sale * 12 / salesPerDay)
			if hour >= 21 {
				hour = 20 + (sale % 2) // Keep within 20-21h for late sales
			}
			minute := (sale * 37) % 60 // Vary minutes
			saleTime := time.Date(currentDate.Year(), currentDate.Month(), currentDate.Day(), hour, minute, 0, 0, time.Local)

			// Random customer selection (including walk-ins)
			var customerID *uint
			if (day+sale)%5 != 0 { // 80% with membership, 20% walk-ins
				// Select from 200 customers randomly but consistently
				custIndex := ((day*13 + sale*7) % 200) + 1
				custCode := fmt.Sprintf("CUST%03d", custIndex)
				if custID, exists := customerMap[custCode]; exists {
					customerID = uintPtr(custID)
				}
			}

			// Random cashier
			cashiers := []string{"EMP003", "EMP006"}
			cashier := cashiers[(day+sale)%2]

			// Generate invoice items first to calculate proper discounts - All 50 products
			productCodes := []string{
				// Văn phòng phẩm (15)
				"VPP001", "VPP002", "VPP003", "VPP004", "VPP005", "VPP006", "VPP007", "VPP008", "VPP009", "VPP010",
				"VPP011", "VPP012", "VPP013", "VPP014", "VPP015",
				// Đồ gia dụng (15)
				"GD001", "GD002", "GD003", "GD004", "GD005", "GD006", "GD007", "GD008", "GD009", "GD010",
				"GD011", "GD012", "GD013", "GD014", "GD015",
				// Đồ điện tử (15)
				"DT001", "DT002", "DT003", "DT004", "DT005", "DT006", "DT007", "DT008", "DT009", "DT010",
				"DT011", "DT012", "DT013", "DT014", "DT015",
				// Đồ bếp (10)
				"DB001", "DB002", "DB003", "DB004", "DB005", "DB006", "DB007", "DB008", "DB009", "DB010",
				// Thực phẩm (20)
				"TP001", "TP002", "TP003", "TP004", "TP005", "TP006", "TP007", "TP008", "TP009", "TP010",
				"TP011", "TP012", "TP013", "TP014", "TP015", "TP016", "TP017", "TP018", "TP019", "TP020",
				// Đồ uống (15)
				"DU001", "DU002", "DU003", "DU004", "DU005", "DU006", "DU007", "DU008", "DU009", "DU010",
				"DU011", "DU012", "DU013", "DU014", "DU015",
				// Mỹ phẩm (10)
				"MP001", "MP002", "MP003", "MP004", "MP005", "MP006", "MP007", "MP008", "MP009", "MP010",
				// Thời trang (7)
				"TT001", "TT002", "TT003", "TT004", "TT005", "TT006", "TT007",
			}

			// Calculate invoice items for proper discounts
			numItems := 1 + ((day*7 + sale*3) % 5) + 1 // Random 2-6 items per invoice
			subtotalBeforeDiscount := 0.0
			totalDiscountAmount := 0.0

			for item := 0; item < numItems; item++ {
				productCode := productCodes[(day*sale+item)%len(productCodes)]
				productID := productMap[productCode]
				categoryID := productCategoryMap[productID]

				// Get product's selling price
				var product models.Product
				tx.Where("product_id = ?", productID).First(&product)

				quantity := 1 + (item % 3)
				unitPrice := product.SellingPrice
				lineSubtotal := unitPrice * float64(quantity)

				// Apply discount logic based on discount rules for the category
				discountPercentage := 0.0
				discountAmount := 0.0

				if rules, exists := discountRuleMap[categoryID]; exists && len(rules) > 0 {
					// For perishable items (food, drinks), apply expiry-based discounts
					foodCategories := []string{
						"Thực phẩm - Đồ khô", "Thực phẩm - Rau quả",
						"Thực phẩm - Thịt cá", "Thực phẩm - Sữa trứng",
					}
					drinkCategories := []string{
						"Đồ uống - Có cồn", "Đồ uống - Không cồn", "Đồ uống - Nóng",
					}

					isFood := false
					isDrink := false

					for _, foodCat := range foodCategories {
						if categoryID == getCategoryID(tx, foodCat) {
							isFood = true
							break
						}
					}
					for _, drinkCat := range drinkCategories {
						if categoryID == getCategoryID(tx, drinkCat) {
							isDrink = true
							break
						}
					}

					if isFood || isDrink {
						// 20% chance of getting close-to-expiry discount
						if (day+sale+item)%5 == 0 {
							// Use first discount rule (less aggressive)
							discountPercentage = rules[0].DiscountPercentage
						}
					}
				}

				// Apply membership discounts for non-walk-in customers
				if customerID != nil && discountPercentage == 0 {
					// Small membership discount (2-5%)
					discountPercentage = float64(2 + ((day + sale + item) % 4))
				}

				discountAmount = lineSubtotal * discountPercentage / 100.0

				subtotalBeforeDiscount += lineSubtotal
				totalDiscountAmount += discountAmount
			}

			// Calculate final invoice amounts
			subtotal := subtotalBeforeDiscount - totalDiscountAmount
			taxAmount := subtotal * 0.1 // 10% tax
			totalAmount := subtotal + taxAmount

			pointsEarned := 0
			if customerID != nil {
				pointsEarned = int(subtotal / 1000)
			}

			invoice := models.SalesInvoice{
				InvoiceNo:      fmt.Sprintf("INV-2025-%02d-%03d", currentDate.Month(), invoiceNo),
				CustomerID:     customerID,
				EmployeeID:     employeeMap[cashier],
				InvoiceDate:    saleTime,
				Subtotal:       subtotalBeforeDiscount,
				DiscountAmount: totalDiscountAmount,
				TaxAmount:      taxAmount,
				TotalAmount:    totalAmount,
				PaymentMethod:  paymentMethodPtr(getRandomPaymentMethod(day, sale)),
				PointsEarned:   pointsEarned,
				PointsUsed:     0,
			}

			if invoiceNo%10 == 0 && customerID != nil { // Some customers use points
				invoice.PointsUsed = pointsEarned / 2
			}

			invoices = append(invoices, invoice)
			invoiceNo++
		}
	}

	if err := tx.Create(&invoices).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d sales invoices", len(invoices))

	// Generate sales invoice details with proper discount logic
	var allInvoices []models.SalesInvoice
	tx.Order("invoice_id").Find(&allInvoices)

	var details []models.SalesInvoiceDetail

	// Generate details for ALL invoices with realistic discount logic - All 50 products
	for i, invoice := range allInvoices {
		productCodes := []string{
			// Văn phòng phẩm (15)
			"VPP001", "VPP002", "VPP003", "VPP004", "VPP005", "VPP006", "VPP007", "VPP008", "VPP009", "VPP010",
			"VPP011", "VPP012", "VPP013", "VPP014", "VPP015",
			// Đồ gia dụng (15)
			"GD001", "GD002", "GD003", "GD004", "GD005", "GD006", "GD007", "GD008", "GD009", "GD010",
			"GD011", "GD012", "GD013", "GD014", "GD015",
			// Đồ điện tử (15)
			"DT001", "DT002", "DT003", "DT004", "DT005", "DT006", "DT007", "DT008", "DT009", "DT010",
			"DT011", "DT012", "DT013", "DT014", "DT015",
			// Đồ bếp (10)
			"DB001", "DB002", "DB003", "DB004", "DB005", "DB006", "DB007", "DB008", "DB009", "DB010",
			// Thực phẩm (20)
			"TP001", "TP002", "TP003", "TP004", "TP005", "TP006", "TP007", "TP008", "TP009", "TP010",
			"TP011", "TP012", "TP013", "TP014", "TP015", "TP016", "TP017", "TP018", "TP019", "TP020",
			// Đồ uống (15)
			"DU001", "DU002", "DU003", "DU004", "DU005", "DU006", "DU007", "DU008", "DU009", "DU010",
			"DU011", "DU012", "DU013", "DU014", "DU015",
			// Mỹ phẩm (10)
			"MP001", "MP002", "MP003", "MP004", "MP005", "MP006", "MP007", "MP008", "MP009", "MP010",
			// Thời trang (7)
			"TT001", "TT002", "TT003", "TT004", "TT005", "TT006", "TT007",
		}

		// Recreate the same items as calculated above
		day := i / 16  // Approximate day
		sale := i % 16 // Approximate sale number within day
		numItems := 1 + ((day*7 + sale*3) % 5) + 1

		for item := 0; item < numItems; item++ {
			productCode := productCodes[(day*sale+item)%len(productCodes)]
			productID := productMap[productCode]
			categoryID := productCategoryMap[productID]

			// Get product's selling price
			var product models.Product
			tx.Where("product_id = ?", productID).First(&product)

			quantity := 1 + (item % 3)
			unitPrice := product.SellingPrice
			lineSubtotal := unitPrice * float64(quantity)

			// Apply same discount logic as above
			discountPercentage := 0.0
			discountAmount := 0.0

			if rules, exists := discountRuleMap[categoryID]; exists && len(rules) > 0 {
				foodCategories := []string{
					"Thực phẩm - Đồ khô", "Thực phẩm - Rau quả",
					"Thực phẩm - Thịt cá", "Thực phẩm - Sữa trứng",
				}
				drinkCategories := []string{
					"Đồ uống - Có cồn", "Đồ uống - Không cồn", "Đồ uống - Nóng",
				}

				isFood := false
				isDrink := false

				for _, foodCat := range foodCategories {
					if categoryID == getCategoryID(tx, foodCat) {
						isFood = true
						break
					}
				}
				for _, drinkCat := range drinkCategories {
					if categoryID == getCategoryID(tx, drinkCat) {
						isDrink = true
						break
					}
				}

				if isFood || isDrink {
					if (day+sale+item)%5 == 0 {
						discountPercentage = rules[0].DiscountPercentage
					}
				}
			}

			// Apply membership discounts for non-walk-in customers
			if invoice.CustomerID != nil && discountPercentage == 0 {
				discountPercentage = float64(2 + ((day + sale + item) % 4))
			}

			discountAmount = lineSubtotal * discountPercentage / 100.0
			finalSubtotal := lineSubtotal - discountAmount

			details = append(details, models.SalesInvoiceDetail{
				InvoiceID:          invoice.InvoiceID,
				ProductID:          productID,
				Quantity:           quantity,
				UnitPrice:          unitPrice,
				DiscountPercentage: discountPercentage,
				DiscountAmount:     discountAmount,
				Subtotal:           finalSubtotal,
			})
		}
	}

	if len(details) > 0 {
		if err := tx.Create(&details).Error; err != nil {
			return err
		}
		log.Printf("  ✓ Seeded %d sales invoice details", len(details))
	}

	return nil
}

// Helper function to get category ID by name
func getCategoryID(tx *gorm.DB, categoryName string) uint {
	var category models.ProductCategory
	tx.Where("category_name = ?", categoryName).First(&category)
	return category.CategoryID
}

// Helper function for random payment method
func getRandomPaymentMethod(day, sale int) models.PaymentMethod {
	methods := []models.PaymentMethod{
		models.PaymentCash,
		models.PaymentCard,
		models.PaymentCard, // Weight towards card payments
	}
	return methods[(day+sale)%len(methods)]
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
