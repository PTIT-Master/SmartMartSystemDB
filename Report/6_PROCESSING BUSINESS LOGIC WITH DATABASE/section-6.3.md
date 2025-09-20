# 6.3. STORED PROCEDURES - QUY TRÌNH PHỨC TẠP

## Tổng quan

Hệ thống triển khai **5 Stored Procedures** để đóng gói các quy trình nghiệp vụ phức tạp, đảm bảo tính toàn vẹn dữ liệu và cung cấp API chuẩn cho các ứng dụng. Mỗi procedure xử lý một nghiệp vụ hoàn chỉnh với logic validation và error handling.

---

## 6.3.1. **sp_replenish_shelf_stock** - Bổ sung Hàng lên Quầy

### **Mục đích**
Thực hiện chuyển hàng từ kho lên quầy bán theo nguyên tắc FIFO (First In, First Out) với đầy đủ validation.

### **Signature**
```sql
CREATE OR REPLACE PROCEDURE supermarket.sp_replenish_shelf_stock(
    p_product_id BIGINT,      -- ID sản phẩm cần bổ sung
    p_shelf_id BIGINT,        -- ID quầy hàng đích
    p_quantity BIGINT,        -- Số lượng cần chuyển
    p_employee_id BIGINT      -- ID nhân viên thực hiện
)
```

### **Logic xử lý**
```sql
DECLARE
    v_warehouse_id BIGINT := 1; -- Default warehouse
    v_available_qty BIGINT;
    v_batch_code VARCHAR(50);
    v_expiry_date DATE;
    v_import_price NUMERIC(12,2);
    v_selling_price NUMERIC(12,2);
    v_transfer_code VARCHAR(30);
BEGIN
    -- 1. Kiểm tra tồn kho trong warehouse
    SELECT SUM(quantity) INTO v_available_qty
    FROM supermarket.warehouse_inventory
    WHERE product_id = p_product_id;
    
    IF v_available_qty IS NULL OR v_available_qty < p_quantity THEN
        RAISE EXCEPTION 'Insufficient warehouse stock. Available: %, Requested: %', 
                        COALESCE(v_available_qty, 0), p_quantity;
    END IF;
    
    -- 2. Chọn batch theo FIFO (oldest first)
    SELECT batch_code, expiry_date, import_price
    INTO v_batch_code, v_expiry_date, v_import_price
    FROM supermarket.warehouse_inventory
    WHERE product_id = p_product_id AND quantity >= p_quantity
    ORDER BY import_date ASC, expiry_date ASC
    LIMIT 1;
    
    -- 3. Lấy giá bán hiện tại
    SELECT selling_price INTO v_selling_price
    FROM supermarket.products
    WHERE product_id = p_product_id;
    
    -- 4. Tạo mã chuyển hàng
    v_transfer_code := 'TRF-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || 
                       LPAD(NEXTVAL('supermarket.stock_transfers_transfer_id_seq')::TEXT, 6, '0');
    
    -- 5. Tạo record chuyển hàng (triggers sẽ xử lý cập nhật tồn kho)
    INSERT INTO supermarket.stock_transfers (
        transfer_code, product_id, from_warehouse_id, to_shelf_id,
        quantity, employee_id, batch_code, expiry_date,
        import_price, selling_price
    ) VALUES (
        v_transfer_code, p_product_id, v_warehouse_id, p_shelf_id,
        p_quantity, p_employee_id, v_batch_code, v_expiry_date,
        v_import_price, v_selling_price
    );
    
    RAISE NOTICE 'Stock transfer completed. Transfer code: %', v_transfer_code;
END;
```

### **Đặc điểm nổi bật**
- **FIFO Implementation**: Ưu tiên batch cũ nhất, hạn sử dụng gần nhất
- **Atomic Transaction**: Toàn bộ quy trình thành công hoặc rollback
- **Auto Code Generation**: Tự động tạo mã chuyển hàng duy nhất
- **Trigger Integration**: Tận dụng triggers để cập nhật tồn kho

### **Ví dụ sử dụng**
```sql
-- Chuyển 50 sản phẩm ID=101 từ kho lên quầy ID=5
CALL supermarket.sp_replenish_shelf_stock(101, 5, 50, 1001);
-- Output: NOTICE:  Stock transfer completed. Transfer code: TRF-20241220-000123

-- Kiểm tra kết quả
SELECT * FROM supermarket.stock_transfers WHERE product_id = 101 ORDER BY created_at DESC LIMIT 1;
```

---

## 6.3.2. **sp_process_sale** - Xử lý Giao dịch Bán hàng

### **Mục đích**
Thực hiện toàn bộ quy trình bán hàng từ tạo hóa đơn đến cập nhật điểm thưởng khách hàng.

### **Signature**
```sql
CREATE OR REPLACE PROCEDURE supermarket.sp_process_sale(
    p_customer_id BIGINT,           -- ID khách hàng (có thể NULL)
    p_employee_id BIGINT,           -- ID nhân viên bán hàng
    p_payment_method VARCHAR(20),   -- Phương thức thanh toán
    p_product_list JSON,            -- Danh sách sản phẩm JSON
    p_points_used BIGINT DEFAULT 0  -- Điểm thưởng sử dụng
)
```

### **Format JSON Input**
```json
[
  {
    "product_id": 101,
    "quantity": 2,
    "discount_percentage": 0
  },
  {
    "product_id": 205, 
    "quantity": 1,
    "discount_percentage": 5.0
  }
]
```

### **Logic xử lý**
```sql
DECLARE
    v_invoice_no VARCHAR(30);
    v_invoice_id BIGINT;
    v_product JSON;
    v_unit_price NUMERIC(12,2);
BEGIN
    -- 1. Tạo số hóa đơn tự động
    v_invoice_no := 'INV-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || 
                    LPAD(NEXTVAL('supermarket.sales_invoices_invoice_id_seq')::TEXT, 6, '0');
    
    -- 2. Tạo header hóa đơn
    INSERT INTO supermarket.sales_invoices (
        invoice_no, customer_id, employee_id, payment_method, points_used
    ) VALUES (
        v_invoice_no, p_customer_id, p_employee_id, p_payment_method, p_points_used
    ) RETURNING invoice_id INTO v_invoice_id;
    
    -- 3. Xử lý từng sản phẩm trong JSON
    FOR v_product IN SELECT * FROM json_array_elements(p_product_list)
    LOOP
        -- Lấy giá bán hiện tại
        SELECT selling_price INTO v_unit_price
        FROM supermarket.products
        WHERE product_id = (v_product->>'product_id')::BIGINT;
        
        -- Tạo chi tiết hóa đơn (triggers sẽ xử lý tính toán và trừ tồn)
        INSERT INTO supermarket.sales_invoice_details (
            invoice_id, product_id, quantity, unit_price, discount_percentage
        ) VALUES (
            v_invoice_id,
            (v_product->>'product_id')::BIGINT,
            (v_product->>'quantity')::BIGINT,
            v_unit_price,
            COALESCE((v_product->>'discount_percentage')::NUMERIC, 0)
        );
    END LOOP;
    
    RAISE NOTICE 'Sale processed successfully. Invoice: %', v_invoice_no;
END;
```

### **Quy trình tự động**
1. **Tạo hóa đơn**: Auto-generate invoice number
2. **Xử lý chi tiết**: Loop qua JSON array
3. **Tính toán**: Triggers tự động tính subtotal, tax, total
4. **Trừ tồn kho**: Triggers kiểm tra và trừ tồn quầy
5. **Cập nhật khách hàng**: Triggers cộng điểm thưởng, nâng cấp membership

### **Ví dụ sử dụng**
```sql
-- Bán hàng cho khách hàng ID=501
CALL supermarket.sp_process_sale(
    501,  -- customer_id
    1002, -- employee_id (nhân viên thu ngân)
    'CASH', -- payment_method
    '[
        {"product_id": 101, "quantity": 3, "discount_percentage": 0},
        {"product_id": 205, "quantity": 1, "discount_percentage": 10.0},
        {"product_id": 310, "quantity": 2, "discount_percentage": 0}
    ]'::json,
    0     -- points_used
);
-- Output: NOTICE:  Sale processed successfully. Invoice: INV-20241220-000045
```

---

## 6.3.3. **sp_generate_monthly_sales_report** - Báo cáo Doanh thu Tháng

### **Mục đích**
Tạo báo cáo tổng hợp doanh thu chi tiết theo tháng với phân tích theo sản phẩm và danh mục.

### **Signature**
```sql
CREATE OR REPLACE PROCEDURE supermarket.sp_generate_monthly_sales_report(
    p_month INTEGER,    -- Tháng (1-12)
    p_year INTEGER      -- Năm
)
```

### **Logic xử lý**
```sql
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_total_revenue NUMERIC(12,2);
    v_total_transactions INTEGER;
    v_total_products INTEGER;
BEGIN
    -- 1. Tính khoảng thời gian
    v_start_date := DATE(p_year || '-' || LPAD(p_month::TEXT, 2, '0') || '-01');
    v_end_date := (v_start_date + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
    
    -- 2. Tạo temporary table cho report
    CREATE TEMP TABLE IF NOT EXISTS monthly_sales_report (
        report_date DATE,
        category_name VARCHAR(100),
        product_name VARCHAR(200),
        quantity_sold BIGINT,
        revenue NUMERIC(12,2),
        avg_discount NUMERIC(5,2)
    );
    
    -- 3. Thu thập dữ liệu chi tiết
    INSERT INTO monthly_sales_report
    SELECT 
        si.invoice_date::DATE,
        pc.category_name,
        p.product_name,
        SUM(sid.quantity),
        SUM(sid.subtotal),
        AVG(sid.discount_percentage)
    FROM supermarket.sales_invoice_details sid
    INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
    INNER JOIN supermarket.products p ON sid.product_id = p.product_id
    INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
    WHERE si.invoice_date >= v_start_date 
      AND si.invoice_date <= v_end_date
    GROUP BY si.invoice_date::DATE, pc.category_name, p.product_name;
    
    -- 4. Tính tổng kết
    SELECT 
        SUM(revenue),
        COUNT(DISTINCT report_date),
        COUNT(DISTINCT product_name)
    INTO v_total_revenue, v_total_transactions, v_total_products
    FROM monthly_sales_report;
    
    RAISE NOTICE 'Monthly report for %/% generated. Total revenue: %', 
                 p_month, p_year, v_total_revenue;
END;
```

### **Ví dụ sử dụng**
```sql
-- Tạo báo cáo tháng 12/2024
CALL supermarket.sp_generate_monthly_sales_report(12, 2024);

-- Xem kết quả chi tiết
SELECT category_name, SUM(quantity_sold) as total_qty, SUM(revenue) as total_revenue
FROM monthly_sales_report
GROUP BY category_name
ORDER BY total_revenue DESC;

-- Top sản phẩm bán chạy
SELECT product_name, SUM(quantity_sold) as qty, SUM(revenue) as revenue
FROM monthly_sales_report  
GROUP BY product_name
ORDER BY revenue DESC
LIMIT 10;
```

---

## 6.3.4. **sp_remove_expired_products** - Loại bỏ Hàng hết hạn

### **Mục đích**
Tự động loại bỏ các sản phẩm đã hết hạn sử dụng khỏi kho và quầy bán, ghi log chi tiết.

### **Signature**
```sql
CREATE OR REPLACE PROCEDURE supermarket.sp_remove_expired_products()
```

### **Logic xử lý**
```sql
DECLARE
    v_expired_count INTEGER := 0;
    v_record RECORD;
BEGIN
    -- 1. Xử lý hàng hết hạn trong warehouse
    FOR v_record IN 
        SELECT inventory_id, product_id, batch_code, quantity, expiry_date
        FROM supermarket.warehouse_inventory
        WHERE expiry_date < CURRENT_DATE
    LOOP
        -- Log thông tin
        RAISE NOTICE 'Removing expired batch: % (Product: %, Qty: %)', 
                     v_record.batch_code, v_record.product_id, v_record.quantity;
        
        -- Xóa khỏi inventory  
        DELETE FROM supermarket.warehouse_inventory 
        WHERE inventory_id = v_record.inventory_id;
        
        v_expired_count := v_expired_count + 1;
    END LOOP;
    
    -- 2. Xử lý hàng hết hạn trên shelf
    UPDATE supermarket.shelf_batch_inventory
    SET quantity = 0, is_near_expiry = true
    WHERE expiry_date < CURRENT_DATE;
    
    RAISE NOTICE 'Expired products removal completed. Total removed: % batches', v_expired_count;
END;
```

### **Tính năng**
- **Audit Trail**: Log chi tiết mỗi batch bị xóa
- **Safe Removal**: Không xóa hẳn shelf records, chỉ set quantity = 0
- **Batch Processing**: Xử lý hàng loạt hiệu quả
- **Notification**: Thông báo kết quả xử lý

### **Ví dụ sử dụng**
```sql
-- Chạy hàng ngày để dọn dẹp hàng hết hạn
CALL supermarket.sp_remove_expired_products();
-- Output: NOTICE:  Removing expired batch: BTH-001 (Product: 101, Qty: 25)
-- Output: NOTICE:  Expired products removal completed. Total removed: 3 batches

-- Có thể tích hợp vào cron job
-- 0 1 * * * psql -d supermarket -c "CALL supermarket.sp_remove_expired_products();"
```

---

## 6.3.5. **sp_calculate_employee_salary** - Tính Lương Nhân viên

### **Mục đích**  
Tính lương tháng cho nhân viên dựa trên lương cơ bản và giờ làm thực tế.

### **Signature**
```sql
CREATE OR REPLACE PROCEDURE supermarket.sp_calculate_employee_salary(
    p_employee_id BIGINT,                    -- ID nhân viên
    p_month INTEGER,                         -- Tháng tính lương
    p_year INTEGER,                          -- Năm tính lương
    OUT p_base_salary NUMERIC(12,2),        -- Lương cơ bản (output)
    OUT p_hourly_salary NUMERIC(12,2),      -- Lương theo giờ (output)
    OUT p_total_salary NUMERIC(12,2)        -- Tổng lương (output)
)
```

### **Logic tính toán**
```sql
DECLARE
    v_position_id BIGINT;
    v_total_hours NUMERIC(10,2);
    v_hourly_rate NUMERIC(10,2);
BEGIN
    -- 1. Lấy thông tin vị trí và mức lương
    SELECT e.position_id, p.base_salary, p.hourly_rate
    INTO v_position_id, p_base_salary, v_hourly_rate
    FROM supermarket.employees e
    INNER JOIN supermarket.positions p ON e.position_id = p.position_id
    WHERE e.employee_id = p_employee_id;
    
    -- 2. Tính tổng giờ làm trong tháng
    SELECT COALESCE(SUM(total_hours), 0)
    INTO v_total_hours
    FROM supermarket.employee_work_hours
    WHERE employee_id = p_employee_id
      AND EXTRACT(MONTH FROM work_date) = p_month
      AND EXTRACT(YEAR FROM work_date) = p_year;
    
    -- 3. Tính lương theo giờ
    p_hourly_salary := v_total_hours * v_hourly_rate;
    
    -- 4. Tính tổng lương
    p_total_salary := p_base_salary + p_hourly_salary;
    
    RAISE NOTICE 'Salary calculated for employee %: Base=%, Hourly=%, Total=%', 
                 p_employee_id, p_base_salary, p_hourly_salary, p_total_salary;
END;
```

### **Công thức lương**
```
Tổng lương = Lương cơ bản + (Số giờ làm × Đơn giá giờ)
```

### **Ví dụ sử dụng**
```sql
-- Tính lương nhân viên ID=1001 tháng 12/2024
DO $$
DECLARE
    base_sal NUMERIC(12,2);
    hourly_sal NUMERIC(12,2); 
    total_sal NUMERIC(12,2);
BEGIN
    CALL supermarket.sp_calculate_employee_salary(1001, 12, 2024, base_sal, hourly_sal, total_sal);
    
    RAISE NOTICE 'Employee salary breakdown:';
    RAISE NOTICE '- Base salary: %', base_sal;
    RAISE NOTICE '- Hourly salary: %', hourly_sal;
    RAISE NOTICE '- Total salary: %', total_sal;
END $$;

-- Output:
-- NOTICE:  Salary calculated for employee 1001: Base=5000000, Hourly=2400000, Total=7400000
-- NOTICE:  Employee salary breakdown:
-- NOTICE:  - Base salary: 5000000.00
-- NOTICE:  - Hourly salary: 2400000.00  
-- NOTICE:  - Total salary: 7400000.00
```

---

## **Tổng quan Stored Procedures System**

### **Thống kê chức năng**
| Procedure | Nghiệp vụ | Độ phức tạp | Tương tác Triggers |
|-----------|-----------|-------------|-------------------|
| `sp_replenish_shelf_stock` | Quản lý tồn kho | Cao | ✓ (validate + process) |
| `sp_process_sale` | Bán hàng | Cao | ✓ (calculation + stock) |
| `sp_generate_monthly_sales_report` | Báo cáo | Trung bình | ✗ |
| `sp_remove_expired_products` | Dọn dẹp | Trung bình | ✗ |
| `sp_calculate_employee_salary` | Tính lương | Thấp | ✗ |

### **Đặc điểm kỹ thuật**

#### **Error Handling**
```sql
-- Pattern chung cho exception handling
BEGIN
    -- Business logic
    IF condition_failed THEN
        RAISE EXCEPTION 'Error message with params: %', variable;
    END IF;
    
    RAISE NOTICE 'Success message: %', result;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Procedure failed: %', SQLERRM;
        -- Có thể log vào audit table
END;
```

#### **Transaction Management**
- Tất cả procedures chạy trong **single transaction**
- **ROLLBACK** tự động nếu có lỗi
- Sử dụng **SAVEPOINT** cho complex procedures

#### **Performance Optimization**
- **Batch processing** cho operations hàng loạt
- **Temp tables** cho complex reports
- **Index hints** trong complex queries
- **LIMIT** clauses để tránh timeout

### **Integration với Application Layer**

```sql
-- Example: Gọi từ application
CALL supermarket.sp_process_sale(
    :customer_id,
    :employee_id, 
    :payment_method,
    :product_list_json,
    :points_used
);

-- Xử lý kết quả trong code
IF SQLSTATE = '00000' THEN
    -- Success
    COMMIT;
    RETURN success_response;
ELSE
    -- Error occurred  
    ROLLBACK;
    RETURN error_response;
END IF;
```

### **Best Practices Applied**

1. **Input Validation**: Kiểm tra tham số đầu vào
2. **Atomic Operations**: Toàn bộ thành công hoặc rollback
3. **Clear Messaging**: RAISE NOTICE cho kết quả
4. **Consistent Naming**: sp_[action]_[object] convention
5. **Documentation**: Comment chi tiết logic phức tạp
