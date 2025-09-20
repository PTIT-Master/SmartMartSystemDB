# 7.3. QUERIES XỬ LÝ HẠN SỬ DỤNG

Phần này trình bày các câu lệnh SQL để xử lý các sản phẩm có hạn sử dụng, bao gồm tìm kiếm hàng hóa quá hạn, áp dụng quy tắc giảm giá tự động, và thống kê hàng sắp hết hạn theo yêu cầu của đề tài.

## 7.3.1. Tìm hàng quá hạn cần loại bỏ

### A. Tìm hàng quá hạn trong kho

```sql
-- Query: Tìm thông tin các hàng hóa đã quá hạn bán trong warehouse
-- Đáp ứng yêu cầu: "Tìm thông tin của các hàng hóa đã quá hạn bán"
SELECT 
    wi.inventory_id,
    wi.batch_code,
    p.product_code,
    p.product_name,
    pc.category_name,
    s.supplier_name,
    wi.quantity,
    wi.import_date,
    wi.expiry_date,
    -- Tính số ngày đã quá hạn
    CURRENT_DATE - wi.expiry_date as days_expired,
    -- Giá trị tồn kho bị mất
    wi.quantity * wi.import_price as lost_value,
    wi.import_price,
    p.selling_price,
    w.warehouse_name,
    w.location as warehouse_location,
    -- Phân loại mức độ nghiêm trọng
    CASE 
        WHEN CURRENT_DATE - wi.expiry_date <= 7 THEN 'MỚI QUÁ HẠN (<=7 ngày)'
        WHEN CURRENT_DATE - wi.expiry_date <= 30 THEN 'QUÁ HẠN TRUNG BÌNH (<=30 ngày)'
        ELSE 'QUÁ HẠN NGHIÊM TRỌNG (>30 ngày)'
    END as expiry_severity
FROM supermarket.warehouse_inventory wi
INNER JOIN supermarket.products p ON wi.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.suppliers s ON p.supplier_id = s.supplier_id
INNER JOIN supermarket.warehouse w ON wi.warehouse_id = w.warehouse_id
WHERE 
    wi.expiry_date < CURRENT_DATE -- Đã quá hạn
    AND wi.quantity > 0 -- Còn tồn kho
ORDER BY 
    days_expired DESC, -- Quá hạn lâu nhất trước
    lost_value DESC; -- Giá trị mất nhiều nhất
```

### B. Sử dụng View có sẵn cho expired products

```sql
-- Sử dụng view v_expired_products đã được định nghĩa sẵn
SELECT 
    batch_code,
    product_code,
    product_name,
    category_name,
    quantity,
    import_date,
    expiry_date,
    days_until_expiry,
    import_price,
    selling_price,
    warehouse_name,
    expiry_status,
    -- Tính toán bổ sung
    quantity * import_price as inventory_value,
    CASE 
        WHEN expiry_status = 'Expired' THEN quantity * import_price
        ELSE 0
    END as loss_amount
FROM supermarket.v_expired_products
WHERE expiry_status IN ('Expired', 'Expiring soon')
ORDER BY 
    CASE expiry_status
        WHEN 'Expired' THEN 1
        WHEN 'Expiring soon' THEN 2
        ELSE 3
    END,
    days_until_expiry ASC;
```

### C. Tìm hàng quá hạn trên quầy (shelf batch inventory)

```sql
-- Query: Tìm hàng quá hạn trên quầy hàng cần loại bỏ ngay
SELECT 
    sbi.shelf_batch_id,
    sbi.batch_code,
    p.product_code,
    p.product_name,
    pc.category_name,
    ds.shelf_code,
    ds.shelf_name,
    sbi.quantity,
    sbi.expiry_date,
    sbi.stocked_date,
    CURRENT_DATE - sbi.expiry_date as days_expired,
    sbi.current_price,
    sbi.import_price,
    sbi.discount_percent,
    -- Giá trị tồn kho bị mất
    sbi.quantity * sbi.import_price as lost_value,
    -- Thời gian lưu trên quầy
    CURRENT_DATE - sbi.stocked_date::DATE as days_on_shelf
FROM supermarket.shelf_batch_inventory sbi
INNER JOIN supermarket.products p ON sbi.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.display_shelves ds ON sbi.shelf_id = ds.shelf_id
WHERE 
    sbi.expiry_date < CURRENT_DATE -- Đã quá hạn
    AND sbi.quantity > 0 -- Còn số lượng
ORDER BY 
    days_expired DESC,
    lost_value DESC;
```

### D. Stored Procedure để xóa hàng quá hạn

```sql
-- Gọi stored procedure đã được định nghĩa để xóa hàng quá hạn
CALL supermarket.sp_remove_expired_products();

-- Xem kết quả sau khi chạy procedure
SELECT 
    'Warehouse' as location_type,
    COUNT(*) as expired_batches_removed,
    SUM(quantity * import_price) as total_loss_value
FROM supermarket.warehouse_inventory 
WHERE expiry_date < CURRENT_DATE AND quantity = 0 -- Đã được xóa bởi procedure

UNION ALL

SELECT 
    'Shelf' as location_type,
    COUNT(*) as expired_batches_removed,
    SUM(quantity * import_price) as total_loss_value
FROM supermarket.shelf_batch_inventory 
WHERE expiry_date < CURRENT_DATE AND quantity = 0; -- Đã được đánh dấu bởi procedure
```

## 7.3.2. Cập nhật giá theo quy tắc giảm giá (theo category)

### A. Xem quy tắc giảm giá hiện tại

```sql
-- Query: Xem các quy tắc giảm giá theo category
SELECT 
    dr.rule_id,
    dr.rule_name,
    pc.category_name,
    dr.days_before_expiry,
    dr.discount_percentage,
    dr.is_active,
    dr.created_at,
    -- Đếm số sản phẩm áp dụng
    COUNT(p.product_id) as applicable_products
FROM supermarket.discount_rules dr
INNER JOIN supermarket.product_categories pc ON dr.category_id = pc.category_id
LEFT JOIN supermarket.products p ON pc.category_id = p.category_id AND p.is_active = true
WHERE dr.is_active = true
GROUP BY dr.rule_id, dr.rule_name, pc.category_name, 
         dr.days_before_expiry, dr.discount_percentage, 
         dr.is_active, dr.created_at
ORDER BY pc.category_name, dr.days_before_expiry DESC;
```

### B. Thêm quy tắc giảm giá mới (theo yêu cầu đề tài)

```sql
-- Thêm quy tắc giảm giá cho Food: dưới 5 ngày giảm 50%
INSERT INTO supermarket.discount_rules (
    category_id, days_before_expiry, discount_percentage, 
    rule_name, is_active
) VALUES (
    (SELECT category_id FROM supermarket.product_categories WHERE category_name = 'Food'),
    5, -- dưới 5 ngày
    50.00, -- giảm 50%
    'Food - 5 days expiry discount',
    true
);

-- Thêm quy tắc giảm giá cho Fresh Produce: dưới 3 ngày giảm 50% (theo yêu cầu đề tài)
INSERT INTO supermarket.discount_rules (
    category_id, days_before_expiry, discount_percentage,
    rule_name, is_active  
) VALUES (
    (SELECT category_id FROM supermarket.product_categories WHERE category_name = 'Fresh Produce'),
    3, -- dưới 3 ngày
    50.00, -- giảm 50%
    'Fresh Produce - 3 days expiry discount', 
    true
);

-- Thêm quy tắc giảm giá cho Dairy: dưới 2 ngày giảm 60%
INSERT INTO supermarket.discount_rules (
    category_id, days_before_expiry, discount_percentage,
    rule_name, is_active
) VALUES (
    (SELECT category_id FROM supermarket.product_categories WHERE category_name = 'Dairy'),
    2, -- dưới 2 ngày
    60.00, -- giảm 60%
    'Dairy - 2 days expiry discount',
    true
);
```

### C. Áp dụng giảm giá thủ công (ngoài trigger tự động)

```sql
-- Query: Tìm sản phẩm cần áp dụng giảm giá dựa trên discount_rules
WITH products_need_discount AS (
    SELECT 
        wi.inventory_id,
        wi.product_id,
        wi.batch_code,
        wi.expiry_date,
        p.product_code,
        p.product_name,
        pc.category_name,
        p.selling_price as current_price,
        p.import_price,
        dr.discount_percentage,
        dr.days_before_expiry,
        wi.expiry_date - CURRENT_DATE as days_until_expiry,
        -- Tính giá sau giảm
        p.selling_price * (1 - dr.discount_percentage / 100) as discounted_price,
        -- Đảm bảo không thấp hơn 110% giá nhập
        GREATEST(
            p.selling_price * (1 - dr.discount_percentage / 100),
            p.import_price * 1.1
        ) as final_price
    FROM supermarket.warehouse_inventory wi
    INNER JOIN supermarket.products p ON wi.product_id = p.product_id
    INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
    INNER JOIN supermarket.discount_rules dr ON pc.category_id = dr.category_id
    WHERE 
        wi.expiry_date IS NOT NULL
        AND wi.expiry_date - CURRENT_DATE <= dr.days_before_expiry
        AND wi.expiry_date - CURRENT_DATE > 0 -- Chưa quá hạn
        AND dr.is_active = true
        AND wi.quantity > 0
)
-- Hiển thị danh sách sản phẩm cần giảm giá
SELECT 
    product_code,
    product_name,
    category_name,
    batch_code,
    days_until_expiry,
    days_before_expiry as rule_threshold,
    discount_percentage,
    current_price,
    final_price,
    current_price - final_price as discount_amount,
    ROUND((current_price - final_price) / current_price * 100, 2) as actual_discount_percent
FROM products_need_discount
ORDER BY days_until_expiry ASC, discount_percentage DESC;

-- Cập nhật giá thực tế (thường được trigger tự động xử lý)
-- UPDATE supermarket.products 
-- SET selling_price = (SELECT final_price FROM products_need_discount WHERE product_id = products.product_id)
-- WHERE product_id IN (SELECT product_id FROM products_need_discount);
```

### D. Kích hoạt trigger áp dụng giảm giá tự động

```sql
-- Trigger sẽ tự động chạy khi cập nhật expiry_date
-- Ví dụ: Force trigger bằng cách update expiry_date (giữ nguyên giá trị)
UPDATE supermarket.warehouse_inventory 
SET expiry_date = expiry_date  -- Trigger sẽ chạy và áp dụng discount
WHERE expiry_date IS NOT NULL 
  AND expiry_date - CURRENT_DATE <= 5 -- Trong vòng 5 ngày
  AND expiry_date > CURRENT_DATE; -- Chưa quá hạn

-- Xem kết quả sau khi trigger chạy
SELECT 
    wi.batch_code,
    p.product_code,
    p.product_name,
    pc.category_name,
    wi.expiry_date,
    wi.expiry_date - CURRENT_DATE as days_until_expiry,
    p.selling_price,
    p.import_price,
    ROUND((p.selling_price - p.import_price) / p.import_price * 100, 2) as profit_margin
FROM supermarket.warehouse_inventory wi
INNER JOIN supermarket.products p ON wi.product_id = p.product_id  
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
WHERE wi.expiry_date - CURRENT_DATE <= 5
  AND wi.expiry_date > CURRENT_DATE
ORDER BY wi.expiry_date ASC;
```

## 7.3.3. Thống kê hàng sắp hết hạn (3 ngày, 5 ngày)

### A. Thống kê tổng quan hàng sắp hết hạn

```sql
-- Query: Thống kê hàng sắp hết hạn theo ngày và category
SELECT 
    pc.category_name,
    COUNT(CASE WHEN wi.expiry_date - CURRENT_DATE <= 1 THEN 1 END) as expires_tomorrow,
    COUNT(CASE WHEN wi.expiry_date - CURRENT_DATE <= 3 THEN 1 END) as expires_within_3_days,
    COUNT(CASE WHEN wi.expiry_date - CURRENT_DATE <= 5 THEN 1 END) as expires_within_5_days,
    COUNT(CASE WHEN wi.expiry_date - CURRENT_DATE <= 7 THEN 1 END) as expires_within_7_days,
    -- Tính giá trị tồn kho sắp hết hạn
    SUM(CASE WHEN wi.expiry_date - CURRENT_DATE <= 3 THEN wi.quantity * wi.import_price ELSE 0 END) as value_expires_3_days,
    SUM(CASE WHEN wi.expiry_date - CURRENT_DATE <= 5 THEN wi.quantity * wi.import_price ELSE 0 END) as value_expires_5_days,
    -- Trung bình số ngày còn lại
    AVG(CASE WHEN wi.expiry_date - CURRENT_DATE <= 5 THEN wi.expiry_date - CURRENT_DATE ELSE NULL END) as avg_days_remaining_within_5
FROM supermarket.warehouse_inventory wi
INNER JOIN supermarket.products p ON wi.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
WHERE 
    wi.expiry_date IS NOT NULL
    AND wi.expiry_date > CURRENT_DATE -- Chưa quá hạn
    AND wi.expiry_date - CURRENT_DATE <= 7 -- Trong vòng 7 ngày
    AND wi.quantity > 0
GROUP BY pc.category_id, pc.category_name
ORDER BY expires_within_3_days DESC;
```

### B. Chi tiết hàng sắp hết hạn 3 ngày

```sql
-- Query: Chi tiết hàng hóa sắp hết hạn trong 3 ngày
SELECT 
    wi.batch_code,
    p.product_code,
    p.product_name,
    pc.category_name,
    wi.quantity,
    wi.import_date,
    wi.expiry_date,
    wi.expiry_date - CURRENT_DATE as days_remaining,
    wi.import_price,
    p.selling_price,
    -- Kiểm tra đã áp dụng discount chưa
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM supermarket.discount_rules dr 
            WHERE dr.category_id = pc.category_id 
              AND dr.days_before_expiry >= (wi.expiry_date - CURRENT_DATE)
              AND dr.is_active = true
        ) THEN 'ĐÃ CÓ QUY TẮC GIẢM GIÁ'
        ELSE 'CHƯA CÓ QUY TẮC'
    END as discount_status,
    -- Giá trị có thể mất
    wi.quantity * wi.import_price as potential_loss,
    w.warehouse_name,
    -- Đề xuất hành động
    CASE 
        WHEN wi.expiry_date - CURRENT_DATE <= 1 THEN 'BÁN GẤP HOẶC THANH LÝ'
        WHEN wi.expiry_date - CURRENT_DATE <= 2 THEN 'GIẢM GIÁ MẠNH'
        WHEN wi.expiry_date - CURRENT_DATE <= 3 THEN 'GIẢM GIÁ VỪA PHẢI'
        ELSE 'THEO DÕI'
    END as recommended_action
FROM supermarket.warehouse_inventory wi
INNER JOIN supermarket.products p ON wi.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.warehouse w ON wi.warehouse_id = w.warehouse_id
WHERE 
    wi.expiry_date IS NOT NULL
    AND wi.expiry_date - CURRENT_DATE <= 3 -- Trong vòng 3 ngày
    AND wi.expiry_date > CURRENT_DATE -- Chưa quá hạn
    AND wi.quantity > 0
ORDER BY 
    wi.expiry_date ASC, 
    potential_loss DESC;
```

### C. Chi tiết hàng sắp hết hạn 5 ngày

```sql
-- Query: Chi tiết hàng hóa sắp hết hạn trong 5 ngày  
SELECT 
    wi.batch_code,
    p.product_code,
    p.product_name,
    pc.category_name,
    s.supplier_name,
    wi.quantity,
    wi.expiry_date,
    wi.expiry_date - CURRENT_DATE as days_remaining,
    wi.import_price,
    p.selling_price,
    -- Tìm discount rule áp dụng
    dr.discount_percentage,
    dr.days_before_expiry as rule_trigger_days,
    -- Tính giá sau discount
    CASE 
        WHEN dr.discount_percentage IS NOT NULL THEN
            GREATEST(
                p.selling_price * (1 - dr.discount_percentage / 100),
                wi.import_price * 1.1
            )
        ELSE p.selling_price
    END as suggested_price,
    wi.quantity * wi.import_price as inventory_value,
    -- Phân nhóm theo mức độ khẩn cấp
    CASE 
        WHEN wi.expiry_date - CURRENT_DATE <= 1 THEN 'KHẨN CẤP'
        WHEN wi.expiry_date - CURRENT_DATE <= 2 THEN 'CAO'
        WHEN wi.expiry_date - CURRENT_DATE <= 3 THEN 'TRUNG BÌNH'
        ELSE 'THẤP'
    END as urgency_level
FROM supermarket.warehouse_inventory wi
INNER JOIN supermarket.products p ON wi.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.suppliers s ON p.supplier_id = s.supplier_id
LEFT JOIN supermarket.discount_rules dr ON pc.category_id = dr.category_id 
                                        AND dr.days_before_expiry >= (wi.expiry_date - CURRENT_DATE)
                                        AND dr.is_active = true
WHERE 
    wi.expiry_date IS NOT NULL
    AND wi.expiry_date - CURRENT_DATE <= 5 -- Trong vòng 5 ngày
    AND wi.expiry_date > CURRENT_DATE -- Chưa quá hạn
    AND wi.quantity > 0
ORDER BY 
    urgency_level ASC,
    wi.expiry_date ASC,
    inventory_value DESC;
```

### D. Dashboard tổng hợp expiry management

```sql
-- Query: Dashboard tổng hợp quản lý hạn sử dụng
WITH expiry_summary AS (
    SELECT 
        pc.category_name,
        -- Đếm theo ngày còn lại
        COUNT(*) as total_batches_expiring,
        SUM(wi.quantity) as total_quantity_expiring,
        SUM(wi.quantity * wi.import_price) as total_value_at_risk,
        -- Phân loại theo độ khẩn cấp
        COUNT(CASE WHEN wi.expiry_date - CURRENT_DATE <= 1 THEN 1 END) as critical_1_day,
        COUNT(CASE WHEN wi.expiry_date - CURRENT_DATE BETWEEN 2 AND 3 THEN 1 END) as urgent_2_3_days,
        COUNT(CASE WHEN wi.expiry_date - CURRENT_DATE BETWEEN 4 AND 5 THEN 1 END) as moderate_4_5_days,
        -- Tính giá trị theo độ khẩn cấp
        SUM(CASE WHEN wi.expiry_date - CURRENT_DATE <= 1 THEN wi.quantity * wi.import_price ELSE 0 END) as value_critical,
        SUM(CASE WHEN wi.expiry_date - CURRENT_DATE BETWEEN 2 AND 3 THEN wi.quantity * wi.import_price ELSE 0 END) as value_urgent,
        SUM(CASE WHEN wi.expiry_date - CURRENT_DATE BETWEEN 4 AND 5 THEN wi.quantity * wi.import_price ELSE 0 END) as value_moderate
    FROM supermarket.warehouse_inventory wi
    INNER JOIN supermarket.products p ON wi.product_id = p.product_id
    INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
    WHERE 
        wi.expiry_date IS NOT NULL
        AND wi.expiry_date - CURRENT_DATE <= 5
        AND wi.expiry_date > CURRENT_DATE
        AND wi.quantity > 0
    GROUP BY pc.category_id, pc.category_name
)
SELECT 
    category_name,
    total_batches_expiring,
    total_quantity_expiring,
    ROUND(total_value_at_risk, 2) as total_value_at_risk,
    critical_1_day,
    urgent_2_3_days, 
    moderate_4_5_days,
    ROUND(value_critical, 2) as value_critical,
    ROUND(value_urgent, 2) as value_urgent,
    ROUND(value_moderate, 2) as value_moderate,
    -- Tính tỷ lệ phần trăm
    ROUND((value_critical / NULLIF(total_value_at_risk, 0) * 100), 2) as critical_percentage,
    ROUND((value_urgent / NULLIF(total_value_at_risk, 0) * 100), 2) as urgent_percentage
FROM expiry_summary
ORDER BY total_value_at_risk DESC;
```

### E. Báo cáo hàng đã hết hạn vs sắp hết hạn

```sql
-- Query: So sánh hàng đã hết hạn vs sắp hết hạn
SELECT 
    pc.category_name,
    -- Hàng đã hết hạn
    COUNT(CASE WHEN wi.expiry_date < CURRENT_DATE THEN 1 END) as expired_batches,
    SUM(CASE WHEN wi.expiry_date < CURRENT_DATE THEN wi.quantity ELSE 0 END) as expired_quantity,
    SUM(CASE WHEN wi.expiry_date < CURRENT_DATE THEN wi.quantity * wi.import_price ELSE 0 END) as expired_loss_value,
    -- Hàng sắp hết hạn (3 ngày)
    COUNT(CASE WHEN wi.expiry_date - CURRENT_DATE BETWEEN 0 AND 3 THEN 1 END) as expiring_3_days,
    SUM(CASE WHEN wi.expiry_date - CURRENT_DATE BETWEEN 0 AND 3 THEN wi.quantity ELSE 0 END) as expiring_3_days_qty,
    SUM(CASE WHEN wi.expiry_date - CURRENT_DATE BETWEEN 0 AND 3 THEN wi.quantity * wi.import_price ELSE 0 END) as expiring_3_days_value,
    -- Hàng sắp hết hạn (5 ngày)  
    COUNT(CASE WHEN wi.expiry_date - CURRENT_DATE BETWEEN 0 AND 5 THEN 1 END) as expiring_5_days,
    SUM(CASE WHEN wi.expiry_date - CURRENT_DATE BETWEEN 0 AND 5 THEN wi.quantity ELSE 0 END) as expiring_5_days_qty,
    SUM(CASE WHEN wi.expiry_date - CURRENT_DATE BETWEEN 0 AND 5 THEN wi.quantity * wi.import_price ELSE 0 END) as expiring_5_days_value
FROM supermarket.warehouse_inventory wi
INNER JOIN supermarket.products p ON wi.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
WHERE 
    wi.expiry_date IS NOT NULL
    AND wi.quantity > 0
    AND (
        wi.expiry_date < CURRENT_DATE -- Đã hết hạn
        OR wi.expiry_date - CURRENT_DATE <= 5 -- Hoặc sắp hết hạn trong 5 ngày
    )
GROUP BY pc.category_id, pc.category_name
ORDER BY (expired_loss_value + expiring_5_days_value) DESC;
```

## Kết luận phần 7.3

Các queries trong phần này đã thực hiện đầy đủ các yêu cầu xử lý hạn sử dụng của đề tài:

1. **7.3.1**: Tìm hàng quá hạn cần loại bỏ với đầy đủ thông tin batch, giá trị tổn thất
2. **7.3.2**: Áp dụng quy tắc giảm giá theo category (Food 5 ngày 50%, Fresh Produce 3 ngày 50%)  
3. **7.3.3**: Thống kê chi tiết hàng sắp hết hạn 3 và 5 ngày với dashboard tổng hợp

**Đặc điểm nổi bật:**

- **Tự động hóa**: Triggers tự động áp dụng discount khi inventory có expiry_date
- **Linh hoạt**: Discount rules có thể cấu hình theo category khác nhau
- **An toàn**: Đảm bảo giá sau giảm không thấp hơn 110% giá nhập
- **Thông tin đầy đủ**: Cung cấp supplier info, batch tracking, loss value calculation
- **Dashboard friendly**: Queries tối ưu cho báo cáo và dashboard quản lý
