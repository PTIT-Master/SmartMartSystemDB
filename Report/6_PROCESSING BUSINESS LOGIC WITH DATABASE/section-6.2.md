# 6.2. VIEWS - KHUNG NHÌN DỮ LIỆU

## Tổng quan

Hệ thống triển khai **6 Views** chuyên biệt để cung cấp khung nhìn tổng hợp từ nhiều bảng dữ liệu, phục vụ các nhu cầu báo cáo và phân tích khác nhau. Mỗi view được tối ưu hóa cho một nghiệp vụ cụ thể và giảm thiểu độ phức tạp khi truy vấn.

---

## 6.2.1. **v_product_inventory_summary** - Tổng quan Tồn kho

### **Mục đích**
Cung cấp cái nhìn toàn diện về tình trạng tồn kho của tất cả sản phẩm, bao gồm cả kho và quầy bán.

### **Cấu trúc View**
```sql
CREATE OR REPLACE VIEW supermarket.v_product_inventory_summary AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    pc.category_name,
    s.supplier_name,
    COALESCE(wi.warehouse_qty, 0) AS warehouse_quantity,
    COALESCE(si.shelf_qty, 0) AS shelf_quantity,
    COALESCE(wi.warehouse_qty, 0) + COALESCE(si.shelf_qty, 0) AS total_quantity,
    p.low_stock_threshold,
    CASE 
        WHEN COALESCE(si.shelf_qty, 0) <= p.low_stock_threshold THEN 'Low on shelf'
        WHEN COALESCE(wi.warehouse_qty, 0) = 0 AND COALESCE(si.shelf_qty, 0) > 0 THEN 'Out in warehouse'
        WHEN COALESCE(wi.warehouse_qty, 0) + COALESCE(si.shelf_qty, 0) = 0 THEN 'Out of stock'
        ELSE 'Available'
    END AS stock_status
FROM supermarket.products p
LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
LEFT JOIN supermarket.suppliers s ON p.supplier_id = s.supplier_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS warehouse_qty
    FROM supermarket.warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) AS shelf_qty
    FROM supermarket.shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id
WHERE p.is_active = true;
```

### **Các cột dữ liệu**
| Cột | Kiểu | Mô tả |
|-----|------|--------|
| `product_code` | VARCHAR(50) | Mã sản phẩm |
| `product_name` | VARCHAR(200) | Tên sản phẩm |
| `category_name` | VARCHAR(100) | Loại sản phẩm |
| `supplier_name` | VARCHAR(200) | Nhà cung cấp |
| `warehouse_quantity` | BIGINT | Tồn kho trong kho |
| `shelf_quantity` | BIGINT | Tồn kho trên quầy |
| `total_quantity` | BIGINT | Tổng tồn kho |
| `stock_status` | TEXT | Trạng thái tồn kho |

### **Logic nghiệp vụ**
- **Tính tổng tồn kho**: Cộng tồn kho từ tất cả warehouse và shelf
- **Phân loại trạng thái**:
  - `Low on shelf`: Quầy dưới ngưỡng cảnh báo
  - `Out in warehouse`: Kho hết nhưng quầy còn
  - `Out of stock`: Hết hàng hoàn toàn
  - `Available`: Bình thường

### **Ví dụ sử dụng**
```sql
-- Liệt kê tất cả sản phẩm có vấn đề về tồn kho
SELECT product_code, product_name, warehouse_quantity, shelf_quantity, stock_status
FROM supermarket.v_product_inventory_summary
WHERE stock_status != 'Available'
ORDER BY stock_status, total_quantity;

-- Tìm top 10 sản phẩm tồn kho thấp nhất
SELECT product_code, product_name, total_quantity, stock_status
FROM supermarket.v_product_inventory_summary
WHERE total_quantity > 0
ORDER BY total_quantity ASC
LIMIT 10;
```

---

## 6.2.2. **v_expired_products** - Danh sách Hàng hết hạn

### **Mục đích**
Theo dõi các sản phẩm đã hết hạn hoặc sắp hết hạn để kịp thời xử lý (giảm giá hoặc loại bỏ).

### **Cấu trúc View**
```sql
CREATE OR REPLACE VIEW supermarket.v_expired_products AS
SELECT 
    wi.inventory_id,
    wi.batch_code,
    p.product_code,
    p.product_name,
    pc.category_name,
    wi.quantity,
    wi.import_date,
    wi.expiry_date,
    wi.expiry_date - CURRENT_DATE AS days_until_expiry,
    wi.import_price,
    p.selling_price,
    w.warehouse_name,
    CASE 
        WHEN wi.expiry_date < CURRENT_DATE THEN 'Expired'
        WHEN wi.expiry_date - CURRENT_DATE <= 3 THEN 'Expiring soon'
        ELSE 'Valid'
    END AS expiry_status
FROM supermarket.warehouse_inventory wi
INNER JOIN supermarket.products p ON wi.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.warehouse w ON wi.warehouse_id = w.warehouse_id
WHERE wi.expiry_date IS NOT NULL
ORDER BY wi.expiry_date ASC;
```

### **Logic phân loại hạn sử dụng**
- **Expired**: `expiry_date < CURRENT_DATE`
- **Expiring soon**: Còn ≤ 3 ngày
- **Valid**: Còn > 3 ngày

### **Ví dụ sử dụng**
```sql
-- Tìm hàng đã hết hạn cần loại bỏ
SELECT batch_code, product_name, quantity, days_until_expiry
FROM supermarket.v_expired_products
WHERE expiry_status = 'Expired'
ORDER BY days_until_expiry;

-- Hàng sắp hết hạn cần giảm giá
SELECT product_code, product_name, selling_price, days_until_expiry
FROM supermarket.v_expired_products
WHERE expiry_status = 'Expiring soon'
ORDER BY days_until_expiry;
```

---

## 6.2.3. **v_product_revenue** - Doanh thu theo Sản phẩm

### **Mục đích**
Phân tích hiệu suất kinh doanh của từng sản phẩm theo tháng để hỗ trợ quyết định kinh doanh.

### **Cấu trúc View**
```sql
CREATE OR REPLACE VIEW supermarket.v_product_revenue AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    pc.category_name,
    COUNT(DISTINCT si.invoice_id) AS total_transactions,
    SUM(sid.quantity) AS total_quantity_sold,
    SUM(sid.subtotal) AS total_revenue,
    AVG(sid.subtotal) AS avg_revenue_per_transaction,
    DATE_TRUNC('month', si.invoice_date) AS month_year
FROM supermarket.sales_invoice_details sid
INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
INNER JOIN supermarket.products p ON sid.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
GROUP BY p.product_id, p.product_code, p.product_name, pc.category_name, 
         DATE_TRUNC('month', si.invoice_date);
```

### **Chỉ số phân tích**
- **total_transactions**: Số giao dịch có chứa sản phẩm
- **total_quantity_sold**: Tổng số lượng bán ra
- **total_revenue**: Tổng doanh thu
- **avg_revenue_per_transaction**: Doanh thu trung bình/giao dịch

### **Ví dụ sử dụng**
```sql
-- Top 10 sản phẩm bán chạy tháng 12/2024
SELECT product_name, total_quantity_sold, total_revenue
FROM supermarket.v_product_revenue
WHERE month_year = '2024-12-01'
ORDER BY total_revenue DESC
LIMIT 10;

-- So sánh doanh thu theo tháng
SELECT 
    product_name,
    TO_CHAR(month_year, 'MM/YYYY') AS month,
    total_revenue,
    LAG(total_revenue) OVER (PARTITION BY product_id ORDER BY month_year) AS prev_month_revenue
FROM supermarket.v_product_revenue
WHERE product_id = 101
ORDER BY month_year;
```

---

## 6.2.4. **v_supplier_performance** - Hiệu suất Nhà cung cấp

### **Mục đích**
Đánh giá hiệu suất kinh doanh của các nhà cung cấp để tối ưu hóa mối quan hệ hợp tác.

### **Cấu trúc View**
```sql
CREATE OR REPLACE VIEW supermarket.v_supplier_performance AS
SELECT 
    s.supplier_id,
    s.supplier_code,
    s.supplier_name,
    COUNT(DISTINCT p.product_id) AS total_products,
    COUNT(DISTINCT po.order_id) AS total_orders,
    SUM(po.total_amount) AS total_purchase_amount,
    SUM(revenue.total_revenue) AS total_sales_revenue,
    SUM(revenue.total_revenue) - SUM(po.total_amount) AS profit_margin
FROM supermarket.suppliers s
LEFT JOIN supermarket.products p ON s.supplier_id = p.supplier_id
LEFT JOIN supermarket.purchase_orders po ON s.supplier_id = po.supplier_id
LEFT JOIN (
    SELECT 
        p.supplier_id,
        SUM(sid.subtotal) AS total_revenue
    FROM supermarket.sales_invoice_details sid
    INNER JOIN supermarket.products p ON sid.product_id = p.product_id
    GROUP BY p.supplier_id
) revenue ON s.supplier_id = revenue.supplier_id
WHERE s.is_active = true
GROUP BY s.supplier_id, s.supplier_code, s.supplier_name;
```

### **Chỉ số đánh giá**
- **total_products**: Số sản phẩm cung cấp
- **total_orders**: Số đơn nhập hàng
- **total_purchase_amount**: Tổng tiền nhập
- **total_sales_revenue**: Tổng doanh thu từ SP của NCC
- **profit_margin**: Lợi nhuận = Doanh thu - Chi phí nhập

### **Ví dụ sử dụng**
```sql
-- Xếp hạng nhà cung cấp theo lợi nhuận
SELECT supplier_name, total_purchase_amount, total_sales_revenue, profit_margin,
       ROUND((profit_margin * 100.0 / total_purchase_amount), 2) AS profit_percentage
FROM supermarket.v_supplier_performance
WHERE total_purchase_amount > 0
ORDER BY profit_margin DESC;
```

---

## 6.2.5. **v_customer_purchase_history** - Lịch sử Mua hàng

### **Mục đích**
Phân tích hành vi mua sắm của khách hàng để phát triển chương trình CRM và marketing.

### **Cấu trúc View**
```sql
CREATE OR REPLACE VIEW supermarket.v_customer_purchase_history AS
SELECT 
    c.customer_id,
    c.customer_code,
    c.full_name,
    c.phone,
    ml.level_name AS membership_level,
    c.total_spending,
    c.loyalty_points,
    COUNT(DISTINCT si.invoice_id) AS total_purchases,
    AVG(si.total_amount) AS avg_purchase_amount,
    MAX(si.invoice_date) AS last_purchase_date
FROM supermarket.customers c
LEFT JOIN supermarket.membership_levels ml ON c.membership_level_id = ml.level_id
LEFT JOIN supermarket.sales_invoices si ON c.customer_id = si.customer_id
GROUP BY c.customer_id, c.customer_code, c.full_name, c.phone, 
         ml.level_name, c.total_spending, c.loyalty_points;
```

### **Chỉ số khách hàng**
- **total_purchases**: Số lần mua hàng
- **avg_purchase_amount**: Giá trị đơn hàng trung bình
- **last_purchase_date**: Lần mua gần nhất
- **loyalty_points**: Điểm tích lũy hiện tại

### **Ví dụ sử dụng**
```sql
-- Top 20 khách hàng VIP
SELECT full_name, membership_level, total_spending, total_purchases, avg_purchase_amount
FROM supermarket.v_customer_purchase_history
WHERE total_spending > 0
ORDER BY total_spending DESC
LIMIT 20;

-- Khách hàng lâu không mua (> 30 ngày)
SELECT full_name, phone, last_purchase_date, 
       CURRENT_DATE - last_purchase_date::DATE AS days_since_last_purchase
FROM supermarket.v_customer_purchase_history
WHERE last_purchase_date < CURRENT_DATE - INTERVAL '30 days'
ORDER BY days_since_last_purchase DESC;
```

---

## 6.2.6. **v_low_stock_alert** - Cảnh báo Tồn kho thấp

### **Mục đích**
Cung cấp danh sách cảnh báo cụ thể về các sản phẩm cần bổ sung từ kho lên quầy.

### **Cấu trúc View**
```sql
CREATE OR REPLACE VIEW supermarket.v_low_stock_alert AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    pc.category_name,
    si.shelf_id,
    ds.shelf_code,
    ds.shelf_name,
    si.current_quantity AS shelf_quantity,
    p.low_stock_threshold,
    wi.warehouse_quantity,
    sl.max_quantity AS shelf_max_capacity,
    CASE 
        WHEN si.current_quantity = 0 THEN 'Out of stock on shelf'
        WHEN si.current_quantity <= p.low_stock_threshold THEN 'Low stock on shelf'
        ELSE 'Sufficient'
    END AS alert_type
FROM supermarket.shelf_inventory si
INNER JOIN supermarket.products p ON si.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
LEFT JOIN supermarket.shelf_layout sl ON si.shelf_id = sl.shelf_id AND si.product_id = sl.product_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS warehouse_quantity
    FROM supermarket.warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
WHERE si.current_quantity <= p.low_stock_threshold
   AND COALESCE(wi.warehouse_quantity, 0) > 0;
```

### **Điều kiện hiển thị**
- Chỉ hiện sản phẩm có tồn quầy ≤ ngưỡng cảnh báo
- Phải có hàng trong kho để có thể bổ sung

### **Ví dụ sử dụng**
```sql
-- Danh sách cần bổ sung hàng gấp
SELECT shelf_code, product_name, shelf_quantity, low_stock_threshold, warehouse_quantity
FROM supermarket.v_low_stock_alert
WHERE alert_type = 'Out of stock on shelf'
ORDER BY shelf_code;

-- Tính toán số lượng cần bổ sung
SELECT 
    product_name,
    shelf_code,
    shelf_quantity,
    shelf_max_capacity,
    LEAST(shelf_max_capacity - shelf_quantity, warehouse_quantity) AS can_replenish
FROM supermarket.v_low_stock_alert
WHERE warehouse_quantity > 0;
```

---

## **Tổng quan Views System**

### **Thống kê sử dụng**
| View | Mục đích chính | Bảng liên quan | Độ phức tạp |
|------|----------------|----------------|-------------|
| `v_product_inventory_summary` | Dashboard tồn kho | 5 bảng | Cao |
| `v_expired_products` | Quản lý hạn SD | 4 bảng | Trung bình |
| `v_product_revenue` | Phân tích doanh thu | 3 bảng | Trung bình |
| `v_supplier_performance` | Đánh giá NCC | 4 bảng | Cao |
| `v_customer_purchase_history` | CRM & Marketing | 3 bảng | Trung bình |
| `v_low_stock_alert` | Cảnh báo bổ sung | 6 bảng | Cao |

### **Lợi ích của Views**
1. **Đơn giản hóa truy vấn**: Che giấu độ phức tạp JOIN
2. **Tính nhất quán**: Logic nghiệp vụ chuẩn hóa
3. **Bảo mật**: Hạn chế truy cập trực tiếp bảng
4. **Hiệu suất**: Có thể tối ưu hóa bằng materialized views
5. **Tái sử dụng**: Dùng chung cho nhiều ứng dụng

### **Performance Tips**
- Views có thể được chuyển thành **Materialized Views** cho hiệu suất cao hơn
- Sử dụng **Index** trên các cột trong WHERE clause
- **LIMIT** khi cần thiết để tránh tải quá nhiều dữ liệu
- **Partitioning** cho bảng lớn như `sales_invoice_details`
