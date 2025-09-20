# 4.3. Lược đồ quan hệ chi tiết

## 4.3.1. Diagram lược đồ quan hệ

### **A. Cấu trúc tổng thể**

Hệ thống được tổ chức thành 6 nhóm bảng chính:

```
┌─────────────────────────────────────────────────────────────────┐
│                      HỆ THỐNG QUẢN LÝ SIÊU THỊ                 │
└─────────────────────────────────────────────────────────────────┘

├── 📦 NHÓM SẢN PHẨM & PHÂN LOẠI
│   ├── product_categories (1) ──┐
│   ├── products (N) ────────────┤
│   └── suppliers (1) ───────────┘
│
├── 🏢 NHÓM KHO VÀ QUẦY HÀNG  
│   ├── warehouse (1) ──────────┐
│   ├── warehouse_inventory (N) ─┤
│   ├── display_shelves (1) ─────┤
│   ├── shelf_layout (N) ────────┤
│   ├── shelf_inventory (N) ─────┤  
│   └── shelf_batch_inventory (N)┘
│
├── 👥 NHÓM NHÂN VIÊN
│   ├── positions (1) ──────────┐
│   ├── employees (N) ──────────┤
│   └── employee_work_hours (N) ┘
│
├── 👤 NHÓM KHÁCH HÀNG
│   ├── membership_levels (1) ──┐
│   └── customers (N) ──────────┘
│
├── 🛒 NHÓM GIAO DỊCH BÁN HÀNG
│   ├── sales_invoices (1) ─────┐
│   └── sales_invoice_details (N)┘
│
├── 📋 NHÓM NHẬP HÀNG
│   ├── purchase_orders (1) ────┐
│   └── purchase_order_details (N)┘
│
└── ⚙️  NHÓM HỆ THỐNG
    ├── stock_transfers
    └── discount_rules
```

### **B. Mối quan hệ chính**

```
product_categories (1:N) products (N:1) suppliers
                     │                      │
                     └──┐                ┌──┘
                        │                │
               ┌────────▼────────────────▼───────────┐
               │                                    │
               ▼                                    ▼
    warehouse_inventory              purchase_order_details
               │                                    │
               │          stock_transfers           │
               │                 │                  │
               ▼                 ▼                  ▼
    shelf_inventory ◄── shelf_batch_inventory      │
               │                                    │
               ▼                                    │
    sales_invoice_details ◄─────────────────────────┘
               │
               ▼
         sales_invoices
               │
               ▼
          customers
```

## 4.3.2. Danh sách các bảng với khóa chính/ngoại

### **A. Nhóm sản phẩm và phân loại**

#### **1. product_categories** - Danh mục sản phẩm
```sql
Khóa chính: category_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: category_name (VARCHAR(100))
Không có khóa ngoại
```
**Thuộc tính**: category_id, category_name, description, created_at, updated_at

#### **2. suppliers** - Nhà cung cấp  
```sql
Khóa chính: supplier_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: supplier_code (VARCHAR(20))
Không có khóa ngoại
```
**Thuộc tính**: supplier_id, supplier_code, supplier_name, contact_person, phone, email, address, tax_code, bank_account, is_active, created_at, updated_at

#### **3. products** - Sản phẩm
```sql
Khóa chính: product_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: product_code (VARCHAR(50)), barcode (VARCHAR(50))
Khóa ngoại: 
  - category_id → product_categories.category_id
  - supplier_id → suppliers.supplier_id
```
**Thuộc tính**: product_id, product_code, product_name, category_id, supplier_id, unit, import_price, selling_price, shelf_life_days, low_stock_threshold, barcode, description, is_active, created_at, updated_at

### **B. Nhóm kho và quầy hàng**

#### **4. warehouse** - Kho hàng
```sql
Khóa chính: warehouse_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: warehouse_code (VARCHAR(20))
Không có khóa ngoại
```
**Thuộc tính**: warehouse_id, warehouse_code, warehouse_name, location, manager_name, capacity, created_at

#### **5. warehouse_inventory** - Tồn kho
```sql
Khóa chính: inventory_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: (warehouse_id, product_id, batch_code)
Khóa ngoại:
  - warehouse_id → warehouse.warehouse_id  
  - product_id → products.product_id
```
**Thuộc tính**: inventory_id, warehouse_id, product_id, batch_code, quantity, import_date, expiry_date, import_price, created_at, updated_at

#### **6. display_shelves** - Quầy hàng
```sql
Khóa chính: shelf_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: shelf_code (VARCHAR(20))
Khóa ngoại:
  - category_id → product_categories.category_id
```
**Thuộc tính**: shelf_id, shelf_code, shelf_name, category_id, location, max_capacity, is_active, created_at

#### **7. shelf_layout** - Bố trí quầy hàng
```sql
Khóa chính: layout_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: (shelf_id, product_id), (shelf_id, position_code)
Khóa ngoại:
  - shelf_id → display_shelves.shelf_id
  - product_id → products.product_id
```
**Thuộc tính**: layout_id, shelf_id, product_id, position_code, max_quantity, created_at, updated_at

#### **8. shelf_inventory** - Tồn kho quầy hàng
```sql
Khóa chính: shelf_inventory_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: (shelf_id, product_id)
Khóa ngoại:
  - shelf_id → display_shelves.shelf_id
  - product_id → products.product_id
```
**Thuộc tính**: shelf_inventory_id, shelf_id, product_id, current_quantity, near_expiry_quantity, expired_quantity, earliest_expiry_date, latest_expiry_date, last_restocked, updated_at

#### **9. shelf_batch_inventory** - Chi tiết lô hàng trên quầy
```sql
Khóa chính: shelf_batch_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: (shelf_id, product_id, batch_code)
Khóa ngoại:
  - shelf_id → display_shelves.shelf_id
  - product_id → products.product_id
  - (shelf_id, product_id) → shelf_inventory(shelf_id, product_id)
```
**Thuộc tính**: shelf_batch_id, shelf_id, product_id, batch_code, quantity, expiry_date, stocked_date, import_price, current_price, discount_percent, is_near_expiry, created_at, updated_at

### **C. Nhóm nhân viên**

#### **10. positions** - Chức vụ
```sql
Khóa chính: position_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: position_code (VARCHAR(20))
Không có khóa ngoại
```
**Thuộc tính**: position_id, position_code, position_name, base_salary, hourly_rate, created_at

#### **11. employees** - Nhân viên
```sql
Khóa chính: employee_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: employee_code (VARCHAR(20)), email (VARCHAR(100)), id_card (VARCHAR(20))
Khóa ngoại:
  - position_id → positions.position_id
```
**Thuộc tính**: employee_id, employee_code, full_name, position_id, phone, email, address, hire_date, id_card, bank_account, is_active, created_at, updated_at

#### **12. employee_work_hours** - Giờ làm việc
```sql
Khóa chính: work_hour_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: (employee_id, work_date)
Khóa ngoại:
  - employee_id → employees.employee_id
```
**Thuộc tính**: work_hour_id, employee_id, work_date, check_in_time, check_out_time, total_hours, created_at

### **D. Nhóm khách hàng**

#### **13. membership_levels** - Cấp độ thành viên
```sql
Khóa chính: level_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: level_name (VARCHAR(50))
Không có khóa ngoại
```
**Thuộc tính**: level_id, level_name, min_spending, discount_percentage, points_multiplier, created_at

#### **14. customers** - Khách hàng
```sql
Khóa chính: customer_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: customer_code (VARCHAR(20)), phone (VARCHAR(20)), membership_card_no (VARCHAR(20))
Khóa ngoại:
  - membership_level_id → membership_levels.level_id [NULLABLE]
```
**Thuộc tính**: customer_id, customer_code, full_name, phone, email, address, membership_card_no, membership_level_id, registration_date, total_spending, loyalty_points, is_active, created_at, updated_at

### **E. Nhóm giao dịch bán hàng**

#### **15. sales_invoices** - Hóa đơn bán hàng
```sql
Khóa chính: invoice_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: invoice_no (VARCHAR(30))
Khóa ngoại:
  - customer_id → customers.customer_id [NULLABLE]
  - employee_id → employees.employee_id
```
**Thuộc tính**: invoice_id, invoice_no, customer_id, employee_id, invoice_date, subtotal, discount_amount, tax_amount, total_amount, payment_method, points_earned, points_used, notes, created_at

#### **16. sales_invoice_details** - Chi tiết hóa đơn
```sql
Khóa chính: detail_id (BIGINT, AUTO_INCREMENT)
Không có khóa duy nhất bổ sung
Khóa ngoại:
  - invoice_id → sales_invoices.invoice_id
  - product_id → products.product_id
```
**Thuộc tính**: detail_id, invoice_id, product_id, quantity, unit_price, discount_percentage, discount_amount, subtotal, created_at

### **F. Nhóm nhập hàng**

#### **17. purchase_orders** - Đơn đặt hàng
```sql
Khóa chính: order_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: order_no (VARCHAR(30))
Khóa ngoại:
  - supplier_id → suppliers.supplier_id
  - employee_id → employees.employee_id
```
**Thuộc tính**: order_id, order_no, supplier_id, employee_id, order_date, delivery_date, total_amount, status, notes, created_at, updated_at

#### **18. purchase_order_details** - Chi tiết đơn đặt hàng
```sql
Khóa chính: detail_id (BIGINT, AUTO_INCREMENT)
Không có khóa duy nhất bổ sung
Khóa ngoại:
  - order_id → purchase_orders.order_id
  - product_id → products.product_id
```
**Thuộc tính**: detail_id, order_id, product_id, quantity, unit_price, subtotal, created_at

### **G. Nhóm hệ thống**

#### **19. stock_transfers** - Chuyển hàng
```sql
Khóa chính: transfer_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: transfer_code (VARCHAR(30))
Khóa ngoại:
  - product_id → products.product_id
  - from_warehouse_id → warehouse.warehouse_id
  - to_shelf_id → display_shelves.shelf_id
  - employee_id → employees.employee_id
```
**Thuộc tính**: transfer_id, transfer_code, product_id, from_warehouse_id, to_shelf_id, quantity, transfer_date, employee_id, batch_code, expiry_date, import_price, selling_price, notes, created_at

#### **20. discount_rules** - Quy tắc giảm giá
```sql
Khóa chính: rule_id (BIGINT, AUTO_INCREMENT)
Khóa duy nhất: (category_id, days_before_expiry)
Khóa ngoại:
  - category_id → product_categories.category_id
```
**Thuộc tính**: rule_id, category_id, days_before_expiry, discount_percentage, rule_name, is_active, created_at

## 4.3.3. Mô tả ý nghĩa từng bảng

### **A. Nhóm Master Data (Dữ liệu chủ)**

#### **1. product_categories** - Danh mục sản phẩm
- **Mục đích**: Phân loại sản phẩm theo nhóm (đồ gia dụng, thực phẩm, văn phòng phẩm...)
- **Business Rule**: Mỗi quầy hàng chỉ bán sản phẩm thuộc một danh mục
- **Quan hệ**: 1:N với products, display_shelves, discount_rules

#### **2. suppliers** - Nhà cung cấp
- **Mục đích**: Quản lý thông tin các nhà cung cấp hàng hóa
- **Business Rule**: Mỗi sản phẩm có duy nhất một nhà cung cấp chính
- **Quan hệ**: 1:N với products, purchase_orders

#### **3. positions** - Chức vụ nhân viên
- **Mục đích**: Định nghĩa các vị trí công việc và mức lương
- **Business Rule**: Lương = base_salary + (total_hours × hourly_rate)
- **Quan hệ**: 1:N với employees

#### **4. membership_levels** - Cấp độ thành viên
- **Mục đích**: Phân cấp khách hàng theo mức chi tiêu
- **Business Rule**: Tự động nâng cấp khi total_spending đạt min_spending
- **Quan hệ**: 1:N với customers

#### **5. warehouse** - Kho hàng
- **Mục đích**: Quản lý không gian lưu trữ hàng hóa
- **Business Rule**: Hàng phải nhập kho trước khi lên quầy
- **Quan hệ**: 1:N với warehouse_inventory, stock_transfers

### **B. Nhóm Inventory (Quản lý tồn kho)**

#### **6. products** - Sản phẩm
- **Mục đích**: Master data của tất cả mặt hàng trong hệ thống
- **Business Rule**: selling_price > import_price (ràng buộc CHECK)
- **Quan hệ**: Hub table kết nối với tất cả các bảng khác

#### **7. warehouse_inventory** - Tồn kho
- **Mục đích**: Theo dõi số lượng hàng trong kho theo từng lô (batch)
- **Business Rule**: Hỗ trợ FIFO (First In First Out) cho việc xuất hàng
- **Quan hệ**: Nguồn dữ liệu cho stock_transfers

#### **8. display_shelves** - Quầy hàng
- **Mục đích**: Định nghĩa các vị trí bán hàng
- **Business Rule**: Mỗi quầy chỉ bán một loại danh mục sản phẩm
- **Quan hệ**: 1:N với shelf_layout, shelf_inventory

#### **9. shelf_layout** - Bố trí quầy hàng
- **Mục đích**: Cấu hình sản phẩm nào được bày tại vị trí nào, với số lượng tối đa
- **Business Rule**: Mỗi sản phẩm chỉ có một vị trí trên mỗi quầy
- **Quan hệ**: Template cho shelf_inventory

#### **10. shelf_inventory** - Tồn kho quầy hàng (Aggregated)
- **Mục đích**: Tổng hợp số lượng hiện có trên quầy (tất cả các batch)
- **Business Rule**: current_quantity ≤ shelf_layout.max_quantity
- **Quan hệ**: 1:N với shelf_batch_inventory

#### **11. shelf_batch_inventory** - Chi tiết lô hàng trên quầy
- **Mục đích**: Theo dõi từng lô hàng cụ thể trên quầy (hạn sử dụng, giá)
- **Business Rule**: Hỗ trợ dynamic pricing theo hạn sử dụng
- **Quan hệ**: Child table của shelf_inventory

### **C. Nhóm Human Resources (Nhân sự)**

#### **12. employees** - Nhân viên
- **Mục đích**: Quản lý thông tin nhân viên
- **Business Rule**: employee_code, email, id_card phải duy nhất
- **Quan hệ**: Tham gia vào tất cả các giao dịch (bán hàng, nhập hàng, chuyển kho)

#### **13. employee_work_hours** - Giờ làm việc
- **Mục đích**: Chấm công và tính lương theo giờ
- **Business Rule**: total_hours = check_out_time - check_in_time
- **Quan hệ**: Chi tiết của employees theo thời gian

#### **14. customers** - Khách hàng
- **Mục đích**: Quản lý khách hàng và chương trình loyalty
- **Business Rule**: Tự động cập nhật total_spending và loyalty_points
- **Quan hệ**: Optional trong sales_invoices (khách lẻ không cần đăng ký)

### **D. Nhóm Transactions (Giao dịch)**

#### **15. purchase_orders + purchase_order_details** - Đơn nhập hàng
- **Mục đích**: Quản lý quá trình đặt hàng từ nhà cung cấp
- **Business Rule**: total_amount tự động tính từ các detail records
- **Quan hệ**: Header-Detail pattern, nguồn tạo warehouse_inventory

#### **16. sales_invoices + sales_invoice_details** - Hóa đơn bán hàng
- **Mục đích**: Ghi nhận các giao dịch bán hàng
- **Business Rule**: Tự động trừ tồn kho quầy, cộng điểm thành viên
- **Quan hệ**: Header-Detail pattern, trigger stock deduction

#### **17. stock_transfers** - Chuyển hàng
- **Mục đích**: Ghi nhận quá trình chuyển hàng từ kho lên quầy
- **Business Rule**: Kiểm tra tồn kho trước khi chuyển, cập nhật cả hai bên
- **Quan hệ**: Kết nối warehouse_inventory và shelf_inventory

### **E. Nhóm Business Rules (Quy tắc nghiệp vụ)**

#### **18. discount_rules** - Quy tắc giảm giá
- **Mục đích**: Định nghĩa chính sách giảm giá theo hạn sử dụng
- **Business Rule**: Áp dụng tự động khi hàng gần hết hạn
- **Quan hệ**: Áp dụng cho từng category, trigger cập nhật giá

### **F. Các đặc điểm thiết kế quan trọng**

#### **1. Audit Trail**
- Tất cả bảng có `created_at`, nhiều bảng có `updated_at`
- Triggers tự động cập nhật timestamps

#### **2. Soft Delete**
- Sử dụng `is_active` thay vì xóa thực sự cho master data
- Đảm bảo referential integrity và audit trail

#### **3. Surrogate Keys**
- Tất cả bảng dùng BIGINT AUTO_INCREMENT làm khóa chính
- Natural keys được dùng làm UNIQUE constraints

#### **4. Batch Tracking**
- Hỗ trợ quản lý theo lô hàng với batch_code
- Theo dõi hạn sử dụng và FIFO

#### **5. Calculated Fields**
- Các trường tính toán (subtotal, total_amount) được lưu trữ
- Triggers đảm bảo tính nhất quán khi dữ liệu thay đổi
