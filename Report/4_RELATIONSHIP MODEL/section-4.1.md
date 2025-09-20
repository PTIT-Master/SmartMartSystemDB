# 4.1. Chuyển đổi ERD sang lược đồ quan hệ

## 4.1.1. Ánh xạ thực thể mạnh

Các thực thể mạnh trong hệ thống siêu thị được ánh xạ trực tiếp thành các bảng quan hệ với khóa chính tự nhiên:

### **A. Thực thể cốt lõi**

**1. Product_Categories (Danh mục sản phẩm)**
```sql
product_categories (
    category_id [PK],
    category_name [UNIQUE],
    description,
    created_at,
    updated_at
)
```

**2. Suppliers (Nhà cung cấp)**
```sql
suppliers (
    supplier_id [PK],
    supplier_code [UNIQUE],
    supplier_name,
    contact_person,
    phone,
    email,
    address,
    tax_code,
    bank_account,
    is_active,
    created_at,
    updated_at
)
```

**3. Positions (Chức vụ nhân viên)**
```sql
positions (
    position_id [PK],
    position_code [UNIQUE],
    position_name,
    base_salary,
    hourly_rate,
    created_at
)
```

**4. Membership_Levels (Cấp độ thành viên)**
```sql
membership_levels (
    level_id [PK],
    level_name [UNIQUE],
    min_spending,
    discount_percentage,
    points_multiplier,
    created_at
)
```

**5. Warehouse (Kho hàng)**
```sql
warehouse (
    warehouse_id [PK],
    warehouse_code [UNIQUE],
    warehouse_name,
    location,
    manager_name,
    capacity,
    created_at
)
```

### **B. Thực thể phụ thuộc (có khóa ngoại)**

**1. Products (Sản phẩm)**
```sql
products (
    product_id [PK],
    product_code [UNIQUE],
    product_name,
    category_id [FK → product_categories.category_id],
    supplier_id [FK → suppliers.supplier_id],
    unit,
    import_price,
    selling_price,
    shelf_life_days,
    low_stock_threshold,
    barcode [UNIQUE],
    description,
    is_active,
    created_at,
    updated_at
)
```

**2. Display_Shelves (Quầy hàng)**
```sql
display_shelves (
    shelf_id [PK],
    shelf_code [UNIQUE],
    shelf_name,
    category_id [FK → product_categories.category_id],
    location,
    max_capacity,
    is_active,
    created_at
)
```

**3. Employees (Nhân viên)**
```sql
employees (
    employee_id [PK],
    employee_code [UNIQUE],
    full_name,
    position_id [FK → positions.position_id],
    phone,
    email [UNIQUE],
    address,
    hire_date,
    id_card [UNIQUE],
    bank_account,
    is_active,
    created_at,
    updated_at
)
```

**4. Customers (Khách hàng)**
```sql
customers (
    customer_id [PK],
    customer_code [UNIQUE],
    full_name,
    phone [UNIQUE],
    email,
    address,
    membership_card_no [UNIQUE],
    membership_level_id [FK → membership_levels.level_id],
    registration_date,
    total_spending,
    loyalty_points,
    is_active,
    created_at,
    updated_at
)
```

**5. Discount_Rules (Quy tắc giảm giá)**
```sql
discount_rules (
    rule_id [PK],
    category_id [FK → product_categories.category_id],
    days_before_expiry,
    discount_percentage,
    rule_name,
    is_active,
    created_at
)
```

## 4.1.2. Ánh xạ thực thể yếu

Các thực thể yếu phụ thuộc vào thực thể chủ để xác định duy nhất:

### **A. Warehouse_Inventory (Tồn kho)**
- **Thực thể chủ**: Warehouse, Products
- **Khóa phân biệt**: batch_code (trong cùng warehouse + product)
```sql
warehouse_inventory (
    inventory_id [PK - surrogate key],
    warehouse_id [FK → warehouse.warehouse_id],
    product_id [FK → products.product_id],
    batch_code,
    quantity,
    import_date,
    expiry_date,
    import_price,
    created_at,
    updated_at,
    UNIQUE(warehouse_id, product_id, batch_code)
)
```

### **B. Shelf_Layout (Bố trí quầy hàng)**
- **Thực thể chủ**: Display_Shelves, Products  
- **Khóa phân biệt**: position_code
```sql
shelf_layout (
    layout_id [PK - surrogate key],
    shelf_id [FK → display_shelves.shelf_id],
    product_id [FK → products.product_id],
    position_code,
    max_quantity,
    created_at,
    updated_at,
    UNIQUE(shelf_id, product_id),
    UNIQUE(shelf_id, position_code)
)
```

### **C. Shelf_Inventory (Tồn kho quầy hàng)**
- **Thực thể chủ**: Display_Shelves, Products
```sql
shelf_inventory (
    shelf_inventory_id [PK - surrogate key],
    shelf_id [FK → display_shelves.shelf_id],
    product_id [FK → products.product_id],
    current_quantity,
    near_expiry_quantity,
    expired_quantity,
    earliest_expiry_date,
    latest_expiry_date,
    last_restocked,
    updated_at,
    UNIQUE(shelf_id, product_id)
)
```

### **D. Shelf_Batch_Inventory (Chi tiết lô hàng trên quầy)**
- **Thực thể chủ**: Display_Shelves, Products
- **Khóa phân biệt**: batch_code
```sql
shelf_batch_inventory (
    shelf_batch_id [PK - surrogate key],
    shelf_id [FK → display_shelves.shelf_id],
    product_id [FK → products.product_id],
    batch_code,
    quantity,
    expiry_date,
    stocked_date,
    import_price,
    current_price,
    discount_percent,
    is_near_expiry,
    created_at,
    updated_at,
    UNIQUE(shelf_id, product_id, batch_code)
)
```

## 4.1.3. Ánh xạ các quan hệ

### **A. Quan hệ 1:N đơn giản**

Được thực hiện thông qua khóa ngoại trong bảng phía "nhiều":

1. **Category → Products** (1:N)
   - Mỗi danh mục có nhiều sản phẩm
   - products.category_id → product_categories.category_id

2. **Supplier → Products** (1:N)  
   - Mỗi nhà cung cấp có nhiều sản phẩm
   - products.supplier_id → suppliers.supplier_id

3. **Position → Employees** (1:N)
   - Mỗi chức vụ có nhiều nhân viên
   - employees.position_id → positions.position_id

### **B. Quan hệ N:M phức tạp**

Được ánh xạ thành các bảng trung gian với thuộc tính bổ sung:

**1. Purchase Orders (Đơn đặt hàng)**

*Bảng chủ:*
```sql
purchase_orders (
    order_id [PK],
    order_no [UNIQUE],
    supplier_id [FK → suppliers.supplier_id],
    employee_id [FK → employees.employee_id],
    order_date,
    delivery_date,
    total_amount,
    status,
    notes,
    created_at,
    updated_at
)
```

*Bảng chi tiết:*
```sql
purchase_order_details (
    detail_id [PK],
    order_id [FK → purchase_orders.order_id],
    product_id [FK → products.product_id],
    quantity,
    unit_price,
    subtotal,
    created_at
)
```

**2. Sales Invoices (Hóa đơn bán hàng)**

*Bảng chủ:*
```sql
sales_invoices (
    invoice_id [PK],
    invoice_no [UNIQUE],
    customer_id [FK → customers.customer_id] [NULLABLE],
    employee_id [FK → employees.employee_id],
    invoice_date,
    subtotal,
    discount_amount,
    tax_amount,
    total_amount,
    payment_method,
    points_earned,
    points_used,
    notes,
    created_at
)
```

*Bảng chi tiết:*
```sql
sales_invoice_details (
    detail_id [PK],
    invoice_id [FK → sales_invoices.invoice_id],
    product_id [FK → products.product_id],
    quantity,
    unit_price,
    discount_percentage,
    discount_amount,
    subtotal,
    created_at
)
```

### **C. Quan hệ đặc biệt**

**1. Stock_Transfers (Chuyển hàng)**
- Quan hệ tam ngôi: Warehouse → Product → Shelf
```sql
stock_transfers (
    transfer_id [PK],
    transfer_code [UNIQUE],
    product_id [FK → products.product_id],
    from_warehouse_id [FK → warehouse.warehouse_id],
    to_shelf_id [FK → display_shelves.shelf_id],
    quantity,
    transfer_date,
    employee_id [FK → employees.employee_id],
    batch_code,
    expiry_date,
    import_price,
    selling_price,
    notes,
    created_at
)
```

**2. Employee_Work_Hours (Giờ làm việc)**
- Quan hệ 1:N với thuộc tính phụ thuộc thời gian
```sql
employee_work_hours (
    work_hour_id [PK],
    employee_id [FK → employees.employee_id],
    work_date,
    check_in_time,
    check_out_time,
    total_hours,
    created_at,
    UNIQUE(employee_id, work_date)
)
```

### **D. Ràng buộc tham chiếu (Referential Integrity)**

Tất cả các khóa ngoại đều có ràng buộc `ON DELETE RESTRICT` và `ON UPDATE CASCADE` mặc định để:

1. **Đảm bảo tính toàn vẹn**: Không cho phép xóa bản ghi được tham chiếu
2. **Tự động cập nhật**: Khi khóa chính thay đổi, khóa ngoại tự động được cập nhật
3. **Cascade update**: Áp dụng cho các trường hợp cập nhật mã định danh

**Ví dụ:**
```sql
ALTER TABLE products 
ADD CONSTRAINT fk_products_category 
FOREIGN KEY (category_id) REFERENCES product_categories(category_id);

ALTER TABLE products 
ADD CONSTRAINT fk_products_supplier 
FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id);
```
