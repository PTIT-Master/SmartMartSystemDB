# 6.3. STORED PROCEDURES & FUNCTIONS - QUY TRÌNH PHỨC TẠP

## Tổng quan

Hệ thống triển khai **3 Stored Procedures** và **28 Functions** để đóng gói các quy trình nghiệp vụ phức tạp, đảm bảo tính toàn vẹn dữ liệu và cung cấp API chuẩn cho các ứng dụng. Procedures xử lý các nghiệp vụ hoàn chỉnh với logic validation và error handling, trong khi Functions chủ yếu phục vụ cho triggers và các tính toán đặc biệt.

---

## **PHẦN A: STORED PROCEDURES**

### **A.1. process_sale_payment** - Xử lý Thanh toán Bán hàng

#### **Mục đích**
Thực hiện xử lý thanh toán hoàn chỉnh: trừ tồn kho theo FIFO, cập nhật điểm thưởng khách hàng.

#### **Signature**
```sql
CREATE PROCEDURE supermarket.process_sale_payment(
    IN p_invoice_id BIGINT
)
```

#### **Logic xử lý**
```sql
DECLARE
    rec RECORD;
    v_customer_id BIGINT;
    v_total_amount DECIMAL(12,2);
BEGIN
    -- 1. Duyệt qua các chi tiết hóa đơn
    FOR rec IN 
        SELECT product_id, quantity 
        FROM sales_invoice_details 
        WHERE invoice_id = p_invoice_id
    LOOP
        -- 2. Giảm số lượng trên quầy (FIFO từ batch cũ nhất)
        WITH batch_deduct AS (
            SELECT shelf_batch_id, 
                   LEAST(quantity, rec.quantity) AS deduct_qty
            FROM shelf_batch_inventory
            WHERE product_id = rec.product_id
              AND quantity > 0
            ORDER BY expiry_date ASC, batch_code ASC
            LIMIT 1
        )
        UPDATE shelf_batch_inventory sbi
        SET quantity = sbi.quantity - bd.deduct_qty
        FROM batch_deduct bd
        WHERE sbi.shelf_batch_id = bd.shelf_batch_id;
        
        -- 3. Cập nhật tổng số lượng trên quầy
        UPDATE shelf_inventory
        SET current_quantity = current_quantity - rec.quantity
        WHERE product_id = rec.product_id
          AND current_quantity >= rec.quantity;
    END LOOP;
    
    -- 4. Cập nhật điểm và tổng chi tiêu cho khách hàng
    SELECT customer_id, total_amount 
    INTO v_customer_id, v_total_amount
    FROM sales_invoices 
    WHERE invoice_id = p_invoice_id;
    
    IF v_customer_id IS NOT NULL THEN
        UPDATE customers
        SET total_spending = total_spending + v_total_amount,
            loyalty_points = loyalty_points + FLOOR(v_total_amount / 10000)
        WHERE customer_id = v_customer_id;
    END IF;
    
    COMMIT;
END;
```

#### **Đặc điểm quan trọng**
- **FIFO Implementation**: Ưu tiên batch có hạn sử dụng sớm nhất
- **Batch Tracking**: Xử lý chi tiết từng batch trên quầy
- **Customer Loyalty**: Tự động cộng điểm thưởng (1 điểm / 10.000 VNĐ)
- **Atomic Transaction**: Toàn bộ thành công hoặc rollback

#### **Ví dụ sử dụng**
```sql
-- Xử lý thanh toán cho hóa đơn ID=1001
CALL supermarket.process_sale_payment(1001);
```

---

### **A.2. transfer_stock_to_shelf** - Chuyển Hàng từ Kho lên Quầy

#### **Mục đích**
Thực hiện chuyển hàng từ kho lên quầy bán với đầy đủ validation và theo nguyên tắc FIFO.

#### **Signature**
```sql
CREATE PROCEDURE supermarket.transfer_stock_to_shelf(
    IN p_product_id BIGINT,         -- ID sản phẩm
    IN p_from_warehouse_id BIGINT,  -- ID kho nguồn
    IN p_to_shelf_id BIGINT,        -- ID quầy đích
    IN p_quantity BIGINT,           -- Số lượng chuyển
    IN p_employee_id BIGINT         -- ID nhân viên thực hiện
)
```

#### **Logic xử lý**
```sql
DECLARE
    v_available_qty BIGINT;
    v_max_shelf_qty BIGINT;
    v_current_shelf_qty BIGINT;
    v_batch_code VARCHAR(50);
    v_expiry_date DATE;
    v_import_price DECIMAL(12,2);
BEGIN
    -- 1. Kiểm tra số lượng trong kho
    SELECT SUM(quantity) INTO v_available_qty
    FROM warehouse_inventory
    WHERE warehouse_id = p_from_warehouse_id AND product_id = p_product_id;
    
    IF v_available_qty IS NULL OR v_available_qty < p_quantity THEN
        RAISE EXCEPTION 'Không đủ hàng trong kho. Có sẵn: %, Yêu cầu: %', 
                        v_available_qty, p_quantity;
    END IF;
    
    -- 2. Kiểm tra giới hạn quầy hàng
    SELECT max_quantity INTO v_max_shelf_qty
    FROM shelf_layout
    WHERE shelf_id = p_to_shelf_id AND product_id = p_product_id;
    
    SELECT COALESCE(current_quantity, 0) INTO v_current_shelf_qty
    FROM shelf_inventory
    WHERE shelf_id = p_to_shelf_id AND product_id = p_product_id;
    
    IF v_max_shelf_qty IS NOT NULL AND (v_current_shelf_qty + p_quantity) > v_max_shelf_qty THEN
        RAISE EXCEPTION 'Vượt quá giới hạn quầy hàng. Giới hạn: %, Hiện tại: %, Yêu cầu thêm: %', 
            v_max_shelf_qty, v_current_shelf_qty, p_quantity;
    END IF;
    
    -- 3. Lấy batch cũ nhất (FIFO)
    SELECT batch_code, expiry_date, import_price 
    INTO v_batch_code, v_expiry_date, v_import_price
    FROM warehouse_inventory
    WHERE warehouse_id = p_from_warehouse_id AND product_id = p_product_id
    ORDER BY expiry_date ASC, batch_code ASC
    LIMIT 1;
    
    -- 4. Tạo record chuyển hàng (triggers sẽ xử lý cập nhật)
    INSERT INTO stock_transfers (
        product_id, from_warehouse_id, to_shelf_id,
        quantity, employee_id, batch_code, expiry_date, import_price
    ) VALUES (
        p_product_id, p_from_warehouse_id, p_to_shelf_id,
        p_quantity, p_employee_id, v_batch_code, v_expiry_date, v_import_price
    );
    
    COMMIT;
END;
```

#### **Validation thực hiện**
1. **Kiểm tra tồn kho**: Đảm bảo kho có đủ hàng
2. **Kiểm tra sức chứa quầy**: Không vượt quá `max_quantity`
3. **FIFO Logic**: Ưu tiên batch cũ nhất, hạn gần nhất
4. **Integrity**: Đảm bảo consistency giữa warehouse và shelf

#### **Ví dụ sử dụng**
```sql
-- Chuyển 100 sản phẩm ID=501 từ kho 1 lên quầy 5
CALL supermarket.transfer_stock_to_shelf(501, 1, 5, 100, 1002);
```

---

### **A.3. update_expiry_discounts** - Cập nhật Giảm giá Hạn sử dụng

#### **Mục đích**
Tự động cập nhật giảm giá cho các sản phẩm trên quầy dựa trên quy tắc giảm giá theo hạn sử dụng.

#### **Signature**
```sql
CREATE PROCEDURE supermarket.update_expiry_discounts()
```

#### **Logic xử lý**
```sql
DECLARE
    rec RECORD;
    v_discount_percent DECIMAL(5,2);
BEGIN
    -- Duyệt qua tất cả sản phẩm trên quầy
    FOR rec IN 
        SELECT sbi.shelf_batch_id, sbi.product_id, sbi.expiry_date, p.category_id
        FROM shelf_batch_inventory sbi
        JOIN products p ON sbi.product_id = p.product_id
        WHERE sbi.expiry_date > CURRENT_DATE
          AND sbi.quantity > 0
    LOOP
        -- Tính discount theo quy tắc
        SELECT discount_percentage INTO v_discount_percent
        FROM discount_rules
        WHERE category_id = rec.category_id
          AND days_before_expiry >= (rec.expiry_date - CURRENT_DATE)
        ORDER BY days_before_expiry ASC
        LIMIT 1;
        
        IF v_discount_percent IS NOT NULL THEN
            -- Cập nhật discount và đánh dấu near expiry
            UPDATE shelf_batch_inventory
            SET discount_percent = v_discount_percent,
                is_near_expiry = TRUE,
                current_price = (
                    SELECT selling_price * (1 - v_discount_percent / 100)
                    FROM products 
                    WHERE product_id = rec.product_id
                )
            WHERE shelf_batch_id = rec.shelf_batch_id;
        END IF;
    END LOOP;
    
    COMMIT;
END;
```

#### **Quy tắc giảm giá**
- **Tìm rule phù hợp**: Dựa trên category và số ngày còn lại
- **Tính giá mới**: `selling_price * (1 - discount_percentage / 100)`
- **Đánh dấu near expiry**: Set flag để dễ tracking
- **Chỉ áp dụng cho hàng còn hạn**: `expiry_date > CURRENT_DATE`

#### **Ví dụ sử dụng**
```sql
-- Chạy hàng ngày để cập nhật giảm giá
CALL supermarket.update_expiry_discounts();

-- Có thể tích hợp vào cron job
-- 0 6 * * * psql -d supermarket -c "CALL supermarket.update_expiry_discounts();"
```

---

## **PHẦN B: UTILITY FUNCTIONS**

### **B.1. Nhóm Functions cho Triggers (28 functions)**

#### **Business Logic Functions**
- `apply_expiry_discounts()` - Áp dụng giảm giá hạn sử dụng
- `calculate_detail_subtotal()` - Tính subtotal chi tiết hóa đơn
- `calculate_expiry_date()` - Tính hạn sử dụng từ ngày nhập
- `calculate_invoice_totals()` - Tính tổng hóa đơn
- `calculate_purchase_detail_subtotal()` - Tính subtotal chi tiết nhập hàng
- `calculate_work_hours()` - Tính giờ làm việc nhân viên
- `check_low_stock()` - Kiểm tra cảnh báo tồn kho thấp
- `check_membership_upgrade()` - Kiểm tra nâng cấp thành viên
- `process_sales_stock_deduction()` - Trừ tồn kho khi bán
- `process_stock_transfer()` - Xử lý chuyển hàng
- `update_customer_metrics()` - Cập nhật thông số khách hàng
- `update_purchase_order_total()` - Cập nhật tổng đơn nhập hàng
- `validate_product_price()` - Validate giá bán > giá nhập
- `validate_shelf_capacity()` - Validate sức chứa quầy
- `validate_shelf_category_consistency()` - Validate category sản phẩm-quầy
- `validate_stock_transfer()` - Validate điều kiện chuyển hàng

#### **Logging Functions**
- `log_expiry_alert()` - Ghi log cảnh báo hết hạn
- `log_low_stock_alert()` - Ghi log cảnh báo thiếu hàng
- `log_product_activity()` - Ghi log hoạt động sản phẩm
- `log_sales_activity()` - Ghi log bán hàng
- `log_stock_transfer_activity()` - Ghi log chuyển hàng

#### **Utility Functions**
- `set_created_timestamp()` - Set timestamp khi tạo
- `update_timestamp()` - Update timestamp khi sửa

#### **Reporting Functions**
- `calculate_discount_price()` - Tính giá sau giảm giá
- `calculate_invoice_total()` - Tính tổng hóa đơn chi tiết
- `check_restock_alerts()` - Kiểm tra cảnh báo bổ sung
- `get_best_selling_products()` - Lấy sản phẩm bán chạy
- `get_revenue_report()` - Tạo báo cáo doanh thu

---

## **PHẦN C: INTEGRATION PATTERNS**

### **C.1. Trigger-Function Integration**
```sql
-- Example: Trigger sử dụng function
CREATE TRIGGER tr_process_sales_stock_deduction 
    AFTER INSERT ON sales_invoice_details 
    FOR EACH ROW 
    EXECUTE FUNCTION process_sales_stock_deduction();

-- Function xử lý logic nghiệp vụ
CREATE FUNCTION process_sales_stock_deduction() 
RETURNS TRIGGER AS $$
BEGIN
    -- Business logic here
    UPDATE shelf_inventory 
    SET current_quantity = current_quantity - NEW.quantity
    WHERE product_id = NEW.product_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### **C.2. Procedure-Application Integration**
```sql
-- Application code gọi procedure
BEGIN;
    CALL supermarket.process_sale_payment(:invoice_id);
    
    IF SQLSTATE = '00000' THEN
        COMMIT;
        RETURN success_response;
    ELSE
        ROLLBACK;
        RETURN error_response;
    END IF;
END;
```

### **C.3. Function-View Integration**
```sql
-- View sử dụng function để tính toán
CREATE VIEW v_product_with_discounts AS
SELECT 
    p.*,
    calculate_discount_price(p.product_id, CURRENT_DATE) as discounted_price
FROM products p;
```

---

## **Tổng quan Procedures & Functions System**

### **Thống kê chức năng**
| Loại | Số lượng | Mục đích chính | Độ phức tạp |
|------|----------|----------------|-------------|
| **Stored Procedures** | 3 | Nghiệp vụ hoàn chỉnh | Cao |
| **Trigger Functions** | 16 | Logic triggers | Trung bình-Cao |
| **Logging Functions** | 5 | Audit & Monitoring | Thấp |
| **Utility Functions** | 2 | Timestamp management | Thấp |
| **Reporting Functions** | 5 | Báo cáo & phân tích | Trung bình |

### **Đặc điểm kỹ thuật**

#### **Error Handling Pattern**
```sql
BEGIN
    -- Business logic
    IF condition_failed THEN
        RAISE EXCEPTION 'Error message with params: %', variable;
    END IF;
    
    -- Success processing
    RAISE NOTICE 'Success message: %', result;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Operation failed: %', SQLERRM;
        -- Optional: Log to audit table
END;
```

#### **Transaction Management**
- **Procedures**: Quản lý transaction hoàn chỉnh với COMMIT/ROLLBACK
- **Functions**: Chạy trong transaction context của caller
- **Atomic Operations**: Đảm bảo consistency với explicit transaction control

#### **Performance Optimization**
- **Batch Processing**: Xử lý hàng loạt trong loops
- **Index Usage**: Tối ưu queries trong functions
- **Memory Management**: Cleanup variables và cursors
- **Connection Pooling**: Tái sử dụng connections cho procedures

### **Best Practices Applied**

1. **Separation of Concerns**: Procedures cho business logic, Functions cho computations
2. **Error Handling**: Comprehensive exception handling với meaningful messages  
3. **Input Validation**: Kiểm tra tham số đầu vào kỹ lưỡng
4. **Consistent Naming**: `sp_[action]_[object]` cho procedures, descriptive names cho functions
5. **Documentation**: Comments chi tiết cho logic phức tạp
6. **Security**: Proper parameter binding, SQL injection prevention
7. **Monitoring**: Extensive logging cho audit và debugging

### **Usage Guidelines**

- **Procedures**: Gọi từ application layer cho complete business operations
- **Functions**: Sử dụng trong triggers, views, và calculations
- **Error Handling**: Luôn wrap procedure calls trong try-catch blocks
- **Performance**: Monitor execution time và optimize khi cần thiết
- **Maintenance**: Regular review và update documentation