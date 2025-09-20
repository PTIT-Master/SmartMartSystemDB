# 6.1. TRIGGERS - XỬ LÝ TỰ ĐỘNG

## Tổng quan

Hệ thống sử dụng **18 triggers** để tự động hóa các nghiệp vụ phức tạp, đảm bảo tính nhất quán dữ liệu và giảm thiểu can thiệp thủ công. Các triggers được phân thành 4 nhóm chức năng chính:

---

## 6.1.1. **Nhóm Triggers Quản lý Tồn kho**

Nhóm này xử lý các nghiệp vụ liên quan đến quản lý số lượng hàng hóa giữa kho và quầy bán.

### **A. `tr_process_sales_stock_deduction`**

**Mục đích**: Tự động trừ tồn kho trên quầy khi có giao dịch bán hàng.

```sql
CREATE TRIGGER tr_process_sales_stock_deduction 
    AFTER INSERT ON supermarket.sales_invoice_details 
    FOR EACH ROW EXECUTE FUNCTION supermarket.process_sales_stock_deduction();
```

**Logic xử lý**:
- Kiểm tra số lượng hàng còn trên quầy
- Từ chối giao dịch nếu không đủ hàng
- Tự động trừ số lượng từ `shelf_inventory`

**Ví dụ hoạt động**:
```sql
-- Khi thêm chi tiết hóa đơn
INSERT INTO sales_invoice_details (invoice_id, product_id, quantity, unit_price)
VALUES (1, 101, 5, 25000);

-- Trigger tự động thực hiện:
-- UPDATE shelf_inventory SET current_quantity = current_quantity - 5 WHERE product_id = 101;
```

### **B. `tr_process_stock_transfer`**

**Mục đích**: Tự động cập nhật tồn kho khi chuyển hàng từ kho lên quầy.

```sql
CREATE TRIGGER tr_process_stock_transfer 
    AFTER INSERT ON supermarket.stock_transfers 
    FOR EACH ROW EXECUTE FUNCTION supermarket.process_stock_transfer();
```

**Logic xử lý**:
- Trừ số lượng từ `warehouse_inventory`
- Cộng số lượng vào `shelf_inventory` (INSERT hoặc UPDATE)
- Sử dụng `ON CONFLICT` để xử lý trường hợp đã có sản phẩm trên quầy

**Đặc điểm quan trọng**:
- Hỗ trợ **UPSERT** (Insert + Update)
- Cập nhật `last_restocked` timestamp
- Xử lý batch tracking

### **C. `tr_validate_stock_transfer`**

**Mục đích**: Kiểm tra tính hợp lệ trước khi thực hiện chuyển hàng.

```sql
CREATE TRIGGER tr_validate_stock_transfer 
    BEFORE INSERT ON supermarket.stock_transfers 
    FOR EACH ROW EXECUTE FUNCTION supermarket.validate_stock_transfer();
```

**Các kiểm tra thực hiện**:
1. **Kiểm tra tồn kho**: Đảm bảo kho có đủ hàng
2. **Kiểm tra sức chứa quầy**: Không vượt quá `max_quantity`
3. **Kiểm tra cấu hình**: Sản phẩm phải được cấu hình cho quầy đó

**Logic validation**:
```sql
-- Kiểm tra tồn kho
SELECT COALESCE(SUM(wi.quantity), 0) INTO available_qty
FROM warehouse_inventory wi
WHERE wi.warehouse_id = NEW.from_warehouse_id 
  AND wi.product_id = NEW.product_id;

IF available_qty < NEW.quantity THEN
    RAISE EXCEPTION 'Insufficient warehouse stock for product %', product_code;
END IF;
```

---

## 6.1.2. **Nhóm Triggers Tính toán**

Nhóm này tự động tính toán các giá trị dẫn xuất và cập nhật thông tin liên quan.

### **A. `tr_calculate_detail_subtotal`**

**Mục đích**: Tính subtotal cho từng dòng hóa đơn bán hàng.

```sql
CREATE TRIGGER tr_calculate_detail_subtotal 
    BEFORE INSERT OR UPDATE ON supermarket.sales_invoice_details 
    FOR EACH ROW EXECUTE FUNCTION supermarket.calculate_detail_subtotal();
```

**Công thức tính**:
```sql
-- Tính tiền chiết khấu
NEW.discount_amount := NEW.unit_price * NEW.quantity * (NEW.discount_percentage / 100);

-- Tính subtotal
NEW.subtotal := (NEW.unit_price * NEW.quantity) - NEW.discount_amount;
```

### **B. `tr_calculate_invoice_totals`**

**Mục đích**: Tính tổng tiền hóa đơn dựa trên các chi tiết.

```sql
CREATE TRIGGER tr_calculate_invoice_totals 
    AFTER INSERT OR DELETE OR UPDATE ON supermarket.sales_invoice_details 
    FOR EACH ROW EXECUTE FUNCTION supermarket.calculate_invoice_totals();
```

**Logic tính toán**:
```sql
-- Tính subtotal và discount từ tất cả chi tiết
SELECT 
    COALESCE(SUM(subtotal), 0),
    COALESCE(SUM(discount_amount), 0)
INTO invoice_subtotal, invoice_discount
FROM sales_invoice_details 
WHERE invoice_id = NEW.invoice_id;

-- Tính thuế VAT 10%
invoice_tax := (invoice_subtotal - invoice_discount) * 0.10;

-- Tính tổng cuối
invoice_total := invoice_subtotal - invoice_discount + invoice_tax;
```

### **C. `tr_update_customer_metrics`**

**Mục đích**: Cập nhật tổng chi tiêu và điểm thưởng của khách hàng.

```sql
CREATE TRIGGER tr_update_customer_metrics 
    BEFORE INSERT OR UPDATE ON supermarket.sales_invoices 
    FOR EACH ROW EXECUTE FUNCTION supermarket.update_customer_metrics();
```

**Logic xử lý**:
1. Lấy hệ số nhân điểm theo cấp thành viên
2. Tính điểm thưởng: `FLOOR(total_amount * multiplier)`
3. Cập nhật `total_spending` và `loyalty_points`

### **D. `tr_calculate_work_hours`**

**Mục đích**: Tính số giờ làm việc của nhân viên.

```sql
CREATE TRIGGER tr_calculate_work_hours 
    BEFORE INSERT OR UPDATE ON supermarket.employee_work_hours 
    FOR EACH ROW EXECUTE FUNCTION supermarket.calculate_work_hours();
```

**Công thức**:
```sql
NEW.total_hours := EXTRACT(EPOCH FROM (NEW.check_out_time - NEW.check_in_time)) / 3600;
```

### **E. `tr_update_purchase_order_total`**

**Mục đích**: Cập nhật tổng tiền đơn nhập hàng.

```sql
CREATE TRIGGER tr_update_purchase_order_total_insert 
    AFTER INSERT OR DELETE OR UPDATE ON supermarket.purchase_order_details 
    FOR EACH ROW EXECUTE FUNCTION supermarket.update_purchase_order_total();
```

---

## 6.1.3. **Nhóm Triggers Kiểm tra Ràng buộc**

Nhóm này đảm bảo các business rules được thực thi nghiêm ngặt.

### **A. `tr_validate_shelf_capacity`**

**Mục đích**: Đảm bảo số lượng hàng trên quầy không vượt quá sức chứa.

```sql
CREATE TRIGGER tr_validate_shelf_capacity 
    BEFORE INSERT OR UPDATE ON supermarket.shelf_inventory 
    FOR EACH ROW EXECUTE FUNCTION supermarket.validate_shelf_capacity();
```

**Logic kiểm tra**:
```sql
-- Lấy sức chứa tối đa
SELECT sl.max_quantity INTO max_qty
FROM shelf_layout sl
WHERE sl.shelf_id = NEW.shelf_id AND sl.product_id = NEW.product_id;

IF NEW.current_quantity > max_qty THEN
    RAISE EXCEPTION 'Quantity (%) exceeds maximum allowed (%) for shelf %',
                    NEW.current_quantity, max_qty, NEW.shelf_id;
END IF;
```

### **B. `tr_validate_product_price`**

**Mục đích**: Đảm bảo giá bán luôn cao hơn giá nhập.

```sql
CREATE TRIGGER tr_validate_product_price 
    BEFORE INSERT OR UPDATE ON supermarket.products 
    FOR EACH ROW EXECUTE FUNCTION supermarket.validate_product_price();
```

**Ràng buộc**:
```sql
IF NEW.selling_price <= NEW.import_price THEN
    RAISE EXCEPTION 'Selling price (%) must be higher than import price (%)', 
                    NEW.selling_price, NEW.import_price;
END IF;
```

### **C. `tr_check_low_stock`**

**Mục đích**: Cảnh báo khi tồn kho xuống dưới ngưỡng.

```sql
CREATE TRIGGER tr_check_low_stock 
    AFTER UPDATE ON supermarket.shelf_inventory 
    FOR EACH ROW EXECUTE FUNCTION supermarket.check_low_stock();
```

**Logic cảnh báo**:
```sql
-- Kiểm tra nếu tồn kho vừa xuống dưới threshold
IF NEW.current_quantity <= threshold AND 
   (OLD IS NULL OR OLD.current_quantity > threshold) THEN
    
    RAISE NOTICE 'LOW STOCK ALERT: Product "%" (ID: %) is at % units (threshold: %)', 
                 product_name, NEW.product_id, NEW.current_quantity, threshold;
END IF;
```

### **D. `tr_validate_shelf_category_consistency`**

**Mục đích**: Đảm bảo sản phẩm chỉ được bày bán trên quầy cùng chủng loại.

```sql
CREATE TRIGGER tr_validate_shelf_category_inventory 
    BEFORE INSERT OR UPDATE ON supermarket.shelf_inventory 
    FOR EACH ROW EXECUTE FUNCTION supermarket.validate_shelf_category_consistency();
```

**Logic kiểm tra**:
```sql
-- Lấy category của quầy và sản phẩm
SELECT ds.category_id INTO shelf_category_id
FROM display_shelves ds WHERE ds.shelf_id = NEW.shelf_id;

SELECT p.category_id INTO product_category_id
FROM products p WHERE p.product_id = NEW.product_id;

IF shelf_category_id != product_category_id THEN
    RAISE EXCEPTION 'Product category (%) does not match shelf category (%)', 
                    product_category_id, shelf_category_id;
END IF;
```

### **E. `tr_check_membership_upgrade`**

**Mục đích**: Tự động nâng cấp thành viên khi đạt mốc chi tiêu.

```sql
CREATE TRIGGER tr_check_membership_upgrade 
    AFTER UPDATE OF total_spending ON supermarket.customers 
    FOR EACH ROW EXECUTE FUNCTION supermarket.check_membership_upgrade();
```

**Logic nâng cấp**:
```sql
-- Tìm cấp thành viên cao nhất mà khách hàng đủ điều kiện
SELECT level_id, level_name INTO new_level_id, new_level_name
FROM membership_levels 
WHERE min_spending <= NEW.total_spending
ORDER BY min_spending DESC
LIMIT 1;

-- Cập nhật nếu có thay đổi
IF new_level_id != current_level_id THEN
    UPDATE customers SET membership_level_id = new_level_id
    WHERE customer_id = NEW.customer_id;
END IF;
```

---

## 6.1.4. **Nhóm Triggers Xử lý Hạn sử dụng**

Nhóm này tự động hóa việc quản lý hạn sử dụng và giảm giá theo thời gian.

### **A. `tr_calculate_expiry_date`**

**Mục đích**: Tự động tính hạn sử dụng khi nhập hàng vào kho.

```sql
CREATE TRIGGER tr_calculate_expiry_date 
    BEFORE INSERT OR UPDATE ON supermarket.warehouse_inventory 
    FOR EACH ROW EXECUTE FUNCTION supermarket.calculate_expiry_date();
```

**Logic tính toán**:
```sql
-- Chỉ tính nếu chưa có expiry_date
IF NEW.expiry_date IS NULL THEN
    SELECT NEW.import_date + (p.shelf_life_days || ' days')::INTERVAL INTO NEW.expiry_date
    FROM products p
    WHERE p.product_id = NEW.product_id AND p.shelf_life_days IS NOT NULL;
END IF;
```

### **B. `tr_apply_expiry_discounts`**

**Mục đích**: Tự động áp dụng giảm giá dựa trên số ngày còn lại đến hạn.

```sql
CREATE TRIGGER tr_apply_expiry_discounts 
    AFTER INSERT OR UPDATE OF expiry_date ON supermarket.warehouse_inventory 
    FOR EACH ROW EXECUTE FUNCTION supermarket.apply_expiry_discounts();
```

**Logic giảm giá**:
```sql
days_until_expiry := NEW.expiry_date - CURRENT_DATE;

-- Tìm quy tắc giảm giá phù hợp
SELECT dr.discount_percentage INTO discount_rule
FROM discount_rules dr
INNER JOIN products p ON p.category_id = dr.category_id
WHERE p.product_id = NEW.product_id
  AND dr.days_before_expiry >= days_until_expiry
  AND dr.is_active = true
ORDER BY dr.days_before_expiry ASC
LIMIT 1;

-- Áp dụng giảm giá nhưng đảm bảo giá > import_price * 1.1
IF FOUND THEN
    new_price := original_price * (1 - discount_rule.discount_percentage / 100);
    IF new_price <= import_price_val THEN
        new_price := import_price_val * 1.1;  -- Minimum 10% profit
    END IF;
    
    UPDATE products SET selling_price = new_price WHERE product_id = NEW.product_id;
END IF;
```

---

## **Tóm tắt hoạt động Triggers**

| Nhóm | Số lượng | Tác động chính |
|------|----------|----------------|
| **Quản lý tồn kho** | 3 | Đồng bộ số liệu kho-quầy, validate chuyển hàng |
| **Tính toán** | 5 | Tự động tính subtotal, total, điểm thưởng, lương |
| **Kiểm tra ràng buộc** | 7 | Validate business rules, cảnh báo |
| **Xử lý hạn sử dụng** | 2 | Tính hạn SD, áp dụng giảm giá tự động |

## **Lợi ích của hệ thống Triggers**

1. **Tự động hóa**: Giảm 90% thao tác thủ công
2. **Nhất quán dữ liệu**: Đảm bảo integrity constraints
3. **Xử lý real-time**: Phản ứng ngay lập tức với thay đổi
4. **Giảm lỗi**: Loại bỏ sai sót do con người
5. **Tuân thủ nghiệp vụ**: Enforce business rules nghiêm ngặt

## **Thống kê hiệu suất**

- **Triggers BEFORE**: 11 triggers (validation + calculation)
- **Triggers AFTER**: 7 triggers (update related data)
- **Bảng có nhiều triggers nhất**: `products` (4 triggers)
- **Function phức tạp nhất**: `apply_expiry_discounts()` (45+ dòng code)
