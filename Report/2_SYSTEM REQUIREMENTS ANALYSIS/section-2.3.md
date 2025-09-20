# 2.3. CÁC RÀNG BUỘC NGHIỆP VỤ QUAN TRỌNG

## 2.3.1. Ràng buộc giá bán > giá nhập

### 2.3.1.1. Mô tả ràng buộc
Đây là ràng buộc nghiệp vụ cơ bản nhất đảm bảo tính khả thi về mặt tài chính của siêu thị. Giá bán (`selling_price`) của bất kỳ sản phẩm nào cũng phải cao hơn giá nhập (`import_price`) để đảm bảo có lợi nhuận.

### 2.3.1.2. Cách thực hiện trong hệ thống

**Constraint cấp bảng:**
```sql
CONSTRAINT check_price CHECK (selling_price > import_price)
```

**Trigger validation:**
- **Trigger name**: `tr_validate_product_price`
- **Kích hoạt**: BEFORE INSERT OR UPDATE ON products
- **Logic**: Kiểm tra `NEW.selling_price > NEW.import_price`, nếu vi phạm sẽ raise exception

**Xử lý khi giảm giá:**
Khi áp dụng discount rules cho hàng sắp hết hạn, hệ thống vẫn đảm bảo giá sau giảm ≥ 110% giá nhập để duy trì lợi nhuận tối thiểu:

```sql
-- Đảm bảo giá giảm không thấp hơn ngưỡng an toàn
IF new_price <= import_price_val THEN
    new_price := import_price_val * 1.1; -- Minimum 10% markup
END IF;
```

### 2.3.1.3. Tác động và lợi ích
- **Bảo vệ lợi nhuận**: Ngăn chặn việc bán lỗ do nhập liệu sai
- **Kiểm soát giá**: Đảm bảo chính sách giá nhất quán
- **Audit compliance**: Minh bạch trong báo cáo tài chính

## 2.3.2. Ràng buộc sức chứa quầy hàng

### 2.3.2.1. Mô tả ràng buộc
Mỗi vị trí trên quầy hàng có giới hạn về số lượng sản phẩm có thể chứa (`max_quantity` trong `shelf_layout`). Ràng buộc này đảm bảo:
- Không gian trưng bày hợp lý
- Tránh tình trạng quá tải quầy hàng
- Quản lý visual merchandising hiệu quả

### 2.3.2.2. Cách thực hiện trong hệ thống

**Bảng cấu hình:**
```sql
shelf_layout (
    shelf_id, 
    product_id, 
    position_code,
    max_quantity  -- Số lượng tối đa cho vị trí này
)
```

**Trigger validation:**
- **Trigger name**: `tr_validate_shelf_capacity`
- **Kích hoạt**: BEFORE INSERT OR UPDATE ON shelf_inventory
- **Logic**:
  ```sql
  -- Lấy giới hạn từ shelf_layout
  SELECT sl.max_quantity INTO max_qty
  FROM shelf_layout sl
  WHERE sl.shelf_id = NEW.shelf_id AND sl.product_id = NEW.product_id;
  
  -- Kiểm tra không vượt quá
  IF NEW.current_quantity > max_qty THEN
      RAISE EXCEPTION 'Quantity exceeds maximum allowed for shelf';
  END IF;
  ```

**Validation trong stock transfer:**
Trigger `tr_validate_stock_transfer` kiểm tra trước khi chuyển hàng:
```sql
-- Kiểm tra shelf capacity
IF (shelf_current_qty + NEW.quantity) > shelf_max_qty THEN
    RAISE EXCEPTION 'Transfer would exceed shelf capacity';
END IF;
```

### 2.3.2.3. Tác động và lợi ích
- **Tối ưu không gian**: Sử dụng diện tích trưng bày hiệu quả
- **Cải thiện shopping experience**: Tránh chen chúc, dễ lấy hàng
- **Kiểm soát inventory**: Phân bổ hàng hóa cân bằng giữa các quầy

## 2.3.3. Ràng buộc phân loại hàng theo quầy

### 2.3.3.1. Mô tả ràng buộc
Mỗi quầy hàng chỉ được trưng bày các sản phẩm thuộc cùng một danh mục (`category_id`). Ví dụ:
- Quầy thực phẩm chỉ bày thực phẩm
- Quầy đồ điện tử chỉ bày đồ điện tử
- Quầy văn phòng phẩm chỉ bày văn phòng phẩm

### 2.3.3.2. Cách thực hiện trong hệ thống

**Thiết kế bảng:**
```sql
display_shelves (
    shelf_id,
    category_id,  -- Mỗi shelf thuộc 1 category duy nhất
    shelf_name
)
```

**Trigger validation:**
- **Trigger name**: `tr_validate_shelf_category_consistency`
- **Áp dụng cho**: `shelf_layout` và `shelf_inventory`
- **Logic**:
  ```sql
  -- Lấy category của shelf
  SELECT ds.category_id INTO shelf_category_id
  FROM display_shelves ds WHERE ds.shelf_id = NEW.shelf_id;
  
  -- Lấy category của product  
  SELECT p.category_id INTO product_category_id
  FROM products p WHERE p.product_id = NEW.product_id;
  
  -- Kiểm tra consistency
  IF shelf_category_id != product_category_id THEN
      RAISE EXCEPTION 'Product category does not match shelf category';
  END IF;
  ```

### 2.3.3.3. Lợi ích của ràng buộc này
- **Trải nghiệm mua sắm tốt**: Khách dễ tìm đúng khu vực cần thiết
- **Quản lý hiệu quả**: Nhân viên chuyên môn theo từng danh mục
- **Marketing strategy**: Dễ dàng thiết kế promotion theo category
- **Inventory control**: Kiểm soát tồn kho theo nhóm sản phẩm

## 2.3.4. Ràng buộc số lượng kho - quầy

### 2.3.4.1. Mô tả ràng buộc
Hệ thống phải đảm bảo tính nhất quán về mặt số lượng giữa kho và quầy hàng:
- Không được chuyển hàng vượt quá số lượng có trong kho
- Không được bán vượt quá số lượng có trên quầy
- Số liệu inventory phải accurate và realtime

### 2.3.4.2. Cách thực hiện trong hệ thống

**Validation khi chuyển hàng:**
Trigger `tr_validate_stock_transfer` kiểm tra trước khi chuyển:
```sql
-- Kiểm tra warehouse stock availability
SELECT COALESCE(SUM(wi.quantity), 0) INTO available_qty
FROM warehouse_inventory wi
WHERE wi.warehouse_id = NEW.from_warehouse_id 
  AND wi.product_id = NEW.product_id;

IF available_qty < NEW.quantity THEN
    RAISE EXCEPTION 'Insufficient warehouse stock. Available: %, Requested: %', 
                    available_qty, NEW.quantity;
END IF;
```

**Xử lý khi bán hàng:**
Trigger `tr_process_sales_stock_deduction` kiểm tra và trừ tồn:
```sql
-- Kiểm tra shelf stock
SELECT si.current_quantity INTO available_qty
FROM shelf_inventory si WHERE si.product_id = NEW.product_id;

IF available_qty < NEW.quantity THEN
    RAISE EXCEPTION 'Insufficient shelf stock. Available: %, Requested: %', 
                    available_qty, NEW.quantity;
END IF;

-- Trừ tồn kho shelf
UPDATE shelf_inventory 
SET current_quantity = current_quantity - NEW.quantity
WHERE product_id = NEW.product_id;
```

**Automated stock transfer processing:**
Trigger `tr_process_stock_transfer` tự động cập nhật inventory sau khi validate:
```sql
-- Trừ warehouse inventory
UPDATE warehouse_inventory 
SET quantity = quantity - NEW.quantity
WHERE warehouse_id = NEW.from_warehouse_id 
  AND product_id = NEW.product_id;

-- Cộng shelf inventory  
INSERT INTO shelf_inventory (...)
VALUES (...) 
ON CONFLICT (shelf_id, product_id) 
DO UPDATE SET current_quantity = shelf_inventory.current_quantity + NEW.quantity;
```

### 2.3.4.3. Monitoring và Alerting
**Low stock alerts:**
```sql
-- Trigger tr_check_low_stock
IF NEW.current_quantity <= threshold AND 
   (OLD IS NULL OR OLD.current_quantity > threshold) THEN
    RAISE NOTICE 'LOW STOCK ALERT: Product "%s" is at %s units', 
                 product_name, NEW.current_quantity;
END IF;
```

**View cho monitoring:**
- `v_product_inventory_summary`: Tổng quan tồn kho
- `v_low_stock_alert`: Danh sách hàng sắp hết

## 2.3.5. Ràng buộc hạn sử dụng

### 2.3.5.1. Mô tả ràng buộc
Đây là ràng buộc phức tạp nhất, bao gồm nhiều aspects:
- Tự động tính ngày hết hạn dựa trên ngày nhập và shelf life
- Áp dụng discount rules khi sắp hết hạn
- Loại bỏ hàng đã quá hạn khỏi hệ thống
- Đảm bảo FIFO (First In, First Out) khi bán hàng

### 2.3.5.2. Tính toán ngày hết hạn

**Trigger tự động tính:**
- **Trigger name**: `tr_calculate_expiry_date`
- **Kích hoạt**: BEFORE INSERT OR UPDATE ON warehouse_inventory
- **Logic**:
```sql
-- Tính expiry_date nếu chưa có
IF NEW.expiry_date IS NULL THEN
    SELECT NEW.import_date + (p.shelf_life_days || ' days')::INTERVAL 
    INTO NEW.expiry_date
    FROM products p
    WHERE p.product_id = NEW.product_id 
      AND p.shelf_life_days IS NOT NULL;
END IF;
```

### 2.3.5.3. Hệ thống discount tự động

**Bảng discount rules:**
```sql
discount_rules (
    rule_id,
    category_id,                    -- Áp dụng cho category nào
    days_before_expiry,             -- Số ngày trước khi hết hạn
    discount_percentage,            -- % giảm giá
    is_active
)
```

**Ví dụ rules:**
- Thực phẩm: giảm 50% khi còn dưới 3 ngày
- Sữa: giảm 30% khi còn dưới 5 ngày
- Bánh kẹo: giảm 20% khi còn dưới 7 ngày

**Trigger áp dụng discount:**
- **Trigger name**: `tr_apply_expiry_discounts`
- **Kích hoạt**: AFTER INSERT OR UPDATE OF expiry_date ON warehouse_inventory
- **Logic**:
```sql
-- Tính số ngày còn lại
days_until_expiry := NEW.expiry_date - CURRENT_DATE;

-- Tìm discount rule phù hợp
SELECT dr.discount_percentage INTO discount_rule
FROM discount_rules dr
INNER JOIN products p ON p.category_id = dr.category_id
WHERE p.product_id = NEW.product_id
  AND dr.days_before_expiry >= days_until_expiry
  AND dr.is_active = true
ORDER BY dr.days_before_expiry ASC
LIMIT 1;

-- Áp dụng discount nhưng đảm bảo > 110% import price
IF FOUND THEN
    new_price := original_price * (1 - discount_rule.discount_percentage / 100);
    IF new_price <= import_price_val THEN
        new_price := import_price_val * 1.1;
    END IF;
    
    UPDATE products SET selling_price = new_price
    WHERE product_id = NEW.product_id;
END IF;
```

### 2.3.5.4. Quản lý hàng hết hạn

**View expired products:**
```sql
CREATE VIEW v_expired_products AS
SELECT 
    batch_code, product_code, quantity, expiry_date,
    CASE 
        WHEN expiry_date < CURRENT_DATE THEN 'Expired'
        WHEN expiry_date - CURRENT_DATE <= 3 THEN 'Expiring soon'
        ELSE 'Valid'
    END AS expiry_status
FROM warehouse_inventory wi
INNER JOIN products p ON wi.product_id = p.product_id
WHERE wi.expiry_date IS NOT NULL
ORDER BY wi.expiry_date ASC;
```

**Stored procedure loại bỏ hàng hết hạn:**
```sql
PROCEDURE sp_remove_expired_products()
-- Tự động xóa các batch đã hết hạn
-- Cập nhật shelf inventory tương ứng  
-- Ghi log để audit
```

### 2.3.5.5. FIFO Implementation

**Trong stored procedure replenishment:**
```sql
-- Lấy batch cũ nhất (FIFO)
SELECT batch_code, expiry_date, import_price
FROM warehouse_inventory
WHERE product_id = p_product_id AND quantity >= p_quantity
ORDER BY import_date ASC, expiry_date ASC  -- FIFO order
LIMIT 1;
```

## 2.3.6. Tổng kết về ràng buộc nghiệp vụ

### 2.3.6.1. Tầm quan trọng của ràng buộc
Các ràng buộc nghiệp vụ không chỉ đảm bảo tính đúng đắn của dữ liệu mà còn:
- **Automation**: Giảm thiểu can thiệp thủ công, tăng hiệu quả
- **Consistency**: Đảm bảo business rules được áp dụng nhất quán
- **Risk mitigation**: Ngăn chặn các lỗi có thể gây tổn thất tài chính
- **Compliance**: Đáp ứng các yêu cầu về an toàn thực phẩm, báo cáo thuế

### 2.3.6.2. Cách monitoring và maintenance
- **Regular review**: Định kỳ xem xét và cập nhật discount rules
- **Performance monitoring**: Theo dõi performance impact của triggers
- **Exception reporting**: Báo cáo các trường hợp vi phạm ràng buộc
- **Audit logging**: Ghi lại mọi thay đổi quan trọng để traceability

### 2.3.6.3. Flexibility vs Control
Hệ thống cân bằng giữa:
- **Flexibility**: Cho phép override trong trường hợp đặc biệt (với proper authorization)
- **Control**: Đảm bảo business rules được tuân thủ nghiêm ngặt
- **Scalability**: Thiết kế để dễ dàng thêm rules mới khi business mở rộng
