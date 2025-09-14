-- BATCH TRACKING SYSTEM - SQL EXAMPLE
-- Demonstrates the dual-layer tracking system in action

-- ==========================================
-- 1. NHẬP HÀNG VÀO KHO (WarehouseInventory)
-- ==========================================
INSERT INTO warehouse_inventory 
(warehouse_id, product_id, batch_code, quantity, import_date, expiry_date, import_price) 
VALUES 
-- Batch A: Sữa TH - HSD sớm
(1, 101, 'MILK_TH_A001', 100, '2024-12-01', '2024-12-15', 12000),
-- Batch B: Sữa TH - HSD muộn hơn  
(1, 101, 'MILK_TH_B002', 150, '2024-12-01', '2024-12-22', 12000);

-- ==========================================
-- 2. CHUYỂN HÀNG LÊN KỆ (StockTransfer)
-- ==========================================
INSERT INTO stock_transfers 
(transfer_code, product_id, from_warehouse_id, to_shelf_id, quantity, employee_id, 
 batch_code, expiry_date, import_price, selling_price)
VALUES 
-- Chuyển 50 chai từ Batch A lên kệ A1
('TRF_001', 101, 1, 1, 50, 1, 'MILK_TH_A001', '2024-12-15', 12000, 15000),
-- Chuyển 80 chai từ Batch B lên kệ A1
('TRF_002', 101, 1, 1, 80, 1, 'MILK_TH_B002', '2024-12-22', 12000, 15000);

-- ==========================================
-- 3. TỰ ĐỘNG TẠO SHELF_BATCH_INVENTORY 
-- ==========================================
-- Trigger sẽ tự động tạo từ StockTransfer
INSERT INTO shelf_batch_inventory 
(shelf_id, product_id, batch_code, quantity, expiry_date, stocked_date, 
 import_price, current_price, discount_percent, is_near_expiry)
SELECT 
    to_shelf_id,
    product_id,
    batch_code,
    quantity,
    expiry_date,
    transfer_date,
    import_price,
    selling_price,
    0,              -- No discount initially
    false           -- Not near expiry yet
FROM stock_transfers 
WHERE transfer_code IN ('TRF_001', 'TRF_002');

-- ==========================================
-- 4. CẬP NHẬT SHELF_INVENTORY SUMMARY
-- ==========================================
INSERT INTO shelf_inventory 
(shelf_id, product_id, current_quantity, near_expiry_quantity, expired_quantity,
 earliest_expiry_date, latest_expiry_date, last_restocked)
SELECT 
    shelf_id,
    product_id,
    SUM(quantity) as current_quantity,
    SUM(CASE WHEN DATEDIFF(expiry_date, NOW()) <= 7 AND DATEDIFF(expiry_date, NOW()) > 0 
             THEN quantity ELSE 0 END) as near_expiry_quantity,
    SUM(CASE WHEN expiry_date <= NOW() 
             THEN quantity ELSE 0 END) as expired_quantity,
    MIN(expiry_date) as earliest_expiry_date,
    MAX(expiry_date) as latest_expiry_date,
    MAX(stocked_date) as last_restocked
FROM shelf_batch_inventory 
WHERE shelf_id = 1 AND product_id = 101
GROUP BY shelf_id, product_id
ON DUPLICATE KEY UPDATE
    current_quantity = VALUES(current_quantity),
    near_expiry_quantity = VALUES(near_expiry_quantity),
    expired_quantity = VALUES(expired_quantity),
    earliest_expiry_date = VALUES(earliest_expiry_date),
    latest_expiry_date = VALUES(latest_expiry_date),
    last_restocked = VALUES(last_restocked);

-- ==========================================
-- 5. AUTO-DISCOUNT CHO BATCH SẮP HẾT HẠN
-- ==========================================
-- Batch A sẽ được discount 20% khi còn 7 ngày
UPDATE shelf_batch_inventory 
SET 
    discount_percent = 20.0,
    current_price = import_price * 0.8,
    is_near_expiry = true
WHERE DATEDIFF(expiry_date, NOW()) <= 7 
  AND DATEDIFF(expiry_date, NOW()) > 0
  AND discount_percent = 0;

-- ==========================================
-- 6. FIFO SELLING LOGIC
-- ==========================================
-- Bán hàng theo thứ tự HSD sớm nhất trước
SELECT 
    shelf_batch_id,
    batch_code,
    quantity,
    current_price,
    discount_percent,
    expiry_date,
    DATEDIFF(expiry_date, NOW()) as days_until_expiry
FROM shelf_batch_inventory 
WHERE shelf_id = 1 
  AND product_id = 101 
  AND quantity > 0
  AND expiry_date > NOW()  -- Chỉ bán hàng chưa hết hạn
ORDER BY 
    expiry_date ASC,        -- HSD sớm nhất trước
    stocked_date ASC;       -- Hàng cũ trước (FIFO)

-- ==========================================
-- 7. BÁO CÁO VÀ CẢNH BÁO
-- ==========================================

-- Hàng sắp hết hạn cần discount
SELECT 
    s.shelf_code,
    p.product_name,
    sbi.batch_code,
    sbi.quantity,
    sbi.expiry_date,
    sbi.current_price,
    sbi.discount_percent,
    DATEDIFF(sbi.expiry_date, NOW()) as days_left
FROM shelf_batch_inventory sbi
JOIN display_shelves s ON sbi.shelf_id = s.shelf_id
JOIN products p ON sbi.product_id = p.product_id
WHERE sbi.is_near_expiry = true
ORDER BY sbi.expiry_date ASC;

-- Hàng đã hết hạn cần loại bỏ
SELECT 
    s.shelf_code,
    p.product_name,
    sbi.batch_code,
    sbi.quantity,
    sbi.expiry_date,
    DATEDIFF(NOW(), sbi.expiry_date) as days_expired
FROM shelf_batch_inventory sbi
JOIN display_shelves s ON sbi.shelf_id = s.shelf_id
JOIN products p ON sbi.product_id = p.product_id
WHERE sbi.expiry_date <= NOW()
ORDER BY sbi.expiry_date ASC;

-- Summary báo cáo theo kệ
SELECT 
    s.shelf_code,
    p.product_name,
    si.current_quantity,
    si.near_expiry_quantity,
    si.expired_quantity,
    (si.current_quantity - si.near_expiry_quantity - si.expired_quantity) as healthy_quantity,
    si.earliest_expiry_date,
    si.latest_expiry_date
FROM shelf_inventory si
JOIN display_shelves s ON si.shelf_id = s.shelf_id  
JOIN products p ON si.product_id = p.product_id
WHERE si.current_quantity > 0;
