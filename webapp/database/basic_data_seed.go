package database

import (
	"log"

	"github.com/supermarket/models"
	"gorm.io/gorm"
)

// seedWarehouses creates initial warehouse data
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

// seedProductCategories creates product category data
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

// seedPositions creates employee position data
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

// seedMembershipLevels creates customer membership level data
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

// seedSuppliers creates supplier data
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
