# 3.3. SƠ ĐỒ ERD HOÀN CHỈNH

Sau khi xác định các thực thể và phân tích mối quan hệ, chúng ta tổng hợp thành sơ đồ ERD hoàn chỉnh cho hệ thống quản lý siêu thị. Sơ đồ này thể hiện đầy đủ cấu trúc dữ liệu và các quy tắc nghiệp vụ.

## 3.3.1. ERD tổng thể với các thuộc tính

### **Cấu trúc ERD theo nhóm chức năng**

```
[PRODUCT MANAGEMENT]
Product_Categories(1) ──→ (N)Products(N) ──→ (1)Suppliers
         │                      │
         │                      │
         └─ Discount_Rules       └─ Products liên kết đến các module khác

[WAREHOUSE MANAGEMENT]
Warehouse(1) ──→ (N)Warehouse_Inventory(M) ──→ (1)Products
     │                    │
     └─ warehouse_code     └─ batch_code, expiry_date, import_price

[SHELF MANAGEMENT]
Display_Shelves(1) ──→ (N)Shelf_Layout(M) ──→ (1)Products
       │                      │
       │                  Shelf_Inventory(M) ──→ Products
       │                      │
       └─ category_id      Shelf_Batch_Inventory ──→ Products

[HUMAN RESOURCES]
Positions(1) ──→ (N)Employees(1) ──→ (N)Employee_Work_Hours
                    │
                    └─ Employees tham gia vào Sales & Transfers

[CUSTOMER MANAGEMENT]
Membership_Levels(1) ──→ (N)Customers
                              │
                              └─ Customers tham gia Sales_Invoices

[BUSINESS PROCESSES]
Stock_Transfers: Warehouse + Display_Shelves + Products + Employees
Purchase_Orders: Suppliers + Employees + Products
Sales_Invoices: Customers + Employees + Products
```

### **Sơ đồ ERD chi tiết**

#### **Core Entities (Thực thể trung tâm)**

**Products** [PK: product_id]
- product_code (UNIQUE)
- product_name
- category_id (FK → Product_Categories)
- supplier_id (FK → Suppliers) 
- unit, import_price, selling_price
- shelf_life_days, low_stock_threshold
- barcode (UNIQUE), description
- is_active, created_at, updated_at

**Product_Categories** [PK: category_id]
- category_name (UNIQUE)
- description
- created_at, updated_at

#### **Storage Management**

**Warehouse** [PK: warehouse_id]
- warehouse_code (UNIQUE), warehouse_name
- location, manager_name, capacity
- created_at

**Warehouse_Inventory** [PK: inventory_id, UNIQUE: (warehouse_id, product_id, batch_code)]
- warehouse_id (FK), product_id (FK)
- batch_code, quantity (≥0)
- import_date, expiry_date, import_price
- created_at, updated_at

**Display_Shelves** [PK: shelf_id]
- shelf_code (UNIQUE), shelf_name
- category_id (FK → Product_Categories)
- location, max_capacity, is_active
- created_at

**Shelf_Layout** [PK: layout_id, UNIQUE: (shelf_id, product_id)]
- shelf_id (FK), product_id (FK)
- position_code, max_quantity (>0)
- created_at, updated_at

**Shelf_Inventory** [PK: shelf_inventory_id, UNIQUE: (shelf_id, product_id)]
- shelf_id (FK), product_id (FK)
- current_quantity (≥0), near_expiry_quantity (≥0)
- expired_quantity (≥0)
- earliest_expiry_date, latest_expiry_date
- last_restocked, updated_at

#### **Human Resources**

**Positions** [PK: position_id]
- position_code (UNIQUE), position_name
- base_salary (≥0), hourly_rate (≥0)
- created_at

**Employees** [PK: employee_id]
- employee_code (UNIQUE), full_name
- position_id (FK)
- phone, email (UNIQUE), address
- hire_date, id_card (UNIQUE)
- bank_account, is_active
- created_at, updated_at

#### **Business Processes**

**Stock_Transfers** [PK: transfer_id]
- transfer_code (UNIQUE)
- product_id (FK), from_warehouse_id (FK)
- to_shelf_id (FK), employee_id (FK)
- quantity (>0), batch_code
- expiry_date, import_price, selling_price
- transfer_date, notes, created_at

**Purchase_Orders** [PK: order_id]
- order_no (UNIQUE)
- supplier_id (FK), employee_id (FK)
- order_date, delivery_date
- total_amount (≥0), status
- notes, created_at, updated_at

**Sales_Invoices** [PK: invoice_id]
- invoice_no (UNIQUE)
- customer_id (FK, optional), employee_id (FK)
- invoice_date, subtotal, discount_amount
- tax_amount, total_amount
- payment_method, points_earned, points_used
- notes, created_at

## 3.3.2. Giải thích Cardinality

### **Quan hệ 1:N (One-to-Many)**

| Thực thể cha (1) | Thực thể con (N) | Cardinality | Giải thích |
|------------------|------------------|-------------|------------|
| Product_Categories | Products | 1:∞ | Một chủng loại chứa nhiều sản phẩm |
| Suppliers | Products | 1:∞ | Một nhà cung cấp cung cấp nhiều sản phẩm |
| Positions | Employees | 1:∞ | Một vị trí có nhiều nhân viên đảm nhiệm |
| Employees | Sales_Invoices | 1:∞ | Một nhân viên xử lý nhiều hóa đơn |
| Customers | Sales_Invoices | 1:∞ | Một khách hàng có nhiều hóa đơn |
| Membership_Levels | Customers | 1:∞ | Một cấp độ thành viên có nhiều khách hàng |

### **Quan hệ N:M (Many-to-Many)**

| Thực thể A | Thực thể B | Bảng trung gian | Cardinality | Ý nghĩa |
|------------|------------|------------------|-------------|---------|
| Products | Display_Shelves | Shelf_Layout | N:M | Sản phẩm có thể ở nhiều quầy, quầy chứa nhiều sản phẩm |
| Products | Warehouse | Warehouse_Inventory | N:M | Sản phẩm có thể ở nhiều kho, kho chứa nhiều sản phẩm |

### **Quan hệ đặc biệt**

#### **Weak Entity Relationships**
- **Employee_Work_Hours** phụ thuộc vào **Employees**: `(employee_id, work_date)`
- **Purchase_Order_Details** phụ thuộc vào **Purchase_Orders**: `(order_id, product_id)`
- **Sales_Invoice_Details** phụ thuộc vào **Sales_Invoices**: `(invoice_id, product_id)`

#### **Ternary Relationships**
- **Stock_Transfers**: Liên kết Warehouse → Shelf thông qua Product và Employee
- **Discount_Rules**: Liên kết Category với Days_Before_Expiry và Discount_Percentage

## 3.3.3. Business Rules được thể hiện trong ERD

### **Ràng buộc giá trị (Value Constraints)**

```sql
-- Giá bán phải lớn hơn giá nhập
CONSTRAINT check_price CHECK (selling_price > import_price)

-- Số lượng không âm
CONSTRAINT chk_quantity CHECK (quantity >= 0)

-- Lương cơ bản và lương giờ không âm
CONSTRAINT chk_salary CHECK (base_salary >= 0 AND hourly_rate >= 0)

-- Phần trăm giảm giá trong khoảng 0-100%
CONSTRAINT chk_discount CHECK (discount_percentage BETWEEN 0 AND 100)
```

### **Ràng buộc tính duy nhất (Uniqueness Constraints)**

```sql
-- Mã sản phẩm duy nhất
CONSTRAINT uni_products_product_code UNIQUE (product_code)

-- Một nhân viên chỉ có một bản ghi giờ làm mỗi ngày
CONSTRAINT unique_employee_date UNIQUE (employee_id, work_date)

-- Một lô hàng chỉ tồn tại một lần trong mỗi kho
CONSTRAINT unique_batch UNIQUE (warehouse_id, product_id, batch_code)

-- Một sản phẩm chỉ có một vị trí trên mỗi quầy
CONSTRAINT unique_shelf_product UNIQUE (shelf_id, product_id)
```

### **Ràng buộc quan hệ nghiệp vụ (Business Relationship Rules)**

#### **Rule 1: Phân loại hàng theo quầy**
```sql
-- Trigger đảm bảo sản phẩm chỉ được đặt trên quầy cùng chủng loại
CREATE TRIGGER tr_validate_shelf_category_consistency
BEFORE INSERT OR UPDATE ON shelf_layout
FOR EACH ROW EXECUTE FUNCTION validate_shelf_category_consistency();
```

#### **Rule 2: Kiểm soát sức chứa quầy**
```sql
-- Không được vượt quá số lượng tối đa cho phép
CREATE TRIGGER tr_validate_shelf_capacity  
BEFORE INSERT OR UPDATE ON shelf_inventory
FOR EACH ROW EXECUTE FUNCTION validate_shelf_capacity();
```

#### **Rule 3: Quản lý tồn kho FIFO**
```sql
-- Bổ sung hàng lên quầy theo nguyên tắc FIFO (First In, First Out)
CREATE PROCEDURE sp_replenish_shelf_stock(product_id, shelf_id, quantity, employee_id)
-- Logic: Chọn lô hàng cũ nhất để chuyển lên quầy trước
```

#### **Rule 4: Tự động cập nhật thông tin khách hàng**
```sql
-- Cập nhật điểm thưởng và tổng chi tiêu khi có giao dịch
CREATE TRIGGER tr_update_customer_metrics
BEFORE INSERT OR UPDATE ON sales_invoices  
FOR EACH ROW EXECUTE FUNCTION update_customer_metrics();

-- Tự động nâng cấp cấp độ thành viên
CREATE TRIGGER tr_check_membership_upgrade
AFTER UPDATE OF total_spending ON customers
FOR EACH ROW EXECUTE FUNCTION check_membership_upgrade();
```

#### **Rule 5: Quản lý hạn sử dụng và giảm giá**
```sql
-- Tự động tính hạn sử dụng khi nhập kho
CREATE TRIGGER tr_calculate_expiry_date
BEFORE INSERT OR UPDATE ON warehouse_inventory
FOR EACH ROW EXECUTE FUNCTION calculate_expiry_date();

-- Áp dụng quy tắc giảm giá theo hạn sử dụng
CREATE TRIGGER tr_apply_expiry_discounts  
AFTER INSERT OR UPDATE OF expiry_date ON warehouse_inventory
FOR EACH ROW EXECUTE FUNCTION apply_expiry_discounts();
```

### **Ràng buộc toàn vẹn tham chiếu (Referential Integrity)**

#### **CASCADE Operations**
- **DELETE CASCADE**: Khi xóa hóa đơn → tự động xóa chi tiết hóa đơn
- **UPDATE CASCADE**: Khi thay đổi mã sản phẩm → cập nhật tất cả bảng liên quan

#### **RESTRICT Operations**  
- Không cho phép xóa chủng loại sản phẩm nếu còn sản phẩm thuộc chủng loại đó
- Không cho phép xóa nhân viên nếu còn hóa đơn do nhân viên đó tạo

### **Ràng buộc thời gian (Temporal Constraints)**

```sql
-- Ngày giao hàng phải sau ngày đặt hàng
CONSTRAINT chk_delivery_date CHECK (delivery_date >= order_date)

-- Giờ tan làm phải sau giờ vào làm  
CONSTRAINT chk_work_time CHECK (check_out_time > check_in_time)

-- Hạn sử dụng phải sau ngày nhập kho
CONSTRAINT chk_expiry_date CHECK (expiry_date >= import_date)
```

---

## Tổng kết ERD

### **Thống kê tổng quan**

| Loại thành phần | Số lượng | Ghi chú |
|-----------------|----------|---------|
| **Strong Entities** | 8 | Suppliers, Product_Categories, Products, Positions, Employees, Membership_Levels, Customers, Warehouse, Display_Shelves |
| **Weak Entities** | 7 | Warehouse_Inventory, Shelf_Layout, Shelf_Inventory, Shelf_Batch_Inventory, Employee_Work_Hours, Purchase_Order_Details, Sales_Invoice_Details |
| **Transaction Entities** | 4 | Purchase_Orders, Sales_Invoices, Stock_Transfers, Discount_Rules |
| **Relationships 1:N** | 15+ | Đa số các quan hệ cơ bản |
| **Relationships N:M** | 3 | Thông qua bảng trung gian |
| **Business Rules** | 20+ | Triggers, constraints, procedures |

### **Đặc điểm thiết kế**

1. **Chuẩn hóa cao**: ERD đạt chuẩn BCNF, giảm thiểu redundancy
2. **Tách biệt nghiệp vụ**: Mỗi nhóm chức năng có các thực thể riêng biệt
3. **Linh hoạt mở rộng**: Dễ dàng thêm thuộc tính và quan hệ mới
4. **Tự động hóa**: Nhiều business rules được implement qua triggers
5. **Truy vết đầy đủ**: Batch tracking, audit trail, transaction history

ERD này cung cấp foundation vững chắc để implement hệ thống quản lý siêu thị đáp ứng đầy đủ các yêu cầu trong đề tài, đồng thời có khả năng mở rộng cho các tính năng tương lai.
