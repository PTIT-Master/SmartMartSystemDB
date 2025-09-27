package database

import (
	"fmt"
	"log"

	"gorm.io/gorm"
)

// seedDashboardTestData creates test data for dashboard features
func seedDashboardTestData(db *gorm.DB) error {
	log.Println("Seeding dashboard test data...")

	// Set search path
	if err := db.Exec("SET search_path TO supermarket").Error; err != nil {
		return fmt.Errorf("failed to set search path: %w", err)
	}

	// 1. Create low stock scenarios
	if err := db.Exec(`
		UPDATE products SET low_stock_threshold = 50 WHERE product_id IN (1, 2, 3);
	`).Error; err != nil {
		return fmt.Errorf("failed to update low stock thresholds: %w", err)
	}

	// 2. Create low stock inventory
	if err := db.Exec(`
		UPDATE warehouse_inventory 
		SET quantity = 5 
		WHERE product_id IN (1, 2, 3);
		
		UPDATE shelf_inventory 
		SET current_quantity = 3 
		WHERE product_id IN (1, 2, 3);
	`).Error; err != nil {
		return fmt.Errorf("failed to create low stock inventory: %w", err)
	}

	// 3. Create expiring products
	if err := db.Exec(`
		INSERT INTO shelf_batch_inventory (
			shelf_id, product_id, batch_code, quantity, 
			expiry_date, import_price, current_price, discount_percent
		) VALUES 
		(1, 1, 'EXP001', 10, CURRENT_DATE + INTERVAL '2 days', 15000, 20000, 0),
		(1, 2, 'EXP002', 15, CURRENT_DATE + INTERVAL '1 day', 12000, 18000, 0),
		(2, 3, 'EXP003', 8, CURRENT_DATE + INTERVAL '3 days', 8000, 12000, 0)
		ON CONFLICT (shelf_id, product_id, batch_code) DO NOTHING;
	`).Error; err != nil {
		return fmt.Errorf("failed to create expiring products: %w", err)
	}

	// 4. Create sample activities
	if err := db.Exec(`
		INSERT INTO activity_logs (activity_type, description, table_name, record_id, created_at) VALUES
		('PRODUCT_CREATED', 'Sản phẩm mới được tạo: Coca Cola 330ml (Mã: COCA001)', 'products', 1, CURRENT_TIMESTAMP - INTERVAL '2 hours'),
		('STOCK_TRANSFER', 'Chuyển hàng: Coca Cola 330ml từ kho Kho chính lên quầy Quầy nước giải khát (SL: 50)', 'stock_transfers', 1, CURRENT_TIMESTAMP - INTERVAL '1 hour'),
		('SALE_COMPLETED', 'Hóa đơn bán hàng: Nguyễn Văn A - Tổng tiền: 150000 VNĐ', 'sales_invoices', 1, CURRENT_TIMESTAMP - INTERVAL '30 minutes'),
		('LOW_STOCK_ALERT', 'Cảnh báo hết hàng: Coca Cola 330ml - Số lượng hiện tại: 3', 'shelf_inventory', 1, CURRENT_TIMESTAMP - INTERVAL '15 minutes'),
		('EXPIRY_ALERT', 'Cảnh báo hết hạn: Pepsi 330ml - Còn lại 2 ngày (Hạn: 2024-01-15)', 'shelf_batch_inventory', 1, CURRENT_TIMESTAMP - INTERVAL '10 minutes'),
		('PRODUCT_UPDATED', 'Sản phẩm được cập nhật: Pepsi 330ml (Mã: PEPSI001)', 'products', 2, CURRENT_TIMESTAMP - INTERVAL '45 minutes'),
		('STOCK_TRANSFER', 'Chuyển hàng: Pepsi 330ml từ kho Kho chính lên quầy Quầy nước giải khát (SL: 15)', 'stock_transfers', 2, CURRENT_TIMESTAMP - INTERVAL '30 minutes'),
		('SALE_COMPLETED', 'Hóa đơn bán hàng: Trần Thị B - Tổng tiền: 159500 VNĐ', 'sales_invoices', 2, CURRENT_TIMESTAMP - INTERVAL '20 minutes'),
		('SALE_COMPLETED', 'Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 88000 VNĐ', 'sales_invoices', 3, CURRENT_TIMESTAMP - INTERVAL '10 minutes')
		ON CONFLICT DO NOTHING;
	`).Error; err != nil {
		return fmt.Errorf("failed to create sample activities: %w", err)
	}

	// 5. Create today's sales for revenue
	if err := db.Exec(`
		INSERT INTO sales_invoices (customer_id, employee_id, invoice_date, subtotal, discount_amount, tax_amount, total_amount, payment_method, status) VALUES
		(1, 1, CURRENT_TIMESTAMP, 200000, 0, 20000, 220000, 'CASH', 'COMPLETED'),
		(2, 1, CURRENT_TIMESTAMP, 150000, 5000, 14500, 159500, 'CARD', 'COMPLETED'),
		(NULL, 1, CURRENT_TIMESTAMP, 80000, 0, 8000, 88000, 'CASH', 'COMPLETED')
		ON CONFLICT DO NOTHING;
	`).Error; err != nil {
		return fmt.Errorf("failed to create today's sales: %w", err)
	}

	// 6. Create sales invoice details
	if err := db.Exec(`
		INSERT INTO sales_invoice_details (invoice_id, product_id, quantity, unit_price, discount_percent, discount_amount, subtotal) VALUES
		(1, 1, 5, 20000, 0, 0, 100000),
		(1, 2, 3, 30000, 0, 0, 90000),
		(1, 3, 2, 5000, 0, 0, 10000),
		(2, 1, 3, 20000, 0, 0, 60000),
		(2, 2, 2, 30000, 0, 0, 60000),
		(2, 3, 6, 5000, 0, 0, 30000),
		(3, 1, 2, 20000, 0, 0, 40000),
		(3, 2, 1, 30000, 0, 0, 30000),
		(3, 3, 2, 5000, 0, 0, 10000)
		ON CONFLICT DO NOTHING;
	`).Error; err != nil {
		return fmt.Errorf("failed to create sales invoice details: %w", err)
	}

	log.Println("  ✓ Dashboard test data seeded")
	return nil
}
