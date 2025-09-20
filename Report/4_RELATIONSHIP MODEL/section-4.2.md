# 4.2. Chuẩn hóa BCNF

## 4.2.1. Kiểm tra và chứng minh đạt chuẩn BCNF

### **A. Định nghĩa chuẩn BCNF (Boyce-Codd Normal Form)**

Một lược đồ quan hệ R đạt chuẩn BCNF khi và chỉ khi với mọi phụ thuộc hàm **X → Y** không tầm thường trong R, thì **X** phải là siêu khóa của R.

### **B. Phương pháp kiểm tra**

Cho mỗi bảng trong schema, chúng ta sẽ:
1. Xác định tất cả phụ thuộc hàm
2. Xác định các khóa ứng viên 
3. Kiểm tra điều kiện BCNF
4. Phân rã nếu cần thiết

### **C. Phân tích từng bảng**

#### **1. Product_Categories**

**Lược đồ**: `product_categories(category_id, category_name, description, created_at, updated_at)`

**Phụ thuộc hàm**:
- FD1: `category_id → {category_name, description, created_at, updated_at}`
- FD2: `category_name → {category_id, description, created_at, updated_at}`

**Khóa ứng viên**: 
- K1: `{category_id}` (Primary Key)
- K2: `{category_name}` (Unique constraint)

**Kiểm tra BCNF**:
- FD1: `category_id` là siêu khóa ✓
- FD2: `category_name` là siêu khóa ✓

**Kết luận**: ✅ **Đạt chuẩn BCNF**

#### **2. Suppliers**

**Lược đồ**: `suppliers(supplier_id, supplier_code, supplier_name, contact_person, phone, email, address, tax_code, bank_account, is_active, created_at, updated_at)`

**Phụ thuộc hàm**:
- FD1: `supplier_id → {supplier_code, supplier_name, contact_person, phone, email, address, tax_code, bank_account, is_active, created_at, updated_at}`
- FD2: `supplier_code → {supplier_id, supplier_name, contact_person, phone, email, address, tax_code, bank_account, is_active, created_at, updated_at}`

**Khóa ứng viên**:
- K1: `{supplier_id}` 
- K2: `{supplier_code}`

**Kiểm tra BCNF**: Tất cả FD có vế trái là siêu khóa ✓

**Kết luận**: ✅ **Đạt chuẩn BCNF**

#### **3. Products** 

**Lược đồ**: `products(product_id, product_code, product_name, category_id, supplier_id, unit, import_price, selling_price, shelf_life_days, low_stock_threshold, barcode, description, is_active, created_at, updated_at)`

**Phụ thuộc hàm**:
- FD1: `product_id → {product_code, product_name, category_id, supplier_id, unit, import_price, selling_price, shelf_life_days, low_stock_threshold, barcode, description, is_active, created_at, updated_at}`
- FD2: `product_code → {product_id, product_name, category_id, supplier_id, unit, import_price, selling_price, shelf_life_days, low_stock_threshold, barcode, description, is_active, created_at, updated_at}`
- FD3: `barcode → {product_id, product_code, product_name, category_id, supplier_id, unit, import_price, selling_price, shelf_life_days, low_stock_threshold, description, is_active, created_at, updated_at}`

**Khóa ứng viên**:
- K1: `{product_id}`
- K2: `{product_code}` 
- K3: `{barcode}` (khi barcode IS NOT NULL)

**Kiểm tra BCNF**: Tất cả FD có vế trái là siêu khóa ✓

**Kết luận**: ✅ **Đạt chuẩn BCNF**

#### **4. Warehouse_Inventory**

**Lược đồ**: `warehouse_inventory(inventory_id, warehouse_id, product_id, batch_code, quantity, import_date, expiry_date, import_price, created_at, updated_at)`

**Phụ thuộc hàm**:
- FD1: `inventory_id → {warehouse_id, product_id, batch_code, quantity, import_date, expiry_date, import_price, created_at, updated_at}`
- FD2: `{warehouse_id, product_id, batch_code} → {inventory_id, quantity, import_date, expiry_date, import_price, created_at, updated_at}`

**Khóa ứng viên**:
- K1: `{inventory_id}` (Surrogate key)
- K2: `{warehouse_id, product_id, batch_code}` (Natural composite key)

**Kiểm tra BCNF**: Tất cả FD có vế trái là siêu khóa ✓

**Kết luận**: ✅ **Đạt chuẩn BCNF**

#### **5. Sales_Invoice_Details**

**Lược đồ**: `sales_invoice_details(detail_id, invoice_id, product_id, quantity, unit_price, discount_percentage, discount_amount, subtotal, created_at)`

**Phụ thuộc hàm**:
- FD1: `detail_id → {invoice_id, product_id, quantity, unit_price, discount_percentage, discount_amount, subtotal, created_at}`
- FD2: `{invoice_id, product_id} → {detail_id, quantity, unit_price, discount_percentage, discount_amount, subtotal, created_at}` (trong thực tế, một hóa đơn có thể có nhiều dòng cho cùng 1 sản phẩm)

**Khóa ứng viên**:
- K1: `{detail_id}`

**Kiểm tra BCNF**: 
- FD1: `detail_id` là khóa chính, là siêu khóa ✓
- Không có FD nào khác vi phạm BCNF

**Kết luận**: ✅ **Đạt chuẩn BCNF**

## 4.2.2. Xử lý các phụ thuộc hàm

### **A. Phụ thuộc hàm tính toán**

Một số trường được tính toán từ các trường khác, tạo ra phụ thuộc hàm đặc biệt:

#### **1. Sales_Invoice_Details**
```sql
-- Phụ thuộc tính toán:
{unit_price, quantity, discount_percentage} → {discount_amount, subtotal}

-- Với công thức:
discount_amount = unit_price × quantity × (discount_percentage / 100)
subtotal = (unit_price × quantity) - discount_amount
```

**Xử lý**: Sử dụng trigger `tr_calculate_detail_subtotal` để tự động tính toán, đảm bảo tính nhất quán.

#### **2. Sales_Invoices**
```sql
-- Phụ thuộc tính toán từ bảng details:
invoice_id → {subtotal, discount_amount, tax_amount, total_amount}

-- Với công thức:
subtotal = SUM(details.subtotal)
discount_amount = SUM(details.discount_amount) 
tax_amount = (subtotal - discount_amount) × 0.10
total_amount = subtotal - discount_amount + tax_amount
```

**Xử lý**: Trigger `tr_calculate_invoice_totals` tự động cập nhật khi có thay đổi.

### **B. Phụ thuộc hàm đa giá trị (MVD)**

#### **1. Customer - Invoice relationship**
```sql
customer_id →→ invoice_id
customer_id →→ {total_spending, loyalty_points}
```

Mối quan hệ 1:N giữa Customer và Invoice không vi phạm BCNF vì được lưu trong các bảng riêng biệt.

#### **2. Product - Batch relationship** 
```sql
product_id →→ batch_code
warehouse_id →→ batch_code
```

Được xử lý thông qua bảng `warehouse_inventory` với composite key `{warehouse_id, product_id, batch_code}`.

### **C. Phụ thuộc hàm có điều kiện**

#### **1. Ràng buộc nghiệp vụ**
```sql
-- Trong products:
selling_price > import_price (luôn đúng)

-- Trong shelf_inventory:
current_quantity ≤ shelf_layout.max_quantity (cho cùng shelf_id, product_id)
```

**Xử lý**: Sử dụng CHECK constraints và triggers để đảm bảo.

## 4.2.3. Bảng kết quả sau chuẩn hóa

### **A. Tóm tắt kết quả kiểm tra**

| **Bảng** | **Khóa chính** | **Khóa ứng viên khác** | **Trạng thái BCNF** | **Ghi chú** |
|-----------|----------------|------------------------|-------------------|-------------|
| `product_categories` | category_id | category_name | ✅ Đạt BCNF | Đơn giản, không phụ thuộc phức tạp |
| `suppliers` | supplier_id | supplier_code | ✅ Đạt BCNF | Đơn giản, không phụ thuộc phức tạp |
| `positions` | position_id | position_code | ✅ Đạt BCNF | Đơn giản, không phụ thuộc phức tạp |
| `membership_levels` | level_id | level_name | ✅ Đạt BCNF | Đơn giản, không phụ thuộc phức tạp |
| `warehouse` | warehouse_id | warehouse_code | ✅ Đạt BCNF | Đơn giản, không phụ thuộc phức tạp |
| `employees` | employee_id | employee_code, email, id_card | ✅ Đạt BCNF | Nhiều unique constraints |
| `customers` | customer_id | customer_code, phone, membership_card_no | ✅ Đạt BCNF | Nhiều unique constraints |
| `products` | product_id | product_code, barcode | ✅ Đạt BCNF | Có ràng buộc giá bán > giá nhập |
| `display_shelves` | shelf_id | shelf_code | ✅ Đạt BCNF | Liên kết với category |
| `discount_rules` | rule_id | {category_id, days_before_expiry} | ✅ Đạt BCNF | Composite unique constraint |
| `warehouse_inventory` | inventory_id | {warehouse_id, product_id, batch_code} | ✅ Đạt BCNF | Surrogate + natural key |
| `shelf_inventory` | shelf_inventory_id | {shelf_id, product_id} | ✅ Đạt BCNF | Aggregated data |
| `shelf_batch_inventory` | shelf_batch_id | {shelf_id, product_id, batch_code} | ✅ Đạt BCNF | Chi tiết theo batch |
| `shelf_layout` | layout_id | {shelf_id, product_id}, {shelf_id, position_code} | ✅ Đạt BCNF | Dual unique constraints |
| `purchase_orders` | order_id | order_no | ✅ Đạt BCNF | Header table |
| `purchase_order_details` | detail_id | - | ✅ Đạt BCNF | Detail table |
| `sales_invoices` | invoice_id | invoice_no | ✅ Đạt BCNF | Header table với calculated fields |
| `sales_invoice_details` | detail_id | - | ✅ Đạt BCNF | Detail table với calculated fields |
| `stock_transfers` | transfer_id | transfer_code | ✅ Đạt BCNF | Giao dịch chuyển hàng |
| `employee_work_hours` | work_hour_id | {employee_id, work_date} | ✅ Đạt BCNF | Time-based data |

### **B. Các lợi ích đạt được**

#### **1. Loại bỏ dư thừa dữ liệu**
- Thông tin sản phẩm chỉ lưu trong bảng `products`
- Thông tin danh mục chỉ lưu trong bảng `product_categories`
- Thông tin khách hàng tách biệt với thông tin giao dịch

#### **2. Tránh bất thường cập nhật (Update Anomaly)**
- Thay đổi tên danh mục chỉ cần cập nhật 1 nơi
- Thay đổi thông tin nhà cung cấp không ảnh hưởng đến sản phẩm
- Cập nhật giá sản phẩm tự động lan truyền qua triggers

#### **3. Tránh bất thường xóa (Delete Anomaly)**  
- Xóa sản phẩm không làm mất thông tin danh mục
- Xóa nhân viên không làm mất thông tin chức vụ
- Foreign key constraints ngăn chặn xóa dữ liệu đang được tham chiếu

#### **4. Tránh bất thường chèn (Insert Anomaly)**
- Có thể tạo danh mục mới mà không cần sản phẩm
- Có thể tạo khách hàng mà không cần giao dịch ngay
- Có thể định nghĩa chức vụ mà không cần nhân viên

### **C. Kiểm chứng thiết kế**

#### **1. Test cases cho BCNF**

```sql
-- Test 1: Không thể có 2 sản phẩm cùng product_code
INSERT INTO products (product_code, product_name, ...) 
VALUES ('P001', 'Product A', ...);
-- Lỗi: duplicate key value violates unique constraint

-- Test 2: Không thể xóa category đang được sử dụng
DELETE FROM product_categories WHERE category_id = 1;
-- Lỗi: update or delete on table violates foreign key constraint

-- Test 3: Tự động tính toán subtotal
INSERT INTO sales_invoice_details (unit_price, quantity, discount_percentage) 
VALUES (100, 2, 10);
-- Kết quả: discount_amount = 20, subtotal = 180 (tự động tính)
```

#### **2. Performance benefits**

- **Joins hiệu quả**: Khóa chính là integer, tốc độ join cao
- **Index optimization**: Unique constraints tạo index tự động
- **Storage efficiency**: Không có redundant data

#### **3. Maintainability**

- **Clear schema**: Mỗi bảng có mục đích rõ ràng
- **Extensible**: Dễ dàng thêm thuộc tính mới
- **Consistent**: Triggers đảm bảo business rules
