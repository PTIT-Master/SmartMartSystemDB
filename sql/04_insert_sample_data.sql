-- =====================================================
-- SAMPLE DATA FOR SUPERMARKET RETAIL MANAGEMENT SYSTEM
-- =====================================================

SET search_path TO supermarket;

-- =====================================================
-- 1. INSERT WAREHOUSE DATA
-- =====================================================
INSERT INTO warehouse (warehouse_code, warehouse_name, location, capacity)
VALUES ('WH001', 'Kho chính', 'Tầng hầm B1', 10000);

-- =====================================================
-- 2. INSERT PRODUCT CATEGORIES
-- =====================================================
INSERT INTO product_categories (category_name, description) VALUES
('Văn phòng phẩm', 'Đồ dùng văn phòng, học tập'),
('Đồ gia dụng', 'Đồ dùng gia đình'),
('Đồ điện tử', 'Thiết bị điện tử tiêu dùng'),
('Đồ bếp', 'Dụng cụ nhà bếp'),
('Thực phẩm', 'Thực phẩm các loại'),
('Đồ uống', 'Nước giải khát, đồ uống các loại');

-- =====================================================
-- 3. INSERT POSITIONS
-- =====================================================
INSERT INTO positions (position_code, position_name, base_salary, hourly_rate) VALUES
('MGR', 'Quản lý', 15000000, 100000),
('SUP', 'Giám sát', 10000000, 70000),
('CASH', 'Thu ngân', 7000000, 50000),
('SALE', 'Nhân viên bán hàng', 6000000, 45000),
('STOCK', 'Nhân viên kho', 6500000, 48000);

-- =====================================================
-- 4. INSERT MEMBERSHIP LEVELS
-- =====================================================
INSERT INTO membership_levels (level_name, min_spending, discount_percentage, points_multiplier) VALUES
('Bronze', 0, 0, 1.0),
('Silver', 5000000, 3, 1.2),
('Gold', 20000000, 5, 1.5),
('Platinum', 50000000, 8, 2.0),
('Diamond', 100000000, 10, 2.5);

-- =====================================================
-- 5. INSERT DISCOUNT RULES FOR NEAR-EXPIRY PRODUCTS
-- =====================================================
INSERT INTO discount_rules (category_id, days_before_expiry, discount_percentage, rule_name) VALUES
(5, 5, 50, 'Thực phẩm khô - giảm 50%'),
(5, 1, 50, 'Rau quả - giảm 50%'),
(6, 7, 30, 'Đồ uống - giảm 30%'),
(6, 3, 50, 'Đồ uống - giảm 50%');

-- =====================================================
-- 6. INSERT SUPPLIERS
-- =====================================================
INSERT INTO suppliers (supplier_code, supplier_name, contact_person, phone, email, address) VALUES
('SUP001', 'Công ty TNHH Thực phẩm Sài Gòn', 'Nguyễn Văn A', '0901234567', 'contact@sgfood.vn', '123 Nguyễn Văn Cừ, Q5, TP.HCM'),
('SUP002', 'Công ty CP Điện tử Việt Nam', 'Trần Thị B', '0912345678', 'sales@vnelec.com', '456 Lý Thường Kiệt, Q10, TP.HCM'),
('SUP003', 'Công ty TNHH Văn phòng phẩm Á Châu', 'Lê Văn C', '0923456789', 'info@acoffice.vn', '789 Cách Mạng Tháng 8, Q3, TP.HCM'),
('SUP004', 'Công ty CP Đồ gia dụng Minh Long', 'Phạm Thị D', '0934567890', 'contact@minhlong.vn', '321 Võ Văn Tần, Q3, TP.HCM'),
('SUP005', 'Công ty TNHH Nước giải khát Tân Hiệp Phát', 'Hoàng Văn E', '0945678901', 'sales@thp.vn', '654 Quốc lộ 1A, Bình Dương');

-- =====================================================
-- 7. INSERT EMPLOYEES
-- =====================================================
INSERT INTO employees (employee_code, full_name, position_id, phone, email, hire_date) VALUES
('EMP001', 'Nguyễn Quản Lý', 1, '0901111111', 'manager@supermarket.vn', '2024-01-01'),
('EMP002', 'Trần Giám Sát', 2, '0902222222', 'supervisor@supermarket.vn', '2024-01-15'),
('EMP003', 'Lê Thu Ngân', 3, '0903333333', 'cashier1@supermarket.vn', '2024-02-01'),
('EMP004', 'Phạm Bán Hàng', 4, '0904444444', 'sales1@supermarket.vn', '2024-02-15'),
('EMP005', 'Hoàng Thủ Kho', 5, '0905555555', 'stock1@supermarket.vn', '2024-03-01');

-- =====================================================
-- 8. INSERT PRODUCTS
-- =====================================================
INSERT INTO products (product_code, product_name, category_id, supplier_id, unit, import_price, selling_price, shelf_life_days, low_stock_threshold) VALUES
-- Văn phòng phẩm
('VPP001', 'Bút bi Thiên Long', 1, 3, 'Cây', 3000, 5000, 365, 20),
('VPP002', 'Vở học sinh 96 trang', 1, 3, 'Quyển', 8000, 12000, 365, 30),
-- Đồ gia dụng
('GD001', 'Chảo chống dính 26cm', 2, 4, 'Cái', 150000, 250000, NULL, 5),
('GD002', 'Bộ nồi inox 3 món', 2, 4, 'Bộ', 350000, 550000, NULL, 3),
-- Đồ điện tử
('DT001', 'Tai nghe Bluetooth', 3, 2, 'Cái', 200000, 350000, NULL, 10),
('DT002', 'Sạc dự phòng 10000mAh', 3, 2, 'Cái', 180000, 300000, NULL, 8),
-- Thực phẩm
('TP001', 'Gạo ST25 5kg', 5, 1, 'Bao', 120000, 180000, 180, 10),
('TP002', 'Mì gói Hảo Hảo', 5, 1, 'Thùng', 85000, 115000, 180, 20),
-- Đồ uống
('DU001', 'Nước suối Aquafina 500ml', 6, 5, 'Thùng', 80000, 120000, 365, 15),
('DU002', 'Trà xanh không độ', 6, 5, 'Thùng', 140000, 200000, 180, 10);

-- =====================================================
-- 9. INSERT DISPLAY SHELVES
-- =====================================================
INSERT INTO display_shelves (shelf_code, shelf_name, category_id, location, max_capacity) VALUES
('SH001', 'Quầy văn phòng phẩm 1', 1, 'Khu A - Tầng 1', 500),
('SH002', 'Quầy đồ gia dụng 1', 2, 'Khu B - Tầng 1', 200),
('SH003', 'Quầy điện tử 1', 3, 'Khu C - Tầng 1', 300),
('SH004', 'Quầy thực phẩm khô', 5, 'Khu D - Tầng 1', 800),
('SH005', 'Quầy đồ uống', 6, 'Khu E - Tầng 1', 600);

-- =====================================================
-- 10. CONFIGURE SHELF LAYOUT
-- =====================================================
INSERT INTO shelf_layout (shelf_id, product_id, position_code, max_quantity) VALUES
-- Văn phòng phẩm
(1, 1, 'A1', 50),
(1, 2, 'A2', 40),
-- Đồ gia dụng
(2, 3, 'B1', 20),
(2, 4, 'B2', 15),
-- Đồ điện tử
(3, 5, 'C1', 30),
(3, 6, 'C2', 25),
-- Thực phẩm
(4, 7, 'D1', 30),
(4, 8, 'D2', 50),
-- Đồ uống
(5, 9, 'E1', 40),
(5, 10, 'E2', 35);

-- =====================================================
-- 11. INITIAL WAREHOUSE INVENTORY
-- =====================================================
INSERT INTO warehouse_inventory (product_id, batch_code, quantity, import_date, expiry_date, import_price) VALUES
(1, 'BATCH202401001', 200, '2024-01-15', NULL, 3000),
(2, 'BATCH202401002', 150, '2024-01-15', NULL, 8000),
(3, 'BATCH202402001', 50, '2024-02-01', NULL, 150000),
(4, 'BATCH202402002', 30, '2024-02-01', NULL, 350000),
(5, 'BATCH202403001', 100, '2024-03-01', NULL, 200000),
(6, 'BATCH202403002', 80, '2024-03-01', NULL, 180000),
(7, 'BATCH202404001', 100, '2024-04-01', '2024-10-01', 120000),
(8, 'BATCH202404002', 200, '2024-04-01', '2024-10-01', 85000),
(9, 'BATCH202405001', 150, '2024-05-01', '2025-05-01', 80000),
(10, 'BATCH202405002', 120, '2024-05-01', '2024-11-01', 140000);

-- =====================================================
-- 12. INSERT CUSTOMERS
-- =====================================================
INSERT INTO customers (customer_code, full_name, phone, email, membership_card_no, membership_level_id, registration_date) VALUES
('CUS001', 'Nguyễn Thị Hương', '0911111111', 'huong@email.com', 'CARD001', 1, '2024-01-01'),
('CUS002', 'Trần Văn Nam', '0922222222', 'nam@email.com', 'CARD002', 2, '2024-01-15'),
('CUS003', 'Lê Thị Mai', '0933333333', 'mai@email.com', 'CARD003', 1, '2024-02-01'),
('CUS004', 'Phạm Văn Đức', '0944444444', 'duc@email.com', 'CARD004', 3, '2024-02-15'),
('CUS005', 'Hoàng Thị Lan', '0955555555', 'lan@email.com', 'CARD005', 2, '2024-03-01');

-- =====================================================
-- 13. SAMPLE EMPLOYEE WORK HOURS (1 MONTH)
-- =====================================================
-- Generate work hours for the last 30 days
DO $$
DECLARE
    emp_id INTEGER;
    work_date DATE;
BEGIN
    FOR emp_id IN SELECT employee_id FROM employees
    LOOP
        FOR work_date IN SELECT generate_series(
            CURRENT_DATE - INTERVAL '30 days',
            CURRENT_DATE - INTERVAL '1 day',
            '1 day'::INTERVAL
        )::DATE
        LOOP
            -- Skip weekends
            IF EXTRACT(DOW FROM work_date) NOT IN (0, 6) THEN
                INSERT INTO employee_work_hours (
                    employee_id, 
                    work_date, 
                    check_in_time, 
                    check_out_time
                ) VALUES (
                    emp_id,
                    work_date,
                    '08:00:00'::TIME + (RANDOM() * INTERVAL '30 minutes'),
                    '17:00:00'::TIME + (RANDOM() * INTERVAL '60 minutes')
                );
            END IF;
        END LOOP;
    END LOOP;
END $$;

-- =====================================================
-- 14. SAMPLE PURCHASE ORDERS
-- =====================================================
INSERT INTO purchase_orders (order_no, supplier_id, employee_id, order_date, delivery_date, total_amount, status) VALUES
('PO202401001', 1, 1, '2024-01-10', '2024-01-15', 20500000, 'RECEIVED'),
('PO202402001', 2, 1, '2024-02-01', '2024-02-05', 38000000, 'RECEIVED'),
('PO202403001', 3, 2, '2024-03-01', '2024-03-05', 1700000, 'RECEIVED'),
('PO202404001', 4, 2, '2024-04-01', '2024-04-05', 25000000, 'RECEIVED'),
('PO202405001', 5, 1, '2024-05-01', '2024-05-05', 32000000, 'RECEIVED');

-- Purchase order details
INSERT INTO purchase_order_details (order_id, product_id, quantity, unit_price, subtotal) VALUES
-- Order 1
(1, 7, 100, 120000, 12000000),
(1, 8, 100, 85000, 8500000),
-- Order 2
(2, 5, 100, 200000, 20000000),
(2, 6, 100, 180000, 18000000),
-- Order 3
(3, 1, 200, 3000, 600000),
(3, 2, 150, 8000, 1200000),
-- Order 4
(4, 3, 50, 150000, 7500000),
(4, 4, 50, 350000, 17500000),
-- Order 5
(5, 9, 200, 80000, 16000000),
(5, 10, 100, 140000, 14000000);

-- =====================================================
-- 15. INITIAL SHELF INVENTORY (Transfer from warehouse)
-- =====================================================
-- Transfer some products to shelves
SELECT fn_restock_shelf(1, 1, 30, 5, 'BATCH202401001');
SELECT fn_restock_shelf(2, 1, 25, 5, 'BATCH202401002');
SELECT fn_restock_shelf(3, 2, 10, 5, 'BATCH202402001');
SELECT fn_restock_shelf(4, 2, 5, 5, 'BATCH202402002');
SELECT fn_restock_shelf(5, 3, 20, 5, 'BATCH202403001');
SELECT fn_restock_shelf(6, 3, 15, 5, 'BATCH202403002');
SELECT fn_restock_shelf(7, 4, 20, 5, 'BATCH202404001');
SELECT fn_restock_shelf(8, 4, 30, 5, 'BATCH202404002');
SELECT fn_restock_shelf(9, 5, 25, 5, 'BATCH202405001');
SELECT fn_restock_shelf(10, 5, 20, 5, 'BATCH202405002');

-- =====================================================
-- 16. SAMPLE SALES TRANSACTIONS (1 MONTH)
-- =====================================================
-- Generate sample sales for the last 30 days
DO $$
DECLARE
    sale_date DATE;
    transactions_per_day INTEGER;
    i INTEGER;
    emp_id INTEGER;
    cust_id INTEGER;
    prod_id INTEGER;
    qty INTEGER;
    invoice_result RECORD;
BEGIN
    FOR sale_date IN SELECT generate_series(
        CURRENT_DATE - INTERVAL '30 days',
        CURRENT_DATE - INTERVAL '1 day',
        '1 day'::INTERVAL
    )::DATE
    LOOP
        -- Random number of transactions per day (10-30)
        transactions_per_day := 10 + FLOOR(RANDOM() * 21);
        
        FOR i IN 1..transactions_per_day
        LOOP
            -- Random employee (cashier or sales)
            emp_id := (SELECT employee_id FROM employees 
                      WHERE position_id IN (3, 4) 
                      ORDER BY RANDOM() LIMIT 1);
            
            -- Random customer (70% chance of member, 30% walk-in)
            IF RANDOM() < 0.7 THEN
                cust_id := (SELECT customer_id FROM customers 
                           ORDER BY RANDOM() LIMIT 1);
            ELSE
                cust_id := NULL;
            END IF;
            
            -- Create invoice with 1-5 random items
            SELECT * INTO invoice_result FROM fn_process_sale(
                emp_id,
                cust_id,
                CASE WHEN RANDOM() < 0.5 THEN 'CASH' ELSE 'CARD' END,
                (
                    SELECT jsonb_agg(jsonb_build_object(
                        'product_id', p.product_id,
                        'quantity', LEAST(
                            1 + FLOOR(RANDOM() * 3)::INTEGER,
                            COALESCE(si.current_quantity, 0)
                        )
                    ))
                    FROM (
                        SELECT product_id 
                        FROM products 
                        ORDER BY RANDOM() 
                        LIMIT 1 + FLOOR(RANDOM() * 5)::INTEGER
                    ) p
                    LEFT JOIN shelf_inventory si ON p.product_id = si.product_id
                    WHERE COALESCE(si.current_quantity, 0) > 0
                )::JSONB
            );
            
            -- Update invoice date to match sale_date
            IF invoice_result.invoice_id IS NOT NULL THEN
                UPDATE sales_invoices 
                SET invoice_date = sale_date + (INTERVAL '8 hours' + RANDOM() * INTERVAL '12 hours')
                WHERE invoice_id = invoice_result.invoice_id;
                
                -- Restock if needed (30% chance)
                IF RANDOM() < 0.3 THEN
                    PERFORM fn_restock_shelf(
                        prod_id, 
                        (SELECT shelf_id FROM shelf_inventory 
                         WHERE product_id = prod_id AND current_quantity < 10 
                         LIMIT 1),
                        10,
                        5
                    )
                    FROM (
                        SELECT DISTINCT product_id as prod_id
                        FROM shelf_inventory 
                        WHERE current_quantity < 10
                        LIMIT 3
                    ) low_stock;
                END IF;
            END IF;
        END LOOP;
    END LOOP;
END $$;

-- =====================================================
-- 17. GRANT PERMISSIONS
-- =====================================================
GRANT ALL ON SCHEMA supermarket TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA supermarket TO postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA supermarket TO postgres;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA supermarket TO postgres;

-- =====================================================
-- 18. VERIFY DATA
-- =====================================================
-- Check sample data counts
SELECT 'Products' as entity, COUNT(*) as count FROM products
UNION ALL
SELECT 'Customers', COUNT(*) FROM customers
UNION ALL
SELECT 'Employees', COUNT(*) FROM employees
UNION ALL
SELECT 'Sales Invoices', COUNT(*) FROM sales_invoices
UNION ALL
SELECT 'Purchase Orders', COUNT(*) FROM purchase_orders
UNION ALL
SELECT 'Warehouse Stock', SUM(quantity) FROM warehouse_inventory
UNION ALL
SELECT 'Shelf Stock', SUM(current_quantity) FROM shelf_inventory;

-- Show dashboard summary
SELECT * FROM fn_dashboard_summary();
