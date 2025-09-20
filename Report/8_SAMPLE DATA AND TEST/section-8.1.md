# 8.1. Kịch bản Dữ liệu Mẫu

## 8.1.1. Dữ liệu 1 tháng hoạt động siêu thị

### Chiến lược tạo dữ liệu mẫu

Để mô phỏng hoạt động thực tế của siêu thị trong 1 tháng (tháng 12/2024), chúng ta thiết kế kịch bản dữ liệu bao gồm:

- **Sản phẩm đa dạng**: 200+ sản phẩm thuộc 8 chủng loại khác nhau
- **Hoạt động nhập hàng**: 15-20 đơn nhập hàng từ các nhà cung cấp
- **Hoạt động bán hàng**: 800-1000 hóa đơn bán lẻ trong tháng
- **Quản lý nhân sự**: 25 nhân viên với các vị trí khác nhau
- **Khách hàng thành viên**: 300 khách hàng với các level membership
- **Vận hành kho-quầy**: Chuyển hàng liên tục từ kho lên quầy

### Script tạo dữ liệu Master

```sql
-- ===== MASTER DATA =====

-- 1. Product Categories
INSERT INTO supermarket.product_categories (category_name, description) VALUES
('Thực phẩm tươi sống', 'Rau củ quả, thịt cá, trứng sữa'),
('Thực phẩm đóng hộp', 'Đồ hộp, mì gói, nước mắm'),
('Đồ uống', 'Nước ngọt, bia rượu, trà cà phê'),
('Văn phòng phẩm', 'Bút viết, giấy in, dụng cụ học tập'),
('Đồ gia dụng', 'Chảo nồi, dao kéo, dụng cụ nhà bếp'),
('Đồ điện tử', 'Điện thoại, máy tính, thiết bị điện'),
('Chăm sóc cá nhân', 'Dầu gội, kem đánh răng, mỹ phẩm'),
('Đồ chơi trẻ em', 'Xe đạp, búp bê, lego, board games');

-- 2. Membership Levels
INSERT INTO supermarket.membership_levels (level_name, min_spending, discount_percentage, points_multiplier) VALUES
('Bronze', 0, 0, 1.0),
('Silver', 5000000, 2, 1.2),
('Gold', 15000000, 5, 1.5),
('Diamond', 50000000, 8, 2.0);

-- 3. Positions
INSERT INTO supermarket.positions (position_code, position_name, base_salary, hourly_rate) VALUES
('MAN001', 'Quản lý cửa hàng', 15000000, 150000),
('SUP001', 'Giám sát ca', 8000000, 100000),
('CSH001', 'Thu ngân', 5000000, 60000),
('STF001', 'Nhân viên bán hàng', 4500000, 55000),
('WHK001', 'Thủ kho', 6000000, 70000),
('CLE001', 'Nhân viên vệ sinh', 4000000, 50000),
('SEC001', 'Bảo vệ', 4200000, 52000);

-- 4. Suppliers
INSERT INTO supermarket.suppliers (supplier_code, supplier_name, contact_person, phone, email, address, tax_code) VALUES
('SUP001', 'Công ty TNHH Thực phẩm Sạch Việt', 'Nguyễn Văn A', '0901234567', 'contact@thucphamsach.vn', 'Quận 1, TP.HCM', '0123456789'),
('SUP002', 'Tập đoàn Đồ uống Refresh', 'Trần Thị B', '0907654321', 'sales@refresh.vn', 'Quận Bình Thạnh, TP.HCM', '0987654321'),
('SUP003', 'Công ty CP Văn phòng phẩm Thiên Long', 'Lê Văn C', '0912345678', 'b2b@thienlong.vn', 'Quận 3, TP.HCM', '0112233445'),
('SUP004', 'Nhà phân phối Điện tử Vạn Phát', 'Phạm Thị D', '0923456789', 'wholesale@vanphat.com', 'Quận 7, TP.HCM', '0556677889'),
('SUP005', 'Công ty Gia dụng Nhà Đẹp', 'Hoàng Văn E', '0934567890', 'orders@nhadep.vn', 'Quận Tân Bình, TP.HCM', '0334455667'),
('SUP006', 'Tổng đại lý Mỹ phẩm Làm Đẹp', 'Võ Thị F', '0945678901', 'supplier@lamdep.com', 'Quận 10, TP.HCM', '0778899001'),
('SUP007', 'Công ty Đồ chơi Tuổi Thơ', 'Đặng Văn G', '0956789012', 'business@tuoitho.vn', 'Quận Gò Vấp, TP.HCM', '0445566778');

-- 5. Warehouse
INSERT INTO supermarket.warehouse (warehouse_code, warehouse_name, location, manager_name, capacity) VALUES
('WH001', 'Kho chính', 'Tầng hầm B1', 'Nguyễn Quản Kho', 10000);

-- 6. Display Shelves (phân theo category)
INSERT INTO supermarket.display_shelves (shelf_code, shelf_name, category_id, location, max_capacity) VALUES
-- Thực phẩm tươi sống
('SHF-FRESH-01', 'Quầy rau củ quả', 1, 'Khu A1', 500),
('SHF-FRESH-02', 'Quầy thịt cá', 1, 'Khu A2', 300),
('SHF-FRESH-03', 'Quầy sữa trứng', 1, 'Khu A3', 400),

-- Thực phẩm đóng hộp  
('SHF-CAN-01', 'Quầy đồ hộp', 2, 'Khu B1', 600),
('SHF-CAN-02', 'Quầy mì gói', 2, 'Khu B2', 800),

-- Đồ uống
('SHF-BEV-01', 'Quầy nước ngọt', 3, 'Khu C1', 700),
('SHF-BEV-02', 'Quầy bia rượu', 3, 'Khu C2', 400),

-- Văn phòng phẩm
('SHF-OFF-01', 'Quầy bút viết', 4, 'Khu D1', 300),
('SHF-OFF-02', 'Quầy giấy tờ', 4, 'Khu D2', 250),

-- Đồ gia dụng
('SHF-KIT-01', 'Quầy chảo nồi', 5, 'Khu E1', 200),
('SHF-KIT-02', 'Quầy dao kéo', 5, 'Khu E2', 150),

-- Đồ điện tử
('SHF-ELE-01', 'Quầy điện thoại', 6, 'Khu F1', 100),
('SHF-ELE-02', 'Quầy phụ kiện điện tử', 6, 'Khu F2', 200),

-- Chăm sóc cá nhân
('SHF-PER-01', 'Quầy dầu gội sữa tắm', 7, 'Khu G1', 400),
('SHF-PER-02', 'Quầy mỹ phẩm', 7, 'Khu G2', 300),

-- Đồ chơi trẻ em
('SHF-TOY-01', 'Quầy đồ chơi', 8, 'Khu H1', 250);
```

### Script tạo sản phẩm đa dạng

```sql
-- ===== PRODUCTS =====

-- Thực phẩm tươi sống (Category 1)
INSERT INTO supermarket.products (product_code, product_name, category_id, supplier_id, unit, import_price, selling_price, shelf_life_days, barcode) VALUES
('FRESH-001', 'Rau cải ngọt', 1, 1, 'bó', 8000, 12000, 3, '8934567890001'),
('FRESH-002', 'Cà rót', 1, 1, 'kg', 15000, 22000, 5, '8934567890002'),
('FRESH-003', 'Thịt ba chỉ heo', 1, 1, 'kg', 120000, 180000, 2, '8934567890003'),
('FRESH-004', 'Cá thu', 1, 1, 'kg', 80000, 120000, 1, '8934567890004'),
('FRESH-005', 'Trứng gà', 1, 1, 'vỉ', 25000, 35000, 14, '8934567890005'),
('FRESH-006', 'Sữa tươi TH', 1, 1, 'hộp', 18000, 25000, 7, '8934567890006'),
('FRESH-007', 'Chuối tiêu', 1, 1, 'nải', 20000, 30000, 7, '8934567890007'),
('FRESH-008', 'Táo Fuji', 1, 1, 'kg', 60000, 90000, 14, '8934567890008'),

-- Thực phẩm đóng hộp (Category 2)  
('CAN-001', 'Mì tôm Hảo Hảo', 2, 1, 'thùng', 180000, 240000, 365, '8934567890009'),
('CAN-002', 'Nước mắm Nam Ngư', 2, 1, 'chai', 45000, 65000, 730, '8934567890010'),
('CAN-003', 'Dầu ăn Simply', 2, 1, 'chai', 35000, 50000, 365, '8934567890011'),
('CAN-004', 'Gạo ST25', 2, 1, 'kg', 35000, 50000, 180, '8934567890012'),
('CAN-005', 'Thịt hộp Spam', 2, 1, 'hộp', 65000, 95000, 1095, '8934567890013'),

-- Đồ uống (Category 3)
('BEV-001', 'Coca Cola', 3, 2, 'lon', 8000, 12000, 180, '8934567890014'),
('BEV-002', 'Bia Saigon Special', 3, 2, 'lon', 12000, 18000, 120, '8934567890015'),
('BEV-003', 'Nước suối Lavie', 3, 2, 'chai', 3000, 5000, 365, '8934567890016'),
('BEV-004', 'Trà xanh C2', 3, 2, 'chai', 8000, 12000, 90, '8934567890017'),
('BEV-005', 'Cà phê Nescafe', 3, 2, 'gói', 120000, 180000, 730, '8934567890018'),

-- Văn phòng phẩm (Category 4)
('OFF-001', 'Bút bi Thiên Long', 4, 3, 'cây', 3000, 5000, NULL, '8934567890019'),
('OFF-002', 'Vở 4 ô li', 4, 3, 'quyển', 8000, 12000, NULL, '8934567890020'),
('OFF-003', 'Giấy A4 Double A', 4, 3, 'ream', 85000, 120000, NULL, '8934567890021'),
('OFF-004', 'Bút chì 2B', 4, 3, 'cây', 2000, 3000, NULL, '8934567890022'),

-- Đồ gia dụng (Category 5)
('KIT-001', 'Chảo chống dính Elmich', 5, 5, 'cái', 250000, 380000, NULL, '8934567890023'),
('KIT-002', 'Dao thái Sunhouse', 5, 5, 'cây', 45000, 65000, NULL, '8934567890024'),
('KIT-003', 'Nồi cơm điện Sharp', 5, 5, 'cái', 800000, 1200000, NULL, '8934567890025'),

-- Đồ điện tử (Category 6)  
('ELE-001', 'iPhone 15', 6, 4, 'cái', 18000000, 25000000, NULL, '8934567890026'),
('ELE-002', 'Tai nghe AirPods', 6, 4, 'cái', 3500000, 5000000, NULL, '8934567890027'),
('ELE-003', 'Cáp sạc Lightning', 6, 4, 'cái', 150000, 250000, NULL, '8934567890028'),

-- Chăm sóc cá nhân (Category 7)
('PER-001', 'Dầu gội Head & Shoulders', 7, 6, 'chai', 65000, 95000, 1095, '8934567890029'),
('PER-002', 'Kem đánh răng Close Up', 7, 6, 'tuýp', 25000, 35000, 1095, '8934567890030'),
('PER-003', 'Son môi MAC', 7, 6, 'cây', 450000, 650000, 1095, '8934567890031'),

-- Đồ chơi trẻ em (Category 8)
('TOY-001', 'Xe đạp trẻ em', 8, 7, 'cái', 1200000, 1800000, NULL, '8934567890032'),
('TOY-002', 'Búp bê Barbie', 8, 7, 'cái', 250000, 380000, NULL, '8934567890033'),
('TOY-003', 'Lego Creator', 8, 7, 'hộp', 800000, 1200000, NULL, '8934567890034');
```

### Script tạo nhân viên và khách hàng

```sql
-- ===== EMPLOYEES =====
INSERT INTO supermarket.employees (employee_code, full_name, position_id, phone, email, id_card, bank_account) VALUES
-- Management
('EMP001', 'Nguyễn Văn Quản Lý', 1, '0901111111', 'manager@supermarket.vn', '123456789', '1234567890'),
('EMP002', 'Trần Thị Giám Sát A', 2, '0901111112', 'supervisor.a@supermarket.vn', '123456790', '1234567891'),
('EMP003', 'Lê Văn Giám Sát B', 2, '0901111113', 'supervisor.b@supermarket.vn', '123456791', '1234567892'),

-- Cashiers  
('EMP004', 'Phạm Thị Thu Ngân 1', 3, '0901111114', 'cashier1@supermarket.vn', '123456792', '1234567893'),
('EMP005', 'Hoàng Văn Thu Ngân 2', 3, '0901111115', 'cashier2@supermarket.vn', '123456793', '1234567894'),
('EMP006', 'Võ Thị Thu Ngân 3', 3, '0901111116', 'cashier3@supermarket.vn', '123456794', '1234567895'),
('EMP007', 'Đặng Văn Thu Ngân 4', 3, '0901111117', 'cashier4@supermarket.vn', '123456795', '1234567896'),

-- Staff
('EMP008', 'Nguyễn Thị Nhân Viên 1', 4, '0901111118', 'staff1@supermarket.vn', '123456796', '1234567897'),
('EMP009', 'Trần Văn Nhân Viên 2', 4, '0901111119', 'staff2@supermarket.vn', '123456797', '1234567898'),
('EMP010', 'Lê Thị Nhân Viên 3', 4, '0901111120', 'staff3@supermarket.vn', '123456798', '1234567899'),
('EMP011', 'Phạm Văn Nhân Viên 4', 4, '0901111121', 'staff4@supermarket.vn', '123456799', '1234567900'),
('EMP012', 'Hoàng Thị Nhân Viên 5', 4, '0901111122', 'staff5@supermarket.vn', '123456800', '1234567901'),

-- Warehouse
('EMP013', 'Võ Văn Thủ Kho 1', 5, '0901111123', 'warehouse1@supermarket.vn', '123456801', '1234567902'),
('EMP014', 'Đặng Thị Thủ Kho 2', 5, '0901111124', 'warehouse2@supermarket.vn', '123456802', '1234567903'),

-- Cleaning & Security
('EMP015', 'Nguyễn Văn Vệ Sinh 1', 6, '0901111125', NULL, '123456803', '1234567904'),
('EMP016', 'Trần Thị Vệ Sinh 2', 6, '0901111126', NULL, '123456804', '1234567905'),
('EMP017', 'Lê Văn Bảo Vệ 1', 7, '0901111127', NULL, '123456805', '1234567906'),
('EMP018', 'Phạm Thị Bảo Vệ 2', 7, '0901111128', NULL, '123456806', '1234567907');

-- ===== CUSTOMERS =====
INSERT INTO supermarket.customers (customer_code, full_name, phone, email, address, membership_card_no, membership_level_id) VALUES
-- Bronze customers (most customers)
('CUS001', 'Nguyễn Văn Khách 1', '0911111111', 'customer1@email.com', 'Quận 1, TP.HCM', 'MEMBER0001', 1),
('CUS002', 'Trần Thị Khách 2', '0911111112', 'customer2@email.com', 'Quận 2, TP.HCM', 'MEMBER0002', 1),
('CUS003', 'Lê Văn Khách 3', '0911111113', 'customer3@email.com', 'Quận 3, TP.HCM', 'MEMBER0003', 1),
-- ... (more bronze customers)

-- Silver customers (some spending)
('CUS050', 'Phạm Thị Khách 50', '0911111150', 'customer50@email.com', 'Quận 7, TP.HCM', 'MEMBER0050', 2),
('CUS051', 'Hoàng Văn Khách 51', '0911111151', 'customer51@email.com', 'Quận 8, TP.HCM', 'MEMBER0051', 2),

-- Gold customers (good spending)  
('CUS080', 'Võ Thị Khách 80', '0911111180', 'customer80@email.com', 'Quận Bình Thạnh, TP.HCM', 'MEMBER0080', 3),
('CUS081', 'Đặng Văn Khách 81', '0911111181', 'customer81@email.com', 'Quận Tân Bình, TP.HCM', 'MEMBER0081', 3),

-- Diamond customers (VIP)
('CUS090', 'Nguyễn Thị VIP 1', '0911111190', 'vip1@email.com', 'Quận 1, TP.HCM', 'MEMBER0090', 4),
('CUS091', 'Trần Văn VIP 2', '0911111191', 'vip2@email.com', 'Quận 3, TP.HCM', 'MEMBER0091', 4);
```

## 8.1.2. Các case đặc biệt để test

### Case 1: Hàng sắp hết hạn

```sql
-- Tạo warehouse inventory với sản phẩm sắp hết hạn (2-3 ngày nữa)
INSERT INTO supermarket.warehouse_inventory (warehouse_id, product_id, batch_code, quantity, import_date, expiry_date, import_price) VALUES
-- Rau cải sắp hết hạn (2 ngày nữa)
(1, 1, 'BATCH-FRESH-001-001', 50, '2024-12-18', '2024-12-22', 8000),
-- Thịt ba chỉ sắp hết hạn (1 ngày nữa) 
(1, 3, 'BATCH-FRESH-003-001', 20, '2024-12-19', '2024-12-21', 120000),
-- Trứng gà sắp hết hạn (3 ngày nữa)
(1, 5, 'BATCH-FRESH-005-001', 30, '2024-12-17', '2024-12-23', 25000),

-- Tạo discount rules cho expiry discounting
INSERT INTO supermarket.discount_rules (category_id, days_before_expiry, discount_percentage, rule_name) VALUES
-- Thực phẩm tươi sống giảm 50% khi còn 3 ngày
(1, 3, 50, 'Fresh food 50% off when 3 days left'),
-- Thực phẩm tươi sống giảm 70% khi còn 1 ngày  
(1, 1, 70, 'Fresh food 70% off when 1 day left');
```

### Case 2: Quầy đầy/kho hết

```sql
-- Setup shelf layout with max quantities
INSERT INTO supermarket.shelf_layout (shelf_id, product_id, position_code, max_quantity) VALUES
-- Quầy rau củ - rau cải chỉ chứa được 30 bó
(1, 1, 'A1-001', 30),
-- Quầy thịt cá - thịt ba chỉ chỉ chứa được 15 kg
(2, 3, 'A2-001', 15);

-- Tạo shelf inventory gần đầy
INSERT INTO supermarket.shelf_inventory (shelf_id, product_id, current_quantity) VALUES
-- Rau cải gần đầy quầy (28/30)
(1, 1, 28),
-- Thịt ba chỉ đầy quầy (15/15) 
(2, 3, 15);

-- Case kho hết nhưng quầy còn
INSERT INTO supermarket.warehouse_inventory (warehouse_id, product_id, batch_code, quantity, import_date, expiry_date, import_price) VALUES
-- Cà rót trong kho = 0 (sẽ không insert - để test case hết kho)
-- Shelf inventory vẫn còn cà rót
INSERT INTO supermarket.shelf_inventory (shelf_id, product_id, current_quantity) VALUES
(1, 2, 12); -- Quầy còn 12 kg cà rót
```

### Case 3: Khách hàng nâng cấp membership

```sql
-- Customer gần đạt ngưỡng Silver (5,000,000)
UPDATE supermarket.customers 
SET total_spending = 4800000 
WHERE customer_code = 'CUS010';

-- Customer gần đạt ngưỡng Gold (15,000,000)
UPDATE supermarket.customers 
SET total_spending = 14500000 
WHERE customer_code = 'CUS030';

-- Customer gần đạt ngưỡng Diamond (50,000,000)
UPDATE supermarket.customers 
SET total_spending = 48000000 
WHERE customer_code = 'CUS070';
```

### Case 4: Nhân viên làm thêm giờ

```sql
-- Employee work hours với overtime scenarios
INSERT INTO supermarket.employee_work_hours (employee_id, work_date, check_in_time, check_out_time) VALUES
-- Manager làm việc bình thường 8h
(1, '2024-12-20', '2024-12-20 08:00:00', '2024-12-20 17:00:00'),

-- Thu ngân làm ca đêm 10h
(4, '2024-12-20', '2024-12-20 18:00:00', '2024-12-21 04:00:00'), 

-- Nhân viên bán hàng làm thêm giờ 12h
(8, '2024-12-20', '2024-12-20 06:00:00', '2024-12-20 18:00:00'),

-- Thủ kho làm ca sáng 6h
(13, '2024-12-20', '2024-12-20 05:00:00', '2024-12-20 11:00:00'),

-- Bảo vệ làm ca đêm 12h
(17, '2024-12-20', '2024-12-20 20:00:00', '2024-12-21 08:00:00');
```

### Case 5: Batch tracking và FIFO

```sql
-- Tạo nhiều batch cho cùng sản phẩm để test FIFO
INSERT INTO supermarket.warehouse_inventory (warehouse_id, product_id, batch_code, quantity, import_date, expiry_date, import_price) VALUES
-- Mì tôm Hảo Hảo - batch cũ (should be picked first by FIFO)
(1, 9, 'BATCH-CAN-001-OLD', 100, '2024-11-15', '2025-11-15', 180000),
-- Mì tôm Hảo Hảo - batch mới 
(1, 9, 'BATCH-CAN-001-NEW', 150, '2024-12-10', '2025-12-10', 185000),
-- Mì tôm Hảo Hảo - batch newest
(1, 9, 'BATCH-CAN-001-NEWEST', 200, '2024-12-18', '2025-12-18', 190000);
```

### Case 6: Sales transactions mô phỏng thực tế

```sql
-- Tạo các giao dịch bán hàng điển hình trong 1 tháng
-- Morning rush (7-9 AM) - breakfast items
-- Lunch time (11-1 PM) - quick meals  
-- Evening (5-8 PM) - family groceries
-- Weekend (full day) - bulk shopping

-- Sample morning transaction
INSERT INTO supermarket.sales_invoices (invoice_no, customer_id, employee_id, payment_method) VALUES
('INV-20241220-000001', 1, 4, 'CASH');

INSERT INTO supermarket.sales_invoice_details (invoice_id, product_id, quantity, unit_price) VALUES
(1, 6, 2, 25000), -- 2 hộp sữa tươi
(1, 7, 1, 30000), -- 1 nải chuối  
(1, 14, 1, 12000); -- 1 lon Coca Cola

-- Sample family grocery transaction
INSERT INTO supermarket.sales_invoices (invoice_no, customer_id, employee_id, payment_method) VALUES
('INV-20241220-000002', 50, 5, 'CARD');

INSERT INTO supermarket.sales_invoice_details (invoice_id, product_id, quantity, unit_price, discount_percentage) VALUES
(2, 9, 2, 240000, 0), -- 2 thùng mì tôm
(2, 12, 5, 50000, 0), -- 5 kg gạo ST25
(2, 11, 3, 50000, 0), -- 3 chai dầu ăn
(2, 1, 5, 12000, 0),  -- 5 bó rau cải
(2, 3, 2, 180000, 5); -- 2 kg thịt ba chỉ (giảm giá 5%)
```

### Kiểm tra tính nhất quán dữ liệu

```sql
-- Script verify data consistency

-- 1. Check product categories match shelf categories
SELECT 
    p.product_code,
    p.product_name,
    pc1.category_name AS product_category,
    pc2.category_name AS shelf_category,
    CASE 
        WHEN pc1.category_id = pc2.category_id THEN 'MATCH'
        ELSE 'MISMATCH - ERROR'
    END AS consistency_check
FROM supermarket.shelf_inventory si
INNER JOIN supermarket.products p ON si.product_id = p.product_id
INNER JOIN supermarket.product_categories pc1 ON p.category_id = pc1.category_id
INNER JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id  
INNER JOIN supermarket.product_categories pc2 ON ds.category_id = pc2.category_id;

-- 2. Check selling price > import price
SELECT 
    product_code,
    product_name, 
    import_price,
    selling_price,
    selling_price - import_price AS profit_margin,
    CASE 
        WHEN selling_price > import_price THEN 'OK'
        ELSE 'ERROR - INVALID PRICE'
    END AS price_check
FROM supermarket.products;

-- 3. Check shelf quantities don't exceed max capacity  
SELECT 
    ds.shelf_code,
    p.product_code,
    si.current_quantity,
    sl.max_quantity,
    CASE 
        WHEN si.current_quantity <= sl.max_quantity THEN 'OK'
        ELSE 'ERROR - OVER CAPACITY'
    END AS capacity_check
FROM supermarket.shelf_inventory si
INNER JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
INNER JOIN supermarket.products p ON si.product_id = p.product_id
INNER JOIN supermarket.shelf_layout sl ON si.shelf_id = sl.shelf_id 
    AND si.product_id = sl.product_id;
```

---

**Tóm tắt Case Studies:**

1. **Expiry Management**: Products sắp hết hạn sẽ trigger discount rules tự động
2. **Capacity Management**: Shelf đầy sẽ không thể transfer thêm hàng
3. **Stock Tracking**: FIFO system đảm bảo hàng cũ được bán trước
4. **Membership Upgrades**: Customers tự động được upgrade khi đạt spending threshold
5. **Employee Management**: Flexible work hours với overtime calculation
6. **Data Consistency**: Các ràng buộc nghiệp vụ được enforce bởi triggers

Dữ liệu mẫu này cung cấp foundation hoàn chỉnh để test tất cả các chức năng của hệ thống trong điều kiện thực tế.
