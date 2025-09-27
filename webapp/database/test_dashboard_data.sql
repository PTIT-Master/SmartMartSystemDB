-- Test data để kiểm tra các tính năng dashboard
-- Chạy sau khi đã migrate và seed dữ liệu cơ bản

-- 1. Tạo một số sản phẩm sắp hết hàng
UPDATE products SET low_stock_threshold = 50 WHERE product_id IN (1, 2, 3);

-- Giảm số lượng trong kho và quầy để tạo cảnh báo hết hàng
UPDATE warehouse_inventory 
SET quantity = 5 
WHERE product_id IN (1, 2, 3);

UPDATE shelf_inventory 
SET current_quantity = 3 
WHERE product_id IN (1, 2, 3);

-- 2. Tạo sản phẩm sắp hết hạn
-- Thêm batch với ngày hết hạn gần
INSERT INTO shelf_batch_inventory (
    shelf_id, product_id, batch_code, quantity, 
    expiry_date, import_price, current_price, discount_percent
) VALUES 
(1, 1, 'EXP001', 10, CURRENT_DATE + INTERVAL '2 days', 15000, 20000, 0),
(1, 2, 'EXP002', 15, CURRENT_DATE + INTERVAL '1 day', 12000, 18000, 0),
(2, 3, 'EXP003', 8, CURRENT_DATE + INTERVAL '3 days', 8000, 12000, 0);

-- 3. Tạo một số hoạt động test
INSERT INTO activity_logs (activity_type, description, table_name, record_id, created_at) VALUES
('PRODUCT_CREATED', 'Sản phẩm mới được tạo: Coca Cola 330ml (Mã: COCA001)', 'products', 1, CURRENT_TIMESTAMP - INTERVAL '2 hours'),
('STOCK_TRANSFER', 'Chuyển hàng: Coca Cola 330ml từ kho Kho chính lên quầy Quầy nước giải khát (SL: 50)', 'stock_transfers', 1, CURRENT_TIMESTAMP - INTERVAL '1 hour'),
('SALE_COMPLETED', 'Hóa đơn bán hàng: Nguyễn Văn A - Tổng tiền: 150000 VNĐ', 'sales_invoices', 1, CURRENT_TIMESTAMP - INTERVAL '30 minutes'),
('LOW_STOCK_ALERT', 'Cảnh báo hết hàng: Coca Cola 330ml - Số lượng hiện tại: 3', 'shelf_inventory', 1, CURRENT_TIMESTAMP - INTERVAL '15 minutes'),
('EXPIRY_ALERT', 'Cảnh báo hết hạn: Pepsi 330ml - Còn lại 2 ngày (Hạn: 2024-01-15)', 'shelf_batch_inventory', 1, CURRENT_TIMESTAMP - INTERVAL '10 minutes');

-- 4. Tạo thêm một số hóa đơn bán hàng để có doanh thu hôm nay
INSERT INTO sales_invoices (customer_id, employee_id, invoice_date, subtotal, discount_amount, tax_amount, total_amount, payment_method, status) VALUES
(1, 1, CURRENT_TIMESTAMP, 200000, 0, 20000, 220000, 'CASH', 'COMPLETED'),
(2, 1, CURRENT_TIMESTAMP, 150000, 5000, 14500, 159500, 'CARD', 'COMPLETED'),
(NULL, 1, CURRENT_TIMESTAMP, 80000, 0, 8000, 88000, 'CASH', 'COMPLETED');

-- Thêm chi tiết hóa đơn
INSERT INTO sales_invoice_details (invoice_id, product_id, quantity, unit_price, discount_percent, discount_amount, subtotal) VALUES
(1, 1, 5, 20000, 0, 0, 100000),
(1, 2, 3, 30000, 0, 0, 90000),
(1, 3, 2, 5000, 0, 0, 10000),
(2, 1, 3, 20000, 0, 0, 60000),
(2, 2, 2, 30000, 0, 0, 60000),
(2, 3, 6, 5000, 0, 0, 30000),
(3, 1, 2, 20000, 0, 0, 40000),
(3, 2, 1, 30000, 0, 0, 30000),
(3, 3, 2, 5000, 0, 0, 10000);

-- 5. Tạo thêm một số chuyển hàng để có hoạt động
INSERT INTO stock_transfers (product_id, from_warehouse_id, to_shelf_id, quantity, transfer_date, employee_id, status) VALUES
(1, 1, 1, 20, CURRENT_TIMESTAMP - INTERVAL '1 hour', 1, 'COMPLETED'),
(2, 1, 1, 15, CURRENT_TIMESTAMP - INTERVAL '45 minutes', 1, 'COMPLETED'),
(3, 1, 2, 10, CURRENT_TIMESTAMP - INTERVAL '30 minutes', 1, 'COMPLETED');

-- 6. Cập nhật số lượng kho sau khi chuyển hàng
UPDATE warehouse_inventory 
SET quantity = quantity - 20 
WHERE product_id = 1 AND warehouse_id = 1;

UPDATE warehouse_inventory 
SET quantity = quantity - 15 
WHERE product_id = 2 AND warehouse_id = 1;

UPDATE warehouse_inventory 
SET quantity = quantity - 10 
WHERE product_id = 3 AND warehouse_id = 1;

-- 7. Cập nhật số lượng quầy sau khi chuyển hàng
UPDATE shelf_inventory 
SET current_quantity = current_quantity + 20 
WHERE product_id = 1 AND shelf_id = 1;

UPDATE shelf_inventory 
SET current_quantity = current_quantity + 15 
WHERE product_id = 2 AND shelf_id = 1;

UPDATE shelf_inventory 
SET current_quantity = current_quantity + 10 
WHERE product_id = 3 AND shelf_id = 2;

-- 8. Tạo thêm một số hoạt động khác
INSERT INTO activity_logs (activity_type, description, table_name, record_id, created_at) VALUES
('PRODUCT_UPDATED', 'Sản phẩm được cập nhật: Pepsi 330ml (Mã: PEPSI001)', 'products', 2, CURRENT_TIMESTAMP - INTERVAL '45 minutes'),
('STOCK_TRANSFER', 'Chuyển hàng: Pepsi 330ml từ kho Kho chính lên quầy Quầy nước giải khát (SL: 15)', 'stock_transfers', 2, CURRENT_TIMESTAMP - INTERVAL '30 minutes'),
('SALE_COMPLETED', 'Hóa đơn bán hàng: Trần Thị B - Tổng tiền: 159500 VNĐ', 'sales_invoices', 2, CURRENT_TIMESTAMP - INTERVAL '20 minutes'),
('SALE_COMPLETED', 'Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 88000 VNĐ', 'sales_invoices', 3, CURRENT_TIMESTAMP - INTERVAL '10 minutes');

-- Kiểm tra kết quả
SELECT 'Low Stock Products:' as info;
SELECT * FROM supermarket.v_low_stock_products LIMIT 5;

SELECT 'Expiring Products:' as info;
SELECT * FROM supermarket.v_expiring_products LIMIT 5;

SELECT 'Recent Activities:' as info;
SELECT 
    TO_CHAR(created_at, 'DD/MM/YYYY HH24:MI') as timestamp,
    CASE 
        WHEN activity_type = 'PRODUCT_CREATED' THEN 'Sản phẩm'
        WHEN activity_type = 'PRODUCT_UPDATED' THEN 'Sản phẩm'
        WHEN activity_type = 'STOCK_TRANSFER' THEN 'Kho hàng'
        WHEN activity_type = 'SALE_COMPLETED' THEN 'Bán hàng'
        WHEN activity_type = 'LOW_STOCK_ALERT' THEN 'Cảnh báo'
        WHEN activity_type = 'EXPIRY_ALERT' THEN 'Cảnh báo'
        ELSE 'Khác'
    END as type,
    description,
    COALESCE(user_name, 'Hệ thống') as user
FROM supermarket.activity_logs
ORDER BY created_at DESC
LIMIT 10;
