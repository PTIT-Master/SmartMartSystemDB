package database

import (
	"log"

	"github.com/supermarket/models"
	"gorm.io/gorm"
)

// seedProducts creates product data
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

// seedDisplayShelves creates display shelf data
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
		{ShelfCode: "SH009", ShelfName: "Quầy thời trang", CategoryID: categoryMap["Thời trang - Unisex"], Location: strPtr("Khu H - Tầng 1"), MaxCapacity: intPtr(200)},
		{ShelfCode: "SH010", ShelfName: "Quầy đồ bếp", CategoryID: categoryMap["Đồ bếp"], Location: strPtr("Khu I - Tầng 1"), MaxCapacity: intPtr(150)},
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

// seedDiscountRules creates discount rule data
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
