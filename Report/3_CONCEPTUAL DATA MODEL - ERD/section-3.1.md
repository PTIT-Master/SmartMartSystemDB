# 3.1. XÁC ĐỊNH CÁC THỰC THỂ CHÍNH

Dựa trên phân tích yêu cầu nghiệp vụ của hệ thống quản lý siêu thị bán lẻ, chúng ta xác định được các thực thể chính và nhóm các thực thể liên quan như sau:

## 3.1.1. Products & Product_Categories

### **Products (Sản phẩm)**
Đây là thực thể trung tâm của hệ thống, lưu trữ thông tin về tất cả các mặt hàng trong siêu thị.

**Thuộc tính chính:**
- `product_id` (PK): Mã định danh duy nhất cho sản phẩm
- `product_code`: Mã sản phẩm (unique, dễ nhớ cho nhân viên)
- `product_name`: Tên sản phẩm
- `category_id` (FK): Liên kết đến chủng loại sản phẩm
- `supplier_id` (FK): Nhà cung cấp
- `unit`: Đơn vị tính (kg, lít, cái, ...)
- `import_price`: Giá nhập (phải > 0)
- `selling_price`: Giá bán (phải > import_price)
- `shelf_life_days`: Số ngày hạn sử dụng (cho hàng có hạn)
- `low_stock_threshold`: Ngưỡng cảnh báo hết hàng
- `barcode`: Mã vạch (unique, nullable)
- `description`: Mô tả chi tiết
- `is_active`: Trạng thái hoạt động

**Ràng buộc quan trọng:**
```sql
CONSTRAINT check_price CHECK (selling_price > import_price)
CONSTRAINT chk_products_import_price CHECK (import_price > 0)
```

### **Product_Categories (Chủng loại sản phẩm)**
Phân loại sản phẩm theo nhóm (văn phòng phẩm, đồ gia dụng, thực phẩm, đồ uống, ...).

**Thuộc tính chính:**
- `category_id` (PK): Mã định danh chủng loại
- `category_name`: Tên chủng loại (unique)
- `description`: Mô tả chi tiết
- `created_at`, `updated_at`: Thời gian tạo/cập nhật

**Vai trò nghiệp vụ:**
- Quy định phân loại hàng hóa theo quầy (mỗi quầy chỉ bày bán một chủng loại)
- Áp dụng quy tắc giảm giá theo từng loại hàng (thông qua `discount_rules`)

## 3.1.2. Warehouse & Warehouse_Inventory

### **Warehouse (Kho hàng)**
Thông tin về các kho lưu trữ hàng hóa trong siêu thị.

**Thuộc tính chính:**
- `warehouse_id` (PK): Mã định danh kho
- `warehouse_code`: Mã kho (unique)
- `warehouse_name`: Tên kho
- `location`: Vị trí kho
- `manager_name`: Tên quản lý kho
- `capacity`: Sức chứa tối đa

### **Warehouse_Inventory (Tồn kho)**
Thực thể yếu lưu trữ thông tin chi tiết về số lượng hàng hóa trong từng kho theo từng lô hàng.

**Thuộc tính chính:**
- `inventory_id` (PK): Mã định danh bản ghi tồn kho
- `warehouse_id` (FK): Kho chứa
- `product_id` (FK): Sản phẩm
- `batch_code`: Mã lô hàng (quan trọng cho FIFO)
- `quantity`: Số lượng tồn (>= 0)
- `import_date`: Ngày nhập kho
- `expiry_date`: Hạn sử dụng (tự động tính hoặc nhập thủ công)
- `import_price`: Giá nhập của lô hàng này

**Ràng buộc nghiệp vụ:**
```sql
CONSTRAINT unique_batch UNIQUE (warehouse_id, product_id, batch_code)
CONSTRAINT chk_warehouse_inventory_quantity CHECK (quantity >= 0)
```

## 3.1.3. Display_Shelves & Shelf_Inventory

### **Display_Shelves (Quầy hàng)**
Thông tin về các quầy bày bán hàng hóa trong siêu thị.

**Thuộc tính chính:**
- `shelf_id` (PK): Mã định danh quầy hàng
- `shelf_code`: Mã quầy (unique)
- `shelf_name`: Tên quầy
- `category_id` (FK): Chủng loại hàng hóa mà quầy này bày bán
- `location`: Vị trí trong siêu thị
- `max_capacity`: Sức chứa tối đa tổng thể
- `is_active`: Trạng thái hoạt động

**Ràng buộc quan trọng:** Mỗi quầy chỉ bày bán các hàng hóa thuộc cùng một chủng loại.

### **Shelf_Layout (Bố trí quầy hàng)**
Thực thể yếu quy định vị trí và số lượng tối đa cho từng sản phẩm trên mỗi quầy.

**Thuộc tính chính:**
- `layout_id` (PK): Mã định danh bố trí
- `shelf_id` (FK): Quầy hàng
- `product_id` (FK): Sản phẩm
- `position_code`: Mã vị trí trên quầy
- `max_quantity`: Số lượng tối đa cho phép tại vị trí này

**Ràng buộc:**
```sql
CONSTRAINT unique_shelf_product UNIQUE (shelf_id, product_id)
CONSTRAINT unique_shelf_position UNIQUE (shelf_id, position_code)
```

### **Shelf_Inventory (Tồn kho quầy hàng)**
Thực thể yếu lưu trữ số lượng thực tế của từng sản phẩm trên từng quầy.

**Thuộc tính chính:**
- `shelf_inventory_id` (PK): Mã định danh
- `shelf_id` (FK): Quầy hàng
- `product_id` (FK): Sản phẩm
- `current_quantity`: Số lượng hiện tại (>= 0)
- `near_expiry_quantity`: Số lượng sắp hết hạn
- `expired_quantity`: Số lượng đã hết hạn
- `earliest_expiry_date`: Ngày hết hạn sớm nhất
- `latest_expiry_date`: Ngày hết hạn muộn nhất
- `last_restocked`: Lần bổ sung gần nhất

### **Shelf_Batch_Inventory (Tồn kho theo lô trên quầy)**
Theo dõi chi tiết từng lô hàng trên quầy để quản lý hạn sử dụng và giá bán.

**Thuộc tính chính:**
- `shelf_batch_id` (PK): Mã định danh
- `shelf_id` (FK): Quầy hàng
- `product_id` (FK): Sản phẩm  
- `batch_code`: Mã lô hàng
- `quantity`: Số lượng của lô này
- `expiry_date`: Hạn sử dụng
- `import_price`: Giá nhập của lô
- `current_price`: Giá bán hiện tại (có thể giảm do sắp hết hạn)
- `discount_percent`: Phần trăm giảm giá
- `is_near_expiry`: Đánh dấu sắp hết hạn

## 3.1.4. Employees & Positions

### **Positions (Chức vụ)**
Định nghĩa các vị trí làm việc trong siêu thị và mức lương tương ứng.

**Thuộc tính chính:**
- `position_id` (PK): Mã chức vụ
- `position_code`: Mã chức vụ (unique)
- `position_name`: Tên chức vụ
- `base_salary`: Lương cơ bản (>= 0)
- `hourly_rate`: Lương theo giờ (>= 0)

### **Employees (Nhân viên)**
Thông tin về tất cả nhân viên trong siêu thị.

**Thuộc tính chính:**
- `employee_id` (PK): Mã nhân viên
- `employee_code`: Mã nhân viên (unique)
- `full_name`: Họ tên đầy đủ
- `position_id` (FK): Chức vụ
- `phone`: Số điện thoại
- `email`: Email (unique)
- `address`: Địa chỉ
- `hire_date`: Ngày tuyển dụng
- `id_card`: CMND/CCCD (unique)
- `bank_account`: Tài khoản ngân hàng
- `is_active`: Trạng thái làm việc

### **Employee_Work_Hours (Giờ làm việc)**
Thực thể yếu ghi nhận giờ làm việc hàng ngày của từng nhân viên.

**Thuộc tính chính:**
- `work_hour_id` (PK): Mã định danh
- `employee_id` (FK): Nhân viên
- `work_date`: Ngày làm việc
- `check_in_time`: Giờ vào làm
- `check_out_time`: Giờ tan làm
- `total_hours`: Tổng giờ làm việc (tự động tính)

**Ràng buộc:**
```sql
CONSTRAINT unique_employee_date UNIQUE (employee_id, work_date)
```

## 3.1.5. Customers & Membership_Levels

### **Membership_Levels (Cấp độ thành viên)**
Định nghĩa các cấp độ thành viên và quyền lợi tương ứng.

**Thuộc tính chính:**
- `level_id` (PK): Mã cấp độ
- `level_name`: Tên cấp độ (Bronze, Silver, Gold, ...)
- `min_spending`: Mức chi tiêu tối thiểu để đạt cấp độ này
- `discount_percentage`: Phần trăm chiết khấu mặc định
- `points_multiplier`: Hệ số tích điểm (1.0, 1.2, 1.5, ...)

### **Customers (Khách hàng)**
Thông tin về khách hàng thành viên của siêu thị.

**Thuộc tính chính:**
- `customer_id` (PK): Mã khách hàng
- `customer_code`: Mã khách hàng (unique)
- `full_name`: Họ tên
- `phone`: Số điện thoại (unique)
- `email`: Email
- `address`: Địa chỉ
- `membership_card_no`: Số thẻ thành viên (unique)
- `membership_level_id` (FK): Cấp độ thành viên
- `registration_date`: Ngày đăng ký
- `total_spending`: Tổng chi tiêu (tự động cập nhật)
- `loyalty_points`: Điểm tích lũy (tự động cập nhật)
- `is_active`: Trạng thái hoạt động

## 3.1.6. Suppliers

### **Suppliers (Nhà cung cấp)**
Thông tin về các nhà cung cấp hàng hóa cho siêu thị.

**Thuộc tính chính:**
- `supplier_id` (PK): Mã nhà cung cấp
- `supplier_code`: Mã nhà cung cấp (unique)
- `supplier_name`: Tên nhà cung cấp
- `contact_person`: Người liên hệ
- `phone`: Số điện thoại
- `email`: Email
- `address`: Địa chỉ
- `tax_code`: Mã số thuế
- `bank_account`: Tài khoản ngân hàng
- `is_active`: Trạng thái hợp tác

---

## Tóm tắt các thực thể chính

| STT | Nhóm thực thể | Thực thể chính | Thực thể yếu | Vai trò |
|-----|---------------|----------------|--------------|---------|
| 1 | **Products** | Products, Product_Categories | - | Quản lý thông tin sản phẩm và phân loại |
| 2 | **Warehouse** | Warehouse | Warehouse_Inventory | Quản lý kho và tồn kho theo lô |
| 3 | **Display** | Display_Shelves | Shelf_Layout, Shelf_Inventory, Shelf_Batch_Inventory | Quản lý quầy hàng và trưng bày |
| 4 | **HR** | Employees, Positions | Employee_Work_Hours | Quản lý nhân sự và chấm công |
| 5 | **Customer** | Customers, Membership_Levels | - | Quản lý khách hàng và chương trình thành viên |
| 6 | **Supplier** | Suppliers | - | Quản lý nhà cung cấp |

Các thực thể này tạo thành nền tảng dữ liệu cho toàn bộ hoạt động của siêu thị, từ quản lý hàng hóa, kho bãi, nhân sự đến chăm sóc khách hàng và quan hệ với nhà cung cấp.
