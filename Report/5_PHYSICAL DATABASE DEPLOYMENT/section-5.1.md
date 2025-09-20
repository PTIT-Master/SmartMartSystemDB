# 5.1. CẤU TRÚC BẢNG VÀ THUỘC TÍNH

## 5.1.1. Định nghĩa kiểu dữ liệu

### Phân tích kiểu dữ liệu được sử dụng

Trong hệ thống quản lý siêu thị, chúng ta sử dụng các kiểu dữ liệu PostgreSQL phù hợp với đặc thù nghiệp vụ:

#### **Nhóm kiểu dữ liệu số**

```sql
-- Kiểu BIGINT cho ID và số lượng lớn
customer_id BIGINT NOT NULL,
quantity BIGINT NOT NULL,

-- Kiểu NUMERIC(12,2) cho tiền tệ - đảm bảo độ chính xác
import_price NUMERIC(12,2) NOT NULL,
selling_price NUMERIC(12,2) NOT NULL,
total_amount NUMERIC(12,2) DEFAULT 0 NOT NULL,

-- Kiểu NUMERIC(5,2) cho phần trăm
discount_percentage NUMERIC(5,2) DEFAULT 0,

-- Kiểu NUMERIC(3,2) cho hệ số nhỏ
points_multiplier NUMERIC(3,2) DEFAULT 1,
```

**Lý do chọn:**
- `BIGINT`: Phù hợp cho ID (auto-increment) và số lượng hàng hóa có thể lớn
- `NUMERIC(12,2)`: Chính xác tuyệt đối cho tiền tệ, tránh sai số floating point
- `NUMERIC(5,2)`: Đủ cho phần trăm từ 0.00% đến 999.99%

#### **Nhóm kiểu dữ liệu chuỗi**

```sql
-- VARCHAR với độ dài giới hạn cho mã code
product_code VARCHAR(50) NOT NULL,
customer_code VARCHAR(20),
employee_code VARCHAR(20) NOT NULL,

-- VARCHAR cho tên, tiêu đề
product_name VARCHAR(200) NOT NULL,
supplier_name VARCHAR(200) NOT NULL,
full_name VARCHAR(100) NOT NULL,

-- TEXT cho nội dung dài, không giới hạn
address TEXT,
description TEXT,
notes TEXT,
```

**Lý do chọn:**
- `VARCHAR(n)`: Tiết kiệm bộ nhớ, phù hợp cho dữ liệu có độ dài cố định
- `TEXT`: Linh hoạt cho nội dung mô tả, ghi chú

#### **Nhóm kiểu dữ liệu thời gian**

```sql
-- DATE cho ngày thuần
hire_date DATE DEFAULT CURRENT_DATE NOT NULL,
order_date DATE DEFAULT CURRENT_DATE NOT NULL,
expiry_date DATE,

-- TIMESTAMP WITH TIME ZONE cho thời điểm chính xác
invoice_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
created_at TIMESTAMP WITH TIME ZONE,
updated_at TIMESTAMP WITH TIME ZONE,
```

**Lý do chọn:**
- `DATE`: Đủ cho ngày sinh, ngày thuê, hạn sử dụng
- `TIMESTAMP WITH TIME ZONE`: Quan trọng cho audit trail và giao dịch

#### **Kiểu dữ liệu logic**

```sql
-- BOOLEAN cho trạng thái
is_active BOOLEAN DEFAULT true,
is_near_expiry BOOLEAN DEFAULT false,
```

## 5.1.2. Ràng buộc mức cột (CHECK, NOT NULL, UNIQUE)

### **Ràng buộc NOT NULL**

```sql
-- Các trường bắt buộc
CREATE TABLE supermarket.products (
    product_id BIGINT NOT NULL,
    product_code VARCHAR(50) NOT NULL,
    product_name VARCHAR(200) NOT NULL,
    category_id BIGINT NOT NULL,
    supplier_id BIGINT NOT NULL,
    unit VARCHAR(20) NOT NULL,
    import_price NUMERIC(12,2) NOT NULL,
    selling_price NUMERIC(12,2) NOT NULL,
    hire_date DATE DEFAULT CURRENT_DATE NOT NULL
);
```

### **Ràng buộc CHECK - Kiểm tra tính hợp lệ dữ liệu**

#### **Ràng buộc giá trị dương**

```sql
-- Đảm bảo giá tiền > 0
CONSTRAINT chk_products_import_price CHECK (import_price > 0),

-- Đảm bảo số lượng >= 0
CONSTRAINT chk_warehouse_inventory_quantity CHECK (quantity >= 0),
CONSTRAINT chk_shelf_inventory_current_quantity CHECK (current_quantity >= 0),

-- Đảm bảo số lượng tối đa > 0
CONSTRAINT chk_shelf_layout_max_quantity CHECK (max_quantity > 0),
```

#### **Ràng buộc phần trăm hợp lệ**

```sql
-- Giảm giá từ 0% đến 100%
CONSTRAINT chk_discount_rules_discount_percentage 
    CHECK (discount_percentage >= 0 AND discount_percentage <= 100),
```

#### **Ràng buộc logic nghiệp vụ quan trọng**

```sql
-- Giá bán phải > giá nhập
CONSTRAINT check_price CHECK (selling_price > import_price),

-- Lương cơ bản >= 0
CONSTRAINT chk_positions_base_salary CHECK (base_salary >= 0),
CONSTRAINT chk_positions_hourly_rate CHECK (hourly_rate >= 0),
```

### **Ràng buộc UNIQUE - Đảm bảo tính duy nhất**

#### **Unique cho mã code**

```sql
-- Mã sản phẩm duy nhất
CONSTRAINT uni_products_product_code UNIQUE (product_code),

-- Mã nhân viên duy nhất
CONSTRAINT uni_employees_employee_code UNIQUE (employee_code),

-- Mã khách hàng duy nhất  
CONSTRAINT uni_customers_customer_code UNIQUE (customer_code),

-- Mã hóa đơn duy nhất
CONSTRAINT uni_sales_invoices_invoice_no UNIQUE (invoice_no),
```

#### **Unique cho thông tin cá nhân**

```sql
-- Số điện thoại duy nhất
CONSTRAINT uni_customers_phone UNIQUE (phone),

-- Email nhân viên duy nhất
CONSTRAINT uni_employees_email UNIQUE (email),

-- CMND duy nhất
CONSTRAINT uni_employees_id_card UNIQUE (id_card),

-- Thẻ thành viên duy nhất
CONSTRAINT uni_customers_membership_card_no UNIQUE (membership_card_no),
```

#### **Unique cho nghiệp vụ phức hợp**

```sql
-- Mỗi nhân viên chỉ 1 bản ghi công/ngày
CONSTRAINT unique_employee_date UNIQUE (employee_id, work_date),

-- Mỗi quầy + sản phẩm chỉ có 1 vị trí
CONSTRAINT unique_shelf_product UNIQUE (shelf_id, product_id),

-- Mỗi batch + warehouse + product là duy nhất
CONSTRAINT unique_batch UNIQUE (warehouse_id, product_id, batch_code),
```

## 5.1.3. Ràng buộc mức bảng (PRIMARY KEY, FOREIGN KEY)

### **PRIMARY KEY - Khóa chính**

#### **Khóa chính đơn**

```sql
-- Bảng chính với khóa tự động tăng
ALTER TABLE supermarket.products 
    ADD CONSTRAINT products_pkey PRIMARY KEY (product_id);

ALTER TABLE supermarket.customers 
    ADD CONSTRAINT customers_pkey PRIMARY KEY (customer_id);

ALTER TABLE supermarket.employees 
    ADD CONSTRAINT employees_pkey PRIMARY KEY (employee_id);
```

#### **Khóa chính tổng hợp** (nếu cần)

```sql
-- Một số bảng có thể dùng composite key
-- Ví dụ: shelf_inventory có unique constraint thay vì composite PK
CONSTRAINT unique_shelf_product_inv UNIQUE (shelf_id, product_id)
```

### **FOREIGN KEY - Khóa ngoại và tính toàn vẹn tham chiếu**

#### **Quan hệ 1-N cơ bản**

```sql
-- Products → Categories
ALTER TABLE supermarket.products
    ADD CONSTRAINT fk_products_category 
    FOREIGN KEY (category_id) REFERENCES supermarket.product_categories(category_id);

-- Products → Suppliers  
ALTER TABLE supermarket.products
    ADD CONSTRAINT fk_products_supplier 
    FOREIGN KEY (supplier_id) REFERENCES supermarket.suppliers(supplier_id);

-- Employees → Positions
ALTER TABLE supermarket.employees
    ADD CONSTRAINT fk_employees_position 
    FOREIGN KEY (position_id) REFERENCES supermarket.positions(position_id);
```

#### **Quan hệ trong giao dịch**

```sql
-- Sales Invoice Details → Sales Invoices
ALTER TABLE supermarket.sales_invoice_details
    ADD CONSTRAINT fk_sales_invoice_details_invoice 
    FOREIGN KEY (invoice_id) REFERENCES supermarket.sales_invoices(invoice_id);

-- Sales Invoices → Customers (nullable)
ALTER TABLE supermarket.sales_invoices
    ADD CONSTRAINT fk_sales_invoices_customer 
    FOREIGN KEY (customer_id) REFERENCES supermarket.customers(customer_id);

-- Sales Invoices → Employees  
ALTER TABLE supermarket.sales_invoices
    ADD CONSTRAINT fk_sales_invoices_employee 
    FOREIGN KEY (employee_id) REFERENCES supermarket.employees(employee_id);
```

#### **Quan hệ trong quản lý kho**

```sql
-- Stock Transfers → Products
ALTER TABLE supermarket.stock_transfers
    ADD CONSTRAINT fk_stock_transfers_product 
    FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);

-- Stock Transfers → Warehouse (from)
ALTER TABLE supermarket.stock_transfers
    ADD CONSTRAINT fk_stock_transfers_from_warehouse 
    FOREIGN KEY (from_warehouse_id) REFERENCES supermarket.warehouse(warehouse_id);

-- Stock Transfers → Display_Shelves (to)
ALTER TABLE supermarket.stock_transfers
    ADD CONSTRAINT fk_stock_transfers_to_shelf 
    FOREIGN KEY (to_shelf_id) REFERENCES supermarket.display_shelves(shelf_id);
```

#### **Quan hệ phức tạp với ràng buộc kép**

```sql
-- Shelf Batch Inventory → Shelf Inventory
ALTER TABLE supermarket.shelf_batch_inventory
    ADD CONSTRAINT fk_shelf_inventory_batch_items 
    FOREIGN KEY (shelf_id, product_id) 
    REFERENCES supermarket.shelf_inventory(shelf_id, product_id);
```

## 5.1.4. Giá trị mặc định và tự động tăng

### **SEQUENCE cho ID tự động tăng**

```sql
-- Tạo sequence cho products
CREATE SEQUENCE supermarket.products_product_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Gán sequence cho cột
ALTER TABLE supermarket.products 
    ALTER COLUMN product_id SET DEFAULT nextval('supermarket.products_product_id_seq');

-- Gán ownership
ALTER SEQUENCE supermarket.products_product_id_seq 
    OWNED BY supermarket.products.product_id;
```

### **Giá trị mặc định thời gian**

```sql
-- Ngày hiện tại
registration_date DATE DEFAULT CURRENT_DATE,
hire_date DATE DEFAULT CURRENT_DATE NOT NULL,
order_date DATE DEFAULT CURRENT_DATE NOT NULL,

-- Timestamp hiện tại  
invoice_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
last_restocked TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
transfer_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
```

### **Giá trị mặc định số học**

```sql
-- Giá trị 0 cho tiền tệ
total_spending NUMERIC(12,2) DEFAULT 0,
loyalty_points BIGINT DEFAULT 0,
total_amount NUMERIC(12,2) DEFAULT 0 NOT NULL,

-- Giá trị mặc định cho số lượng
current_quantity BIGINT DEFAULT 0 NOT NULL,
near_expiry_quantity BIGINT DEFAULT 0,
expired_quantity BIGINT DEFAULT 0,

-- Phần trăm mặc định
discount_percentage NUMERIC(5,2) DEFAULT 0,
discount_percent NUMERIC(5,2) DEFAULT 0,
```

### **Giá trị mặc định boolean**

```sql
-- Trạng thái hoạt động mặc định là true
is_active BOOLEAN DEFAULT true,

-- Trạng thái gần hết hạn mặc định là false  
is_near_expiry BOOLEAN DEFAULT false,

-- Quy tắc giảm giá mặc định hoạt động
is_active BOOLEAN DEFAULT true,
```

### **Giá trị mặc định chuỗi**

```sql
-- Trạng thái đơn hàng mặc định
status VARCHAR(20) DEFAULT 'PENDING',

-- Warehouse mặc định (ID = 1)
warehouse_id BIGINT DEFAULT 1 NOT NULL,
```

### **Ưu điểm của việc sử dụng DEFAULT**

1. **Đảm bảo tính nhất quán**: Tránh NULL không mong muốn
2. **Đơn giản hóa INSERT**: Không cần specify tất cả columns
3. **Business logic**: Embed logic nghiệp vụ vào DB level
4. **Data integrity**: Đảm bảo dữ liệu luôn trong trạng thái hợp lệ

### **Ví dụ về INSERT với DEFAULT values**

```sql
-- Chỉ cần insert các trường bắt buộc, phần còn lại tự động
INSERT INTO supermarket.customers (customer_code, full_name, phone)
VALUES ('CUS001', 'Nguyen Van A', '0901234567');
-- registration_date = CURRENT_DATE
-- total_spending = 0
-- loyalty_points = 0  
-- is_active = true
-- created_at = CURRENT_TIMESTAMP (via trigger)
```

Hệ thống ràng buộc và giá trị mặc định được thiết kế nhằm đảm bảo tính toàn vẹn dữ liệu ở mức cơ sở dữ liệu, tạo nền tảng vững chắc cho các tầng ứng dụng phía trên.
