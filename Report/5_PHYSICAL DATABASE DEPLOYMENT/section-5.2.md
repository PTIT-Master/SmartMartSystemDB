# 5.2. INDEX VÀ TỐI ƯU HÓA

## 5.2.1. Index cho khóa chính/ngoại

### **Index tự động cho PRIMARY KEY**

PostgreSQL tự động tạo unique index cho tất cả PRIMARY KEY constraints:

```sql
-- Tự động tạo khi define PRIMARY KEY
CREATE TABLE supermarket.products (
    product_id BIGINT NOT NULL,
    -- Tự động có: products_pkey (product_id)
    CONSTRAINT products_pkey PRIMARY KEY (product_id)
);

-- Tương đương với:
-- CREATE UNIQUE INDEX products_pkey ON supermarket.products (product_id);
```

### **Index tự động cho UNIQUE constraints**

```sql
-- Các UNIQUE constraint cũng tự động có index
CONSTRAINT uni_products_product_code UNIQUE (product_code),
-- → Tạo index: uni_products_product_code

CONSTRAINT uni_customers_phone UNIQUE (phone),
-- → Tạo index: uni_customers_phone

CONSTRAINT uni_employees_email UNIQUE (email),
-- → Tạo index: uni_employees_email
```

### **Index thủ công cho FOREIGN KEY**

PostgreSQL không tự động tạo index cho foreign key, cần tạo thủ công để tối ưu JOIN:

```sql
-- Index cho foreign key relationships
CREATE INDEX idx_products_category ON supermarket.products (category_id);
CREATE INDEX idx_products_supplier ON supermarket.products (supplier_id);
CREATE INDEX idx_customer_membership ON supermarket.customers (membership_level_id);
CREATE INDEX idx_employee_position ON supermarket.employees (position_id);
```

**Lý do cần index cho FK:**
- Tăng tốc JOIN operations
- Tối ưu CASCADE DELETE/UPDATE
- Cải thiện hiệu suất referential integrity checks

## 5.2.2. Index cho các cột thường query

### **Index cho các cột tìm kiếm thường xuyên**

#### **Index cho customer lookup**

```sql
-- Tìm kiếm khách hàng theo total spending (membership upgrade)
CREATE INDEX idx_customer_spending ON supermarket.customers (total_spending);

-- Hỗ trợ query:
-- SELECT * FROM customers WHERE total_spending >= 1000000;
-- ORDER BY total_spending DESC;
```

#### **Index cho inventory management**

```sql
-- Tìm kiếm theo số lượng tồn kho (low stock alert)
CREATE INDEX idx_shelf_inv_quantity ON supermarket.shelf_inventory (current_quantity);

-- Tìm kiếm product trong shelf inventory
CREATE INDEX idx_shelf_inv_product ON supermarket.shelf_inventory (product_id);

-- Hỗ trợ query:
-- SELECT * FROM shelf_inventory WHERE current_quantity <= 10;
-- SELECT * FROM shelf_inventory WHERE product_id = ?;
```

#### **Index cho batch tracking và expiry**

```sql
-- Tìm kiếm theo batch code
CREATE INDEX idx_shelf_batch_code ON supermarket.shelf_batch_inventory (batch_code);
CREATE INDEX idx_stock_transfers_batch_code ON supermarket.stock_transfers (batch_code);

-- Tìm kiếm theo hạn sử dụng
CREATE INDEX idx_warehouse_inv_expiry ON supermarket.warehouse_inventory (expiry_date);
CREATE INDEX idx_shelf_batch_expiry ON supermarket.shelf_batch_inventory (expiry_date);

-- Hỗ trợ queries:
-- SELECT * FROM warehouse_inventory WHERE expiry_date < CURRENT_DATE;
-- SELECT * FROM shelf_batch_inventory WHERE expiry_date <= CURRENT_DATE + INTERVAL '3 days';
```

#### **Index cho product management**

```sql
-- Tìm kiếm warehouse inventory theo product
CREATE INDEX idx_warehouse_inv_product ON supermarket.warehouse_inventory (product_id);

-- Tìm kiếm shelf batch theo product
CREATE INDEX idx_shelf_batch_product ON supermarket.shelf_batch_inventory (product_id);

-- Hỗ trợ aggregate queries:
-- SELECT product_id, SUM(quantity) FROM warehouse_inventory GROUP BY product_id;
-- SELECT product_id, SUM(quantity) FROM shelf_batch_inventory GROUP BY product_id;
```

## 5.2.3. Index cho báo cáo thống kê

### **Index cho sales reporting**

#### **Index cho customer analysis**

```sql
-- Phân tích giao dịch theo khách hàng
CREATE INDEX idx_sales_invoice_customer ON supermarket.sales_invoices (customer_id);

-- Phân tích theo nhân viên bán hàng
CREATE INDEX idx_sales_invoice_employee ON supermarket.sales_invoices (employee_id);
```

#### **Index cho time-based reporting**

```sql
-- Báo cáo theo thời gian (quan trọng nhất)
CREATE INDEX idx_sales_invoice_date ON supermarket.sales_invoices (invoice_date);

-- Hỗ trợ queries:
-- SELECT * FROM sales_invoices 
-- WHERE invoice_date >= '2024-01-01' AND invoice_date < '2024-02-01';

-- SELECT DATE_TRUNC('month', invoice_date), SUM(total_amount)
-- FROM sales_invoices 
-- WHERE invoice_date >= '2024-01-01'
-- GROUP BY DATE_TRUNC('month', invoice_date);
```

#### **Index cho product sales analysis**

```sql
-- Phân tích bán hàng theo sản phẩm
CREATE INDEX idx_sales_details_product ON supermarket.sales_invoice_details (product_id);

-- Hỗ trợ queries:
-- SELECT product_id, SUM(quantity), SUM(subtotal)
-- FROM sales_invoice_details 
-- WHERE invoice_id IN (SELECT invoice_id FROM sales_invoices 
--                      WHERE EXTRACT(MONTH FROM invoice_date) = 12)
-- GROUP BY product_id;
```

### **Composite Index cho complex queries**

#### **Index tổng hợp cho batch expiry tracking**

```sql
-- Index phức hợp cho warehouse inventory với expiry
CREATE INDEX idx_shelf_batch_inventory_batch_code 
    ON supermarket.shelf_batch_inventory (batch_code);

CREATE INDEX idx_shelf_batch_inventory_expiry_date 
    ON supermarket.shelf_batch_inventory (expiry_date);

-- Có thể tạo composite index nếu query thường kết hợp:
-- CREATE INDEX idx_shelf_batch_product_expiry 
--     ON supermarket.shelf_batch_inventory (product_id, expiry_date);
```

### **Chiến lược Index optimization**

#### **Partial Index cho active records**

```sql
-- Chỉ index các bản ghi active (tiết kiệm không gian)
CREATE INDEX idx_products_active 
    ON supermarket.products (product_id, product_name) 
    WHERE is_active = true;

CREATE INDEX idx_customers_active 
    ON supermarket.customers (customer_code, full_name) 
    WHERE is_active = true;
```

#### **Functional Index cho specific needs**

```sql
-- Index cho tìm kiếm không phân biệt hoa thường
CREATE INDEX idx_products_name_lower 
    ON supermarket.products (LOWER(product_name));

-- Index cho date functions
CREATE INDEX idx_sales_invoice_year_month 
    ON supermarket.sales_invoices (EXTRACT(YEAR FROM invoice_date), 
                                   EXTRACT(MONTH FROM invoice_date));
```

### **Index Performance Analysis**

#### **Monitoring Index Usage**

```sql
-- Kiểm tra việc sử dụng index
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes 
WHERE schemaname = 'supermarket'
ORDER BY idx_scan DESC;

-- Tìm index không được sử dụng
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan
FROM pg_stat_user_indexes 
WHERE schemaname = 'supermarket' 
  AND idx_scan = 0;
```

#### **Index Size Analysis**

```sql
-- Kiểm tra kích thước index
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes 
WHERE schemaname = 'supermarket'
ORDER BY pg_relation_size(indexrelid) DESC;
```

### **Best Practices cho Index Design**

#### **1. Index Cardinality**

```sql
-- High cardinality (tốt cho index): customer_id, product_id, invoice_no
-- Medium cardinality: category_id, supplier_id, employee_id  
-- Low cardinality (cần cân nhắc): is_active, status, gender
```

#### **2. Query Pattern-based Indexing**

```sql
-- Phân tích query patterns từ application
-- Ví dụ: Nếu thường query "products by category with low stock"
CREATE INDEX idx_products_category_stock 
    ON supermarket.products (category_id, low_stock_threshold);

-- JOIN pattern: sales_invoices với sales_invoice_details
-- Already có idx_sales_details_product, idx_sales_invoice_customer, etc.
```

#### **3. Index Maintenance**

```sql
-- Tự động VACUUM và REINDEX thông qua pg_cron hoặc scheduled job
-- REINDEX INDEX idx_sales_invoice_date; -- Định kỳ cho index quan trọng

-- ANALYZE để cập nhật statistics
-- ANALYZE supermarket.sales_invoices;
-- ANALYZE supermarket.products;
```

### **Impact của Index lên Performance**

#### **Query Performance Improvement**

```sql
-- Trước khi có index (Seq Scan):
EXPLAIN ANALYZE 
SELECT * FROM supermarket.products WHERE category_id = 1;
-- → Sequential Scan on products (cost=0.00..15.00 rows=500 width=100)

-- Sau khi có index (Index Scan):  
EXPLAIN ANALYZE 
SELECT * FROM supermarket.products WHERE category_id = 1;
-- → Index Scan using idx_products_category (cost=0.29..8.30 rows=5 width=100)
```

#### **Trade-offs**

**Ưu điểm:**
- Tăng tốc SELECT, WHERE, ORDER BY, JOIN
- Tăng tốc uniqueness checking
- Cải thiện FOREIGN KEY constraint checking

**Nhược điểm:**
- Tăng thời gian INSERT/UPDATE/DELETE
- Chiếm thêm disk space (30-50% table size)
- Cần maintenance (VACUUM, REINDEX)

### **Tổng kết Index Strategy**

Hệ thống đã được tối ưu với:

1. **25+ indexes** covering:
   - Primary keys (tự động)
   - Foreign keys (thủ công)
   - Unique constraints (tự động)
   - Query performance (thủ công)

2. **Focus areas:**
   - Customer lookup và membership  
   - Product inventory management
   - Sales reporting và analytics
   - Batch tracking và expiry management

3. **Balanced approach:**
   - Không over-index (tránh slow writes)
   - Priority cho business-critical queries
   - Monitor và adjust based on usage patterns

Index strategy này đảm bảo hệ thống có performance tốt cho cả OLTP (giao dịch) và OLAP (báo cáo) workloads.
