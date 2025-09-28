# 6.2. VIEWS - KHUNG NHÌN DỮ LIỆU

## Tổng quan

Hệ thống triển khai **9 Views** chuyên biệt để cung cấp khung nhìn tổng hợp từ nhiều bảng dữ liệu, phục vụ các nhu cầu báo cáo và phân tích khác nhau. Mỗi view được tối ưu hóa cho một nghiệp vụ cụ thể và giảm thiểu độ phức tạp khi truy vấn.

---

## 6.2.1. **v_expiring_products** - Sản phẩm Sắp hết hạn

### **Mục đích**
Theo dõi các sản phẩm trên quầy sắp hết hạn (trong vòng 7 ngày) để kịp thời áp dụng giảm giá hoặc xử lý.

### **Cấu trúc View**
```sql
CREATE VIEW supermarket.v_expiring_products AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    sbi.batch_code,
    sbi.expiry_date,
    sbi.quantity,
    sbi.shelf_id,
    ds.shelf_name,
    sbi.current_price,
    sbi.discount_percent,
    (sbi.expiry_date - CURRENT_DATE) AS days_remaining
FROM shelf_batch_inventory sbi
JOIN products p ON sbi.product_id = p.product_id
JOIN product_categories c ON p.category_id = c.category_id
JOIN display_shelves ds ON sbi.shelf_id = ds.shelf_id
WHERE sbi.expiry_date <= (CURRENT_DATE + INTERVAL '7 days')
  AND sbi.quantity > 0
ORDER BY sbi.expiry_date;
```

### **Logic nghiệp vụ**
- **Thời gian cảnh báo**: Trong vòng 7 ngày sắp hết hạn
- **Chỉ hiện hàng còn số lượng**: `quantity > 0`
- **Sắp xếp theo hạn sử dụng**: Hết hạn sớm nhất lên đầu

### **Ví dụ sử dụng**
```sql
-- Tìm hàng cần giảm giá gấp (còn 1-2 ngày)
SELECT product_name, batch_code, days_remaining, current_price, discount_percent
FROM supermarket.v_expiring_products
WHERE days_remaining <= 2
ORDER BY days_remaining;

-- Thống kê theo danh mục
SELECT category_name, COUNT(*) as products_expiring, SUM(quantity) as total_qty
FROM supermarket.v_expiring_products
GROUP BY category_name
ORDER BY products_expiring DESC;
```

---

## 6.2.2. **v_low_shelf_products** - Sản phẩm Thiếu trên Quầy

### **Mục đích**
Cảnh báo những sản phẩm có tồn kho trên quầy thấp hơn ngưỡng nhưng vẫn còn hàng trong kho để bổ sung.

### **Cấu trúc View**
```sql
CREATE VIEW supermarket.v_low_shelf_products AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    p.low_stock_threshold,
    COALESCE(wi.total_warehouse, 0) AS warehouse_quantity,
    COALESCE(si.total_shelf, 0) AS shelf_quantity,
    (COALESCE(wi.total_warehouse, 0) + COALESCE(si.total_shelf, 0)) AS total_quantity,
    CASE 
        WHEN p.low_stock_threshold > 0 THEN 
            ROUND((100.0 * COALESCE(si.total_shelf, 0)) / p.low_stock_threshold, 2)
        ELSE 0 
    END AS shelf_fill_percentage
FROM products p
LEFT JOIN product_categories c ON p.category_id = c.category_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS total_warehouse
    FROM warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) AS total_shelf
    FROM shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id
WHERE COALESCE(si.total_shelf, 0) < p.low_stock_threshold
  AND COALESCE(wi.total_warehouse, 0) > 0
  AND p.low_stock_threshold > 0
ORDER BY shelf_fill_percentage, si.total_shelf;
```

### **Logic nghiệp vụ**
- **Điều kiện**: Tồn quầy < ngưỡng cảnh báo ĐỂ kho > 0
- **Tính phần trăm lấp đầy**: `(tồn_quầy / ngưỡng_cảnh_báo) * 100%`
- **Ưu tiên**: Sản phẩm có % thấp nhất

### **Ví dụ sử dụng**
```sql
-- Top 10 sản phẩm cần bổ sung gấp
SELECT product_name, shelf_quantity, low_stock_threshold, warehouse_quantity, shelf_fill_percentage
FROM supermarket.v_low_shelf_products
ORDER BY shelf_fill_percentage ASC
LIMIT 10;
```

---

## 6.2.3. **v_low_stock_products** - Sản phẩm Thiếu tổng thể

### **Mục đích**
Tìm các sản phẩm có tổng tồn kho (kho + quầy) thấp hơn ngưỡng cảnh báo.

### **Cấu trúc View**
```sql
CREATE VIEW supermarket.v_low_stock_products AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    p.low_stock_threshold,
    COALESCE(wi.total_warehouse, 0) AS warehouse_quantity,
    COALESCE(si.total_shelf, 0) AS shelf_quantity,
    (COALESCE(wi.total_warehouse, 0) + COALESCE(si.total_shelf, 0)) AS total_quantity
FROM products p
LEFT JOIN product_categories c ON p.category_id = c.category_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS total_warehouse
    FROM warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) AS total_shelf
    FROM shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id
WHERE (COALESCE(wi.total_warehouse, 0) + COALESCE(si.total_shelf, 0)) < p.low_stock_threshold;
```

### **Ví dụ sử dụng**
```sql
-- Danh sách cần đặt hàng bổ sung
SELECT product_name, total_quantity, low_stock_threshold, 
       (low_stock_threshold - total_quantity) AS need_to_order
FROM supermarket.v_low_stock_products
ORDER BY need_to_order DESC;
```

---

## 6.2.4. **v_product_overview** - Tổng quan Sản phẩm

### **Mục đích**
Cung cấp cái nhìn tổng quan về tất cả sản phẩm với thông tin giá và tồn kho.

### **Cấu trúc View**
```sql
CREATE VIEW supermarket.v_product_overview AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    s.supplier_name,
    p.selling_price,
    p.import_price,
    COALESCE(wi.total_warehouse, 0) AS warehouse_quantity,
    COALESCE(si.total_shelf, 0) AS shelf_quantity,
    (COALESCE(wi.total_warehouse, 0) + COALESCE(si.total_shelf, 0)) AS total_quantity
FROM products p
LEFT JOIN product_categories c ON p.category_id = c.category_id
LEFT JOIN suppliers s ON p.supplier_id = s.supplier_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS total_warehouse
    FROM warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) AS total_shelf
    FROM shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id;
```

### **Ví dụ sử dụng**
```sql
-- Tổng quan các sản phẩm theo nhà cung cấp
SELECT supplier_name, COUNT(*) as product_count, 
       SUM(total_quantity) as total_stock_value
FROM supermarket.v_product_overview
GROUP BY supplier_name
ORDER BY product_count DESC;
```

---

## 6.2.5. **v_product_revenue** - Doanh thu theo Sản phẩm

### **Mục đích**
Phân tích hiệu suất kinh doanh của từng sản phẩm dựa trên dữ liệu bán hàng.

### **Cấu trúc View**
```sql
CREATE VIEW supermarket.v_product_revenue AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    SUM(sid.quantity) AS total_sold,
    SUM(sid.subtotal) AS total_revenue,
    COUNT(DISTINCT si.invoice_id) AS transaction_count
FROM sales_invoice_details sid
JOIN products p ON sid.product_id = p.product_id
JOIN product_categories c ON p.category_id = c.category_id
JOIN sales_invoices si ON sid.invoice_id = si.invoice_id
GROUP BY p.product_id, p.product_code, p.product_name, c.category_name;
```

### **Ví dụ sử dụng**
```sql
-- Top 10 sản phẩm bán chạy nhất
SELECT product_name, total_sold, total_revenue, transaction_count
FROM supermarket.v_product_revenue
ORDER BY total_revenue DESC
LIMIT 10;

-- Phân tích theo danh mục
SELECT category_name, 
       SUM(total_sold) as category_sold,
       SUM(total_revenue) as category_revenue,
       COUNT(*) as product_count
FROM supermarket.v_product_revenue
GROUP BY category_name
ORDER BY category_revenue DESC;
```

---

## 6.2.6. **v_shelf_status** - Trạng thái Quầy hàng

### **Mục đích**
Theo dõi tình trạng sử dụng và hiệu suất của các quầy hàng.

### **Cấu trúc View**
```sql
CREATE VIEW supermarket.v_shelf_status AS
SELECT 
    ds.shelf_id,
    ds.shelf_name,
    pc.category_name,
    ds.location,
    COUNT(si.product_id) AS product_count,
    SUM(si.current_quantity) AS total_items,
    SUM(sl.max_quantity) AS total_capacity,
    CASE 
        WHEN SUM(sl.max_quantity) > 0 THEN 
            ROUND((100.0 * SUM(si.current_quantity)) / SUM(sl.max_quantity), 2)
        ELSE 0 
    END AS fill_percentage
FROM display_shelves ds
JOIN product_categories pc ON ds.category_id = pc.category_id
LEFT JOIN shelf_inventory si ON ds.shelf_id = si.shelf_id
LEFT JOIN shelf_layout sl ON ds.shelf_id = sl.shelf_id
GROUP BY ds.shelf_id, ds.shelf_name, pc.category_name, ds.location;
```

### **Ví dụ sử dụng**
```sql
-- Quầy hàng cần sắp xếp lại (quá tải hoặc trống)
SELECT shelf_name, category_name, total_items, total_capacity, fill_percentage
FROM supermarket.v_shelf_status
WHERE fill_percentage < 30 OR fill_percentage > 95
ORDER BY fill_percentage;
```

---

## 6.2.7. **v_supplier_revenue** - Doanh thu theo Nhà cung cấp

### **Mục đích**
Đánh giá hiệu suất kinh doanh của các nhà cung cấp.

### **Cấu trúc View**
```sql
CREATE VIEW supermarket.v_supplier_revenue AS
SELECT 
    s.supplier_id,
    s.supplier_name,
    s.contact_person,
    COUNT(DISTINCT p.product_id) AS product_count,
    SUM(pr.total_sold) AS total_units_sold,
    SUM(pr.total_revenue) AS total_revenue
FROM suppliers s
JOIN products p ON s.supplier_id = p.supplier_id
LEFT JOIN v_product_revenue pr ON p.product_id = pr.product_id
GROUP BY s.supplier_id, s.supplier_name, s.contact_person
ORDER BY SUM(pr.total_revenue) DESC NULLS LAST;
```

### **Ví dụ sử dụng**
```sql
-- Xếp hạng nhà cung cấp theo doanh thu
SELECT supplier_name, product_count, total_units_sold, total_revenue
FROM supermarket.v_supplier_revenue
WHERE total_revenue > 0
ORDER BY total_revenue DESC
LIMIT 5;
```

---

## 6.2.8. **v_vip_customers** - Khách hàng VIP

### **Mục đích**
Phân tích khách hàng có giá trị cao để phát triển chương trình CRM.

### **Cấu trúc View**
```sql
CREATE VIEW supermarket.v_vip_customers AS
SELECT 
    c.customer_id,
    c.full_name,
    c.phone,
    c.email,
    ml.level_name AS membership_level,
    c.total_spending,
    c.loyalty_points,
    COUNT(si.invoice_id) AS purchase_count,
    MAX(si.invoice_date) AS last_purchase
FROM customers c
LEFT JOIN membership_levels ml ON c.membership_level_id = ml.level_id
LEFT JOIN sales_invoices si ON c.customer_id = si.customer_id
GROUP BY c.customer_id, c.full_name, c.phone, c.email, 
         ml.level_name, c.total_spending, c.loyalty_points
ORDER BY c.total_spending DESC;
```

### **Ví dụ sử dụng**
```sql
-- Top 20 khách hàng VIP
SELECT full_name, membership_level, total_spending, purchase_count, last_purchase
FROM supermarket.v_vip_customers
WHERE total_spending > 1000000
LIMIT 20;
```

---

## 6.2.9. **v_warehouse_empty_products** - Sản phẩm Hết kho nhưng còn Quầy

### **Mục đích**
Tìm các sản phẩm đã hết hàng trong kho nhưng vẫn còn trên quầy bán.

### **Cấu trúc View**
```sql
CREATE VIEW supermarket.v_warehouse_empty_products AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    p.low_stock_threshold,
    COALESCE(wi.total_warehouse, 0) AS warehouse_quantity,
    COALESCE(si.total_shelf, 0) AS shelf_quantity
FROM products p
LEFT JOIN product_categories c ON p.category_id = c.category_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS total_warehouse
    FROM warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) AS total_shelf
    FROM shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id
WHERE COALESCE(wi.total_warehouse, 0) = 0 
  AND COALESCE(si.total_shelf, 0) > 0;
```

### **Ví dụ sử dụng**
```sql
-- Danh sách cần nhập hàng gấp
SELECT product_name, category_name, shelf_quantity
FROM supermarket.v_warehouse_empty_products
ORDER BY shelf_quantity DESC;
```

---

## **Tổng quan Views System**

### **Thống kê sử dụng**
| View | Mục đích chính | Bảng liên quan | Độ phức tạp |
|------|----------------|----------------|-------------|
| `v_expiring_products` | Quản lý hạn SD | 4 bảng | Trung bình |
| `v_low_shelf_products` | Cảnh báo bổ sung quầy | 5 bảng | Cao |
| `v_low_stock_products` | Cảnh báo tồn kho thấp | 5 bảng | Cao |
| `v_product_overview` | Dashboard tổng quan | 5 bảng | Cao |
| `v_product_revenue` | Phân tích doanh thu | 4 bảng | Trung bình |
| `v_shelf_status` | Quản lý quầy hàng | 4 bảng | Trung bình |
| `v_supplier_revenue` | Đánh giá NCC | 3 bảng | Trung bình |
| `v_vip_customers` | CRM & Marketing | 3 bảng | Trung bình |
| `v_warehouse_empty_products` | Cảnh báo nhập hàng | 5 bảng | Cao |

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