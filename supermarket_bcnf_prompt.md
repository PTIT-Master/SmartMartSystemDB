# Hệ Thống Quản Lý Siêu Thị Bán Lẻ

## 📋 Tổng Quan Dự Án

Xây dựng hệ thống CSDL và ứng dụng quản lý siêu thị bán lẻ với đầy đủ chức năng quản lý hàng hóa, nhân viên, khách hàng và báo cáo kinh doanh.

## 🗄️ Yêu Cầu Database

### 1. Các Thực Thể Chính

#### 1.1 Nhân Viên (employees)

- [x] Thông tin cơ bản nhân viên
- [x] Vị trí công việc (positions)
- [x] Lương = lương cơ bản + lương theo giờ
- [x] Theo dõi giờ làm việc (employee_work_hours)

#### 1.2 Hàng Hóa (products)

- [x] Thông tin sản phẩm
- [x] Chủng loại (product_categories)
- [x] Giá bán > giá nhập (constraint)
- [x] Hạn sử dụng (shelf_life_days)
- [x] Ngưỡng cảnh báo tồn kho thấp

#### 1.3 Quầy Hàng (display_shelves)

- [x] Thông tin quầy hàng
- [x] Mỗi quầy chỉ bán 1 loại hàng (category_id)
- [x] Vị trí bày hàng (shelf_layout)
- [x] Số lượng tối đa cho mỗi sản phẩm
- [x] Tồn kho trên quầy (shelf_inventory)

#### 1.4 Kho Hàng (warehouse)

- [x] Thông tin kho
- [x] Tồn kho trong kho (warehouse_inventory)
- [x] Theo dõi lô hàng (batch_code)
- [x] Ngày nhập/hết hạn

#### 1.5 Nhà Cung Cấp (suppliers)

- [x] Thông tin nhà cung cấp
- [x] Liên kết với sản phẩm

#### 1.6 Khách Hàng (customers)

- [x] Thông tin khách hàng
- [x] Thẻ thành viên (membership_card_no)
- [x] Hạng thành viên (membership_levels)
- [x] Điểm tích lũy

### 2. Các Quan Hệ

- [x] Hóa đơn bán hàng (sales_invoices, sales_invoice_details)
- [x] Đơn đặt hàng (purchase_orders, purchase_order_details)
- [x] Chuyển kho lên quầy (stock_transfers)
- [x] Quy tắc giảm giá theo hạn sử dụng (discount_rules)

## 💻 Yêu Cầu Ứng Dụng

### 1. Chức Năng CRUD Cơ Bản

- [ ] **Quản lý Hàng Hóa**
  - [ ] Thêm/sửa/xóa sản phẩm
  - [ ] Tìm kiếm sản phẩm
  - [ ] Quản lý giá nhập/bán

- [ ] **Quản lý Nhân Viên**
  - [ ] Thêm/sửa/xóa nhân viên
  - [ ] Chấm công
  - [ ] Tính lương

- [ ] **Quản lý Khách Hàng**
  - [ ] Đăng ký thành viên
  - [ ] Cập nhật thông tin
  - [ ] Quản lý điểm thưởng

- [ ] **Quản lý Nhà Cung Cấp**
  - [ ] Thêm/sửa/xóa NCC
  - [ ] Theo dõi đơn hàng

### 2. Chức Năng Quản Lý Kho & Quầy Hàng

- [x] **Bổ sung hàng từ kho lên quầy** (fn_restock_shelf)
  - Kiểm tra số lượng trong kho
  - Không vượt quá sức chứa quầy
  - Ghi nhận lịch sử chuyển kho

- [x] **Cảnh báo tồn kho thấp**
  - Trigger cảnh báo khi < ngưỡng
  - View v_low_stock_shelves

- [x] **Xử lý bán hàng** (fn_process_sale)
  - Kiểm tra tồn kho trên quầy
  - Cập nhật số lượng sau bán
  - Tính điểm thưởng

### 3. Báo Cáo & Thống Kê

#### 3.1 Báo cáo Hàng Hóa

- [x] Liệt kê theo chủng loại/quầy hàng
- [x] Sắp xếp theo số lượng còn lại (v_products_by_shelf_quantity)
- [x] Sắp xếp theo số lượng bán trong ngày (v_products_by_daily_sales)
- [x] Hàng sắp hết trên quầy nhưng còn trong kho (v_products_need_restocking)
- [x] Hàng hết trong kho nhưng còn trên quầy (v_products_warehouse_empty)
- [x] Tổng tồn kho (quầy + kho) (v_total_inventory)
- [x] Xếp hạng doanh thu theo tháng (fn_product_revenue_ranking)

#### 3.2 Quản lý Hạn Sử Dụng

- [x] Tìm hàng quá hạn (v_expired_products)
- [x] Tự động giảm giá theo quy tắc (fn_apply_expiry_discounts)
  - Đồ khô < 5 ngày: giảm 50%
  - Rau quả < 1 ngày: giảm 50%

#### 3.3 Báo cáo Khách Hàng

- [x] Thông tin khách hàng thân thiết (v_customer_tier_analysis)
- [x] Xếp hạng theo chi tiêu (fn_get_top_customers)
- [x] Tự động nâng hạng thành viên

#### 3.4 Báo cáo Nhân Viên

- [x] Xếp hạng theo doanh số bán hàng (v_employee_performance)
- [x] Báo cáo doanh số theo tháng (v_employee_monthly_sales)
- [x] Tính lương chi tiết (fn_calculate_employee_salary)

#### 3.5 Báo cáo Nhà Cung Cấp

- [x] Xếp hạng theo doanh số (v_supplier_performance)
- [x] Thống kê sản phẩm và doanh thu (fn_get_supplier_ranking)

### 4. Chức Năng Hệ Thống

- [x] Dashboard tổng quan (fn_dashboard_summary)
- [x] Hệ thống cảnh báo (fn_get_system_alerts)
- [x] Báo cáo doanh thu hàng ngày (fn_daily_sales_report)

## 📊 Dữ Liệu Mẫu

- [x] Đã nhập dữ liệu mẫu cho:
  - 6 loại hàng hóa
  - 5 nhà cung cấp
  - 5 nhân viên
  - 10 sản phẩm
  - 5 quầy hàng
  - 5 khách hàng
  - Tồn kho ban đầu

- [ ] **Cần bổ sung thêm:**
  - [ ] Dữ liệu giao dịch 1 tháng
  - [ ] Lịch sử chấm công nhân viên
  - [ ] Đơn đặt hàng từ NCC

## 🚀 Tiến Độ Thực Hiện

### ✅ Đã Hoàn Thành

1. **Database Schema (100%)**
   - Thiết kế BCNF chuẩn hóa
   - Constraints và indexes
   - Triggers tự động

2. **Stored Procedures & Functions (100%)**
   - Các function xử lý nghiệp vụ chính
   - Views báo cáo

3. **Queries & Reports (100%)**
   - Đầy đủ queries phức tạp
   - Views thống kê

### 🔲 Cần Phát Triển

1. **Web Application**
   - [ ] Backend API (Node.js/Python)
   - [ ] Frontend UI (React/Vue)
   - [ ] Authentication & Authorization

2. **Mobile App** (Tùy chọn)
   - [ ] App cho nhân viên
   - [ ] App cho khách hàng

3. **Tích Hợp**
   - [ ] Barcode scanner
   - [ ] Payment gateway
   - [ ] SMS/Email notifications

## 📝 Ghi Chú Kỹ Thuật

### Database

- PostgreSQL với schema `supermarket`
- Sử dụng SERIAL cho primary keys
- Timestamps tự động cập nhật
- Triggers xử lý nghiệp vụ

### Best Practices

- Kiểm tra ràng buộc tại database level
- Sử dụng transactions cho data integrity
- Indexes cho performance
- Views cho security và simplicity

### Cần Lưu Ý

1. Giá bán phải > giá nhập (CHECK constraint)
2. Mỗi quầy chỉ bán 1 loại hàng
3. Không bán vượt quá tồn kho
4. Tự động cập nhật hạng thành viên
5. Cảnh báo hàng sắp hết hạn

## 🎯 Mục Tiêu Tiếp Theo

1. **Phase 1**: Xây dựng Web API
2. **Phase 2**: Phát triển giao diện web
3. **Phase 3**: Testing & deployment
4. **Phase 4**: Training & go-live
