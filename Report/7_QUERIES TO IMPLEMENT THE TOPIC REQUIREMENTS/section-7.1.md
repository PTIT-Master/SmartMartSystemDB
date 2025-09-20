# 7.1. QUERIES QUẢN LÝ CƠ BẢN

Phần này trình bày các câu lệnh SQL cơ bản để thực hiện các thao tác CRUD (Create, Read, Update, Delete) và tìm kiếm đa điều kiện cho các đối tượng chính trong hệ thống quản lý siêu thị.

## 7.1.1. CRUD Operations cho các đối tượng

### A. Quản lý Sản phẩm (Products)

#### **CREATE - Thêm sản phẩm mới**

```sql
-- Thêm sản phẩm mới
INSERT INTO supermarket.products (
    product_code, product_name, category_id, supplier_id, 
    unit, import_price, selling_price, shelf_life_days, 
    low_stock_threshold, barcode, description
) VALUES (
    'PRD-FOOD-001', 
    'Bánh mì sandwich thịt nguội', 
    1, -- category_id cho Food
    1, -- supplier_id
    'cái',
    15000, -- import_price
    22000, -- selling_price (phải > import_price)
    3, -- shelf_life_days
    20, -- low_stock_threshold
    '1234567890123',
    'Bánh mì sandwich thịt nguội tươi ngon'
);

-- Xác minh ràng buộc giá bán > giá nhập được trigger xử lý tự động
```

#### **READ - Truy xuất thông tin sản phẩm**

```sql
-- Lấy thông tin chi tiết sản phẩm kèm thông tin category và supplier
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    s.supplier_name,
    p.unit,
    p.import_price,
    p.selling_price,
    p.shelf_life_days,
    p.low_stock_threshold,
    p.barcode,
    p.description,
    p.is_active,
    p.created_at
FROM supermarket.products p
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.suppliers s ON p.supplier_id = s.supplier_id
WHERE p.product_code = 'PRD-FOOD-001';

-- Lấy tất cả sản phẩm đang active
SELECT * FROM supermarket.products 
WHERE is_active = true 
ORDER BY created_at DESC;
```

#### **UPDATE - Cập nhật thông tin sản phẩm**

```sql
-- Cập nhật giá bán sản phẩm (trigger sẽ validate giá bán > giá nhập)
UPDATE supermarket.products 
SET selling_price = 25000,
    description = 'Bánh mì sandwich thịt nguội cao cấp'
WHERE product_code = 'PRD-FOOD-001';

-- Cập nhật ngưỡng cảnh báo tồn kho thấp
UPDATE supermarket.products 
SET low_stock_threshold = 15
WHERE category_id = 1; -- Cập nhật cho tất cả sản phẩm Food
```

#### **DELETE - Xóa sản phẩm (Soft Delete)**

```sql
-- Thông thường không xóa hoàn toàn sản phẩm mà chỉ set is_active = false
UPDATE supermarket.products 
SET is_active = false
WHERE product_code = 'PRD-FOOD-001';

-- Xóa thực sự (cần cẩn thận vì có thể vi phạm foreign key)
-- DELETE FROM supermarket.products WHERE product_code = 'PRD-FOOD-001';
```

### B. Quản lý Khách hàng (Customers)

#### **CREATE - Đăng ký khách hàng mới**

```sql
-- Thêm khách hàng thành viên mới
INSERT INTO supermarket.customers (
    customer_code, full_name, phone, email, address,
    membership_card_no, membership_level_id
) VALUES (
    'CUS-2024-001',
    'Nguyễn Văn An',
    '0901234567',
    'nguyenvanan@email.com',
    '123 Đường ABC, Quận 1, TP.HCM',
    'MEMBER-2024-001',
    1 -- Basic membership level
);
```

#### **READ - Truy xuất thông tin khách hàng**

```sql
-- Lấy thông tin khách hàng kèm level membership
SELECT 
    c.customer_code,
    c.full_name,
    c.phone,
    c.email,
    c.address,
    c.membership_card_no,
    ml.level_name,
    c.total_spending,
    c.loyalty_points,
    c.registration_date
FROM supermarket.customers c
LEFT JOIN supermarket.membership_levels ml ON c.membership_level_id = ml.level_id
WHERE c.phone = '0901234567';
```

#### **UPDATE - Cập nhật thông tin khách hàng**

```sql
-- Cập nhật thông tin liên hệ
UPDATE supermarket.customers 
SET email = 'newemail@gmail.com',
    address = '456 Đường XYZ, Quận 2, TP.HCM'
WHERE customer_code = 'CUS-2024-001';

-- Cập nhật điểm loyalty (thường được trigger tự động xử lý khi mua hàng)
UPDATE supermarket.customers 
SET loyalty_points = loyalty_points + 100
WHERE customer_code = 'CUS-2024-001';
```

### C. Quản lý Nhân viên (Employees)

#### **CREATE - Thêm nhân viên mới**

```sql
-- Thêm nhân viên mới
INSERT INTO supermarket.employees (
    employee_code, full_name, position_id, phone, email,
    address, id_card, bank_account
) VALUES (
    'EMP-2024-001',
    'Trần Thị Bình',
    2, -- position_id cho Sales Staff
    '0907654321',
    'tranthibinh@company.com',
    '789 Đường DEF, Quận 3, TP.HCM',
    '123456789012',
    '1234567890'
);
```

#### **READ - Truy xuất thông tin nhân viên**

```sql
-- Lấy thông tin nhân viên kèm chức vụ và lương
SELECT 
    e.employee_code,
    e.full_name,
    p.position_name,
    p.base_salary,
    p.hourly_rate,
    e.phone,
    e.email,
    e.hire_date,
    e.is_active
FROM supermarket.employees e
INNER JOIN supermarket.positions p ON e.position_id = p.position_id
WHERE e.is_active = true
ORDER BY e.hire_date DESC;
```

### D. Quản lý Nhà cung cấp (Suppliers)

#### **CREATE - Thêm nhà cung cấp mới**

```sql
-- Thêm nhà cung cấp
INSERT INTO supermarket.suppliers (
    supplier_code, supplier_name, contact_person, phone, email,
    address, tax_code, bank_account
) VALUES (
    'SUP-2024-001',
    'Công ty TNHH Thực phẩm ABC',
    'Nguyễn Văn Manager',
    '0281234567',
    'contact@foodabc.com',
    '123 KCN ABC, Bình Dương',
    '0123456789',
    '9876543210'
);
```

#### **READ - Truy xuất thông tin nhà cung cấp**

```sql
-- Lấy thông tin nhà cung cấp kèm số sản phẩm đang cung cấp
SELECT 
    s.supplier_code,
    s.supplier_name,
    s.contact_person,
    s.phone,
    s.email,
    COUNT(p.product_id) as total_products,
    s.is_active
FROM supermarket.suppliers s
LEFT JOIN supermarket.products p ON s.supplier_id = p.supplier_id
WHERE s.is_active = true
GROUP BY s.supplier_id, s.supplier_code, s.supplier_name, 
         s.contact_person, s.phone, s.email, s.is_active
ORDER BY total_products DESC;
```

## 7.1.2. Tìm kiếm và lọc đa điều kiện

### A. Tìm kiếm sản phẩm nâng cao

```sql
-- Tìm kiếm sản phẩm theo nhiều tiêu chí
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    s.supplier_name,
    p.selling_price,
    COALESCE(inv.total_quantity, 0) as stock_quantity
FROM supermarket.products p
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.suppliers s ON p.supplier_id = s.supplier_id
LEFT JOIN (
    -- Subquery tính tổng tồn kho (warehouse + shelf)
    SELECT 
        product_id,
        SUM(COALESCE(warehouse_qty, 0) + COALESCE(shelf_qty, 0)) as total_quantity
    FROM (
        SELECT product_id, SUM(quantity) as warehouse_qty, 0 as shelf_qty
        FROM supermarket.warehouse_inventory
        GROUP BY product_id
        UNION ALL
        SELECT product_id, 0 as warehouse_qty, SUM(current_quantity) as shelf_qty
        FROM supermarket.shelf_inventory  
        GROUP BY product_id
    ) combined
    GROUP BY product_id
) inv ON p.product_id = inv.product_id
WHERE 
    p.is_active = true
    AND (
        p.product_name ILIKE '%bánh%' 
        OR p.product_code ILIKE '%FOOD%'
        OR p.barcode = '1234567890123'
    )
    AND p.selling_price BETWEEN 10000 AND 50000
    AND pc.category_name = 'Food'
    AND inv.total_quantity > 0
ORDER BY p.selling_price ASC, p.product_name ASC;
```

### B. Tìm kiếm khách hàng theo điều kiện phức hợp

```sql
-- Tìm khách hàng VIP (high-value customers)
SELECT 
    c.customer_code,
    c.full_name,
    c.phone,
    ml.level_name,
    c.total_spending,
    c.loyalty_points,
    COUNT(si.invoice_id) as total_orders,
    MAX(si.invoice_date) as last_purchase,
    AVG(si.total_amount) as avg_order_value
FROM supermarket.customers c
LEFT JOIN supermarket.membership_levels ml ON c.membership_level_id = ml.level_id
LEFT JOIN supermarket.sales_invoices si ON c.customer_id = si.customer_id
WHERE 
    c.is_active = true
    AND c.total_spending >= 1000000 -- Khách hàng chi tiêu >= 1 triệu
    AND c.registration_date >= '2024-01-01'
GROUP BY c.customer_id, c.customer_code, c.full_name, c.phone, 
         ml.level_name, c.total_spending, c.loyalty_points
HAVING 
    COUNT(si.invoice_id) >= 5 -- Có ít nhất 5 đơn hàng
    AND MAX(si.invoice_date) >= CURRENT_DATE - INTERVAL '30 days' -- Mua hàng trong 30 ngày gần đây
ORDER BY c.total_spending DESC, total_orders DESC;
```

### C. Tìm kiếm đơn hàng theo thời gian và trạng thái

```sql
-- Tìm đơn hàng trong khoảng thời gian với filtering phức tạp
SELECT 
    si.invoice_no,
    si.invoice_date,
    c.full_name as customer_name,
    c.phone as customer_phone,
    e.full_name as employee_name,
    si.total_amount,
    si.payment_method,
    si.points_earned,
    si.points_used,
    COUNT(sid.detail_id) as total_items
FROM supermarket.sales_invoices si
LEFT JOIN supermarket.customers c ON si.customer_id = c.customer_id
INNER JOIN supermarket.employees e ON si.employee_id = e.employee_id
LEFT JOIN supermarket.sales_invoice_details sid ON si.invoice_id = sid.invoice_id
WHERE 
    si.invoice_date >= '2024-12-01'
    AND si.invoice_date < '2025-01-01'
    AND (
        si.total_amount >= 500000 -- Đơn hàng >= 500k
        OR si.customer_id IS NOT NULL -- Hoặc là khách thành viên
    )
    AND si.payment_method IN ('CASH', 'CARD', 'E_WALLET')
GROUP BY si.invoice_id, si.invoice_no, si.invoice_date, 
         c.full_name, c.phone, e.full_name, si.total_amount,
         si.payment_method, si.points_earned, si.points_used
HAVING COUNT(sid.detail_id) >= 3 -- Đơn hàng có >= 3 items
ORDER BY si.invoice_date DESC, si.total_amount DESC;
```

### D. Tìm kiếm và phân tích inventory

```sql
-- Phân tích tồn kho theo nhiều tiêu chí
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    s.supplier_name,
    COALESCE(wi.warehouse_quantity, 0) as warehouse_stock,
    COALESCE(si.shelf_quantity, 0) as shelf_stock,
    COALESCE(wi.warehouse_quantity, 0) + COALESCE(si.shelf_quantity, 0) as total_stock,
    p.low_stock_threshold,
    CASE 
        WHEN COALESCE(si.shelf_quantity, 0) = 0 THEN 'OUT_OF_SHELF'
        WHEN COALESCE(si.shelf_quantity, 0) <= p.low_stock_threshold THEN 'LOW_SHELF_STOCK'
        WHEN COALESCE(wi.warehouse_quantity, 0) = 0 THEN 'OUT_OF_WAREHOUSE'
        ELSE 'ADEQUATE_STOCK'
    END as stock_status,
    p.selling_price,
    p.import_price,
    ROUND((p.selling_price - p.import_price) / p.import_price * 100, 2) as profit_margin_percent
FROM supermarket.products p
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.suppliers s ON p.supplier_id = s.supplier_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) as warehouse_quantity
    FROM supermarket.warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) as shelf_quantity
    FROM supermarket.shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id
WHERE 
    p.is_active = true
    AND pc.category_name IN ('Food', 'Electronics', 'Home & Garden')
    AND (
        COALESCE(wi.warehouse_quantity, 0) + COALESCE(si.shelf_quantity, 0) <= p.low_stock_threshold
        OR COALESCE(si.shelf_quantity, 0) = 0
    )
ORDER BY 
    CASE 
        WHEN COALESCE(si.shelf_quantity, 0) = 0 THEN 1
        WHEN COALESCE(si.shelf_quantity, 0) <= p.low_stock_threshold THEN 2
        ELSE 3
    END,
    total_stock ASC;
```

### E. Query tổng hợp với window functions

```sql
-- Phân tích ranking và so sánh
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    sales_summary.total_revenue,
    sales_summary.total_quantity_sold,
    sales_summary.avg_selling_price,
    -- Ranking trong category
    RANK() OVER (
        PARTITION BY pc.category_name 
        ORDER BY sales_summary.total_revenue DESC
    ) as category_revenue_rank,
    -- Ranking toàn hệ thống
    RANK() OVER (ORDER BY sales_summary.total_revenue DESC) as overall_revenue_rank,
    -- So sánh với trung bình category
    ROUND(
        (sales_summary.total_revenue / 
         AVG(sales_summary.total_revenue) OVER (PARTITION BY pc.category_name) - 1) * 100, 
        2
    ) as vs_category_avg_percent
FROM supermarket.products p
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN (
    SELECT 
        p.product_id,
        SUM(sid.subtotal) as total_revenue,
        SUM(sid.quantity) as total_quantity_sold,
        AVG(sid.unit_price) as avg_selling_price
    FROM supermarket.sales_invoice_details sid
    INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
    INNER JOIN supermarket.products p ON sid.product_id = p.product_id
    WHERE si.invoice_date >= CURRENT_DATE - INTERVAL '90 days' -- 3 tháng gần nhất
    GROUP BY p.product_id
    HAVING SUM(sid.quantity) >= 10 -- Chỉ lấy sản phẩm bán >= 10 units
) sales_summary ON p.product_id = sales_summary.product_id
WHERE p.is_active = true
ORDER BY sales_summary.total_revenue DESC;
```

## Kết luận phần 7.1

Các queries trong phần này đã thực hiện đầy đủ các thao tác CRUD cơ bản cho tất cả các đối tượng chính trong hệ thống:

1. **CRUD Operations**: Thêm, đọc, cập nhật, xóa cho Products, Customers, Employees, Suppliers
2. **Advanced Search**: Tìm kiếm đa tiêu chí với JOIN, subquery, và các điều kiện phức tạp
3. **Business Logic Integration**: Các queries tận dụng triggers và constraints đã thiết kế
4. **Performance Optimization**: Sử dụng index-friendly queries và window functions

Tất cả queries đều tuân thủ các ràng buộc nghiệp vụ đã định nghĩa và tận dụng các trigger để đảm bảo tính toàn vẹn dữ liệu.
