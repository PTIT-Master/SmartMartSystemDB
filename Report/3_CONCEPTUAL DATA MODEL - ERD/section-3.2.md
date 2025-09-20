# 3.2. PHÂN TÍCH MỐI QUAN HỆ

Sau khi xác định được các thực thể chính, chúng ta tiến hành phân tích các mối quan hệ giữa chúng. Hệ thống quản lý siêu thị có các loại quan hệ đặc trưng từ đơn giản đến phức tạp.

## 3.2.1. Quan hệ 1-N (Một-nhiều)

### **Quan hệ cơ bản**

#### **Product_Categories (1) ← → Products (N)**
- **Mô tả**: Một chủng loại có thể chứa nhiều sản phẩm, nhưng mỗi sản phẩm chỉ thuộc về một chủng loại.
- **Cardinality**: 1:N
- **Khóa ngoại**: `products.category_id → product_categories.category_id`
- **Ý nghĩa nghiệp vụ**: Phân loại sản phẩm để quản lý theo danh mục và áp dụng các quy tắc kinh doanh riêng biệt.

#### **Suppliers (1) ← → Products (N)**
- **Mô tả**: Một nhà cung cấp có thể cung cấp nhiều sản phẩm, nhưng mỗi sản phẩm có một nhà cung cấp chính.
- **Cardinality**: 1:N
- **Khóa ngoại**: `products.supplier_id → suppliers.supplier_id`
- **Ý nghĩa nghiệp vụ**: Quản lý nguồn cung và đánh giá hiệu suất nhà cung cấp.

#### **Positions (1) ← → Employees (N)**
- **Mô tả**: Một vị trí có thể có nhiều nhân viên đảm nhiệm, mỗi nhân viên có một chức vụ.
- **Cardinality**: 1:N
- **Khóa ngoại**: `employees.position_id → positions.position_id`
- **Ý nghĩa nghiệp vụ**: Xác định lương cơ bản và lương theo giờ cho từng nhân viên.

#### **Membership_Levels (1) ← → Customers (N)**
- **Mô tả**: Một cấp độ thành viên có nhiều khách hàng, mỗi khách hàng thuộc một cấp độ.
- **Cardinality**: 1:N (optional - khách hàng có thể không có thẻ thành viên)
- **Khóa ngoại**: `customers.membership_level_id → membership_levels.level_id`
- **Ý nghĩa nghiệp vụ**: Áp dụng chương trình khuyến mại và tích điểm theo cấp độ.

### **Quan hệ với thực thể yếu**

#### **Employees (1) ← → Employee_Work_Hours (N)**
- **Mô tả**: Một nhân viên có nhiều bản ghi giờ làm việc (theo ngày), mỗi bản ghi thuộc về một nhân viên.
- **Cardinality**: 1:N
- **Khóa ngoại**: `employee_work_hours.employee_id → employees.employee_id`
- **Ràng buộc**: `UNIQUE (employee_id, work_date)` - một ngày chỉ có một bản ghi
- **Ý nghĩa nghiệp vụ**: Tính lương theo giờ làm việc thực tế.

#### **Warehouse (1) ← → Warehouse_Inventory (N)**
- **Mô tả**: Một kho chứa nhiều loại hàng hóa với nhiều lô khác nhau.
- **Cardinality**: 1:N
- **Khóa ngoại**: `warehouse_inventory.warehouse_id → warehouse.warehouse_id`
- **Ý nghĩa nghiệp vụ**: Quản lý tồn kho theo từng kho và theo từng lô hàng.

## 3.2.2. Quan hệ N-N (Nhiều-nhiều)

### **Products (N) ← → Display_Shelves (N)**
**Mô tả quan hệ phức tạp:** Một sản phẩm có thể được trưng bày trên nhiều quầy (tại nhiều vị trí khác nhau), và một quầy có thể trưng bày nhiều sản phẩm.

**Cách giải quyết:** Sử dụng các bảng trung gian:

#### **Shelf_Layout** (Bảng trung gian 1)
- **Vai trò**: Định nghĩa cấu hình trưng bày - sản phẩm nào được phép đặt ở quầy nào, vị trí nào, với số lượng tối đa bao nhiêu.
- **Khóa ngoại**:
  - `shelf_layout.shelf_id → display_shelves.shelf_id`
  - `shelf_layout.product_id → products.product_id`
- **Thuộc tính bổ sung**:
  - `position_code`: Vị trí cụ thể trên quầy
  - `max_quantity`: Sức chứa tối đa tại vị trí này
- **Ràng buộc**: 
  ```sql
  UNIQUE (shelf_id, product_id) -- Một sản phẩm chỉ có một vị trí trên mỗi quầy
  UNIQUE (shelf_id, position_code) -- Một vị trí chỉ dành cho một sản phẩm
  ```

#### **Shelf_Inventory** (Bảng trung gian 2)
- **Vai trò**: Lưu trữ số lượng thực tế hiện tại của từng sản phẩm trên từng quầy.
- **Khóa ngoại**: Tương tự `shelf_layout`
- **Thuộc tính bổ sung**:
  - `current_quantity`: Số lượng hiện có
  - `near_expiry_quantity`: Số lượng sắp hết hạn
  - `earliest_expiry_date`, `latest_expiry_date`: Thông tin hạn sử dụng

#### **Shelf_Batch_Inventory** (Bảng trung gian 3)
- **Vai trò**: Quản lý chi tiết từng lô hàng trên quầy (để xử lý hạn sử dụng và giá bán).
- **Thuộc tính bổ sung**:
  - `batch_code`: Mã lô hàng
  - `expiry_date`: Hạn sử dụng của lô này
  - `current_price`: Giá bán hiện tại (có thể khác giá gốc do giảm giá)

### **Products (N) ← → Warehouse (N)**
**Mô tả:** Một sản phẩm có thể được lưu trữ trong nhiều kho, một kho chứa nhiều sản phẩm.

**Bảng trung gian:** `Warehouse_Inventory`
- **Thuộc tính bổ sung**:
  - `batch_code`: Mã lô hàng (quan trọng cho FIFO)
  - `quantity`: Số lượng tồn kho
  - `import_date`: Ngày nhập kho
  - `expiry_date`: Hạn sử dụng (nếu có)
  - `import_price`: Giá nhập của lô này

## 3.2.3. Các quan hệ phức tạp và thực thể yếu

### **Quan hệ nghiệp vụ phức tạp**

#### **Stock_Transfers (Chuyển kho)**
**Mô tả:** Quan hệ ternary (3 chiều) liên kết Warehouse → Shelf thông qua Product.

**Các khóa ngoại:**
- `from_warehouse_id → warehouse.warehouse_id`
- `to_shelf_id → display_shelves.shelf_id`
- `product_id → products.product_id`
- `employee_id → employees.employee_id` (người thực hiện)

**Thuộc tính đặc biệt:**
- `transfer_code`: Mã chuyển kho (unique)
- `batch_code`: Mã lô hàng được chuyển
- `quantity`: Số lượng chuyển
- `expiry_date`, `import_price`, `selling_price`: Thông tin kèm theo

**Ý nghĩa nghiệp vụ:** Ghi nhận quá trình bổ sung hàng từ kho lên quầy bán.

#### **Purchase_Orders & Purchase_Order_Details**
**Mô tả:** Quan hệ 1-N điển hình cho nghiệp vụ nhập hàng.

**Purchase_Orders (Master):**
- **Liên kết**: Supplier (1) → Purchase_Orders (N)
- **Liên kết**: Employee (1) → Purchase_Orders (N) (người tạo đơn)

**Purchase_Order_Details (Details):**
- **Liên kết**: Purchase_Order (1) → Purchase_Order_Details (N)
- **Liên kết**: Product (1) → Purchase_Order_Details (N)

#### **Sales_Invoices & Sales_Invoice_Details**
**Mô tả:** Quan hệ 1-N cho nghiệp vụ bán hàng.

**Sales_Invoices (Master):**
- **Liên kết**: Customer (1) → Sales_Invoices (N) (optional - khách vãng lai)
- **Liên kết**: Employee (1) → Sales_Invoices (N) (nhân viên bán hàng)

**Sales_Invoice_Details (Details):**
- **Liên kết**: Sales_Invoice (1) → Sales_Invoice_Details (N)
- **Liên kết**: Product (1) → Sales_Invoice_Details (N)

### **Thực thể yếu và quan hệ định danh**

#### **Warehouse_Inventory**
- **Thực thể chủ**: Warehouse
- **Khóa định danh**: `(warehouse_id, product_id, batch_code)`
- **Lý do**: Mỗi lô hàng trong kho được xác định bởi kho + sản phẩm + mã lô

#### **Shelf_Layout**
- **Thực thể chủ**: Display_Shelves  
- **Khóa định danh**: `(shelf_id, product_id)` hoặc `(shelf_id, position_code)`
- **Lý do**: Vị trí trưng bày chỉ tồn tại khi có quầy hàng

#### **Employee_Work_Hours**
- **Thực thể chủ**: Employees
- **Khóa định danh**: `(employee_id, work_date)`
- **Lý do**: Bản ghi giờ làm chỉ có ý nghĩa khi gắn với nhân viên cụ thể

### **Quan hệ có điều kiện (Conditional Relationships)**

#### **Discount_Rules**
**Mô tả:** Áp dụng quy tắc giảm giá theo chủng loại sản phẩm và số ngày còn lại trước hết hạn.

**Khóa ngoại:** `category_id → product_categories.category_id`
**Ràng buộc:** `UNIQUE (category_id, days_before_expiry)` - mỗi khoảng ngày chỉ có một quy tắc

**Logic nghiệp vụ:**
```sql
-- Ví dụ: Rau củ giảm 50% khi còn 3 ngày hết hạn
-- Thực phẩm khô giảm 30% khi còn 5 ngày hết hạn
```

---

## Tóm tắt các loại quan hệ

| Loại quan hệ | Số lượng | Ví dụ điển hình | Đặc điểm |
|--------------|----------|-----------------|----------|
| **1:N đơn giản** | 6 | Category → Products | Khóa ngoại thông thường |
| **1:N với thực thể yếu** | 4 | Employee → Work_Hours | Khóa định danh phụ thuộc |
| **N:N qua bảng trung gian** | 2 | Product ↔ Shelf via Layout/Inventory | Có thuộc tính bổ sung |
| **Quan hệ ternary** | 2 | Stock_Transfers, Discount_Rules | Liên kết 3+ thực thể |
| **Master-Detail** | 2 | Invoice → Invoice_Details | Quan hệ cha-con |

Thiết kế này đảm bảo:
1. **Tính toàn vẹn dữ liệu** thông qua khóa ngoại và ràng buộc
2. **Linh hoạt nghiệp vụ** với các bảng trung gian có thuộc tính phong phú  
3. **Hiệu quả truy vấn** với các index phù hợp
4. **Khả năng mở rộng** cho các yêu cầu tương lai
