# MỤC LỤC BÁO CÁO

## HỆ THỐNG QUẢN LÝ SIÊU THỊ BÁN LẺ

---

## **PHẦN I: TỔNG QUAN**

### 1.1. Giới thiệu đề tài

### 1.2. Mục tiêu hệ thống

### 1.3. Phạm vi và giới hạn

### 1.4. Cấu trúc báo cáo

---

## **PHẦN II: PHÂN TÍCH YÊU CẦU HỆ THỐNG**

### 2.1. **Phân tích nghiệp vụ**

- 2.1.1. Quy trình nhập hàng và quản lý kho
- 2.1.2. Quy trình chuyển hàng từ kho lên quầy
- 2.1.3. Quy trình bán hàng và thanh toán
- 2.1.4. Quy trình quản lý hạn sử dụng và giảm giá

### 2.2. **Xác định các yêu cầu chức năng**

- 2.2.1. Nhóm chức năng CRUD cơ bản
- 2.2.2. Nhóm chức năng quản lý tồn kho
- 2.2.3. Nhóm chức năng cảnh báo và tự động hóa
- 2.2.4. Nhóm chức năng báo cáo thống kê

### 2.3. **Các ràng buộc nghiệp vụ quan trọng**

- 2.3.1. Ràng buộc giá bán > giá nhập
- 2.3.2. Ràng buộc sức chứa quầy hàng
- 2.3.3. Ràng buộc phân loại hàng theo quầy
- 2.3.4. Ràng buộc số lượng kho - quầy
- 2.3.5. Ràng buộc hạn sử dụng

---

## **PHẦN III: MÔ HÌNH DỮ LIỆU KHÁI NIỆM - ERD**

### 3.1. **Xác định các thực thể chính**

- 3.1.1. Products & Product_Categories
- 3.1.2. Warehouse & Warehouse_Inventory
- 3.1.3. Display_Shelves & Shelf_Inventory
- 3.1.4. Employees & Positions
- 3.1.5. Customers & Membership_Levels
- 3.1.6. Suppliers

### 3.2. **Phân tích mối quan hệ**

- 3.2.1. Quan hệ 1-n (một-nhiều)
- 3.2.2. Quan hệ n-n (nhiều-nhiều)
- 3.2.3. Các quan hệ phức tạp và thực thể yếu

### 3.3. **Sơ đồ ERD hoàn chỉnh**

- 3.3.1. ERD tổng thể với các thuộc tính
- 3.3.2. Giải thích cardinality
- 3.3.3. Business rules được thể hiện trong ERD

---

## **PHẦN IV: MÔ HÌNH QUAN HỆ**

### 4.1. **Chuyển đổi ERD sang lược đồ quan hệ**

- 4.1.1. Ánh xạ thực thể mạnh
- 4.1.2. Ánh xạ thực thể yếu
- 4.1.3. Ánh xạ các quan hệ

### 4.2. **Chuẩn hóa BCNF**

- 4.2.1. Kiểm tra và chứng minh đạt chuẩn BCNF
- 4.2.2. Xử lý các phụ thuộc hàm
- 4.2.3. Bảng kết quả sau chuẩn hóa

### 4.3. **Lược đồ quan hệ chi tiết**

- 4.3.1. Diagram lược đồ quan hệ
- 4.3.2. Danh sách các bảng với khóa chính/ngoại
- 4.3.3. Mô tả ý nghĩa từng bảng

---

## **PHẦN V: TRIỂN KHAI CƠ SỞ DỮ LIỆU VẬT LÝ**

### 5.1. **Cấu trúc bảng và thuộc tính**

- 5.1.1. Định nghĩa kiểu dữ liệu
- 5.1.2. Ràng buộc mức cột (CHECK, NOT NULL, UNIQUE)
- 5.1.3. Ràng buộc mức bảng (PRIMARY KEY, FOREIGN KEY)
- 5.1.4. Giá trị mặc định và tự động tăng

### 5.2. **Index và tối ưu hóa**

- 5.2.1. Index cho khóa chính/ngoại
- 5.2.2. Index cho các cột thường query
- 5.2.3. Index cho báo cáo thống kê

---

## **PHẦN VI: XỬ LÝ LOGIC NGHIỆP VỤ BẰNG DATABASE**

### 6.1. **Triggers - Xử lý tự động**

#### 6.1.1. **Nhóm triggers quản lý tồn kho**

- `tr_process_sales_stock_deduction`: Tự động trừ tồn kho khi bán
- `tr_process_stock_transfer`: Tự động cập nhật khi chuyển hàng
- `tr_validate_stock_transfer`: Kiểm tra tồn kho trước khi chuyển

#### 6.1.2. **Nhóm triggers tính toán**

- `tr_calculate_detail_subtotal`: Tính tiền chi tiết hóa đơn
- `tr_calculate_invoice_totals`: Tính tổng hóa đơn
- `tr_update_customer_metrics`: Cập nhật điểm thành viên
- `tr_calculate_work_hours`: Tính giờ làm việc
- `tr_update_purchase_order_total`: Cập nhật tổng đơn nhập hàng

#### 6.1.3. **Nhóm triggers kiểm tra ràng buộc**

- `tr_validate_shelf_capacity`: Kiểm tra sức chứa quầy
- `tr_validate_product_price`: Đảm bảo giá bán > giá nhập
- `tr_check_low_stock`: Cảnh báo tồn kho thấp
- `tr_validate_shelf_category_consistency`: Kiểm tra phân loại hàng theo quầy
- `tr_check_membership_upgrade`: Tự động nâng cấp thành viên

#### 6.1.4. **Nhóm triggers xử lý hạn sử dụng**

- `tr_calculate_expiry_date`: Tính hạn sử dụng
- `tr_apply_expiry_discounts`: Tự động giảm giá theo hạn

### 6.2. **Views - Khung nhìn dữ liệu**

- 6.2.1. `v_product_inventory_summary`: Tổng quan tồn kho
- 6.2.2. `v_expired_products`: Danh sách hàng hết hạn
- 6.2.3. `v_product_revenue`: Doanh thu theo sản phẩm
- 6.2.4. `v_supplier_performance`: Hiệu suất nhà cung cấp
- 6.2.5. `v_customer_purchase_history`: Lịch sử mua hàng
- 6.2.6. `v_low_stock_alert`: Cảnh báo hàng sắp hết

### 6.3. **Stored Procedures - Quy trình phức tạp**

- 6.3.1. `sp_replenish_shelf_stock`: Bổ sung hàng lên quầy (FIFO)
- 6.3.2. `sp_process_sale`: Xử lý giao dịch bán hàng
- 6.3.3. `sp_calculate_employee_salary`: Tính lương nhân viên
- 6.3.4. `sp_remove_expired_products`: Loại bỏ hàng hết hạn
- 6.3.5. `sp_generate_monthly_sales_report`: Báo cáo doanh thu tháng

---

## **PHẦN VII: QUERIES THỰC HIỆN YÊU CẦU ĐỀ TÀI**

### 7.1. **Queries quản lý cơ bản**

- 7.1.1. CRUD operations cho các đối tượng
- 7.1.2. Tìm kiếm và lọc đa điều kiện

### 7.2. **Queries theo dõi tồn kho**

- 7.2.1. Liệt kê hàng theo chủng loại/quầy hàng (sắp xếp theo số lượng)
- 7.2.2. Hàng sắp hết trên quầy nhưng còn trong kho
- 7.2.3. Hàng hết trong kho nhưng còn trên quầy
- 7.2.4. Sắp xếp theo tổng tồn kho (kho + quầy)

### 7.3. **Queries xử lý hạn sử dụng**

- 7.3.1. Tìm hàng quá hạn cần loại bỏ
- 7.3.2. Cập nhật giá theo quy tắc giảm giá (theo category)
- 7.3.3. Thống kê hàng sắp hết hạn (3 ngày, 5 ngày)

### 7.4. **Queries báo cáo thống kê**

- 7.4.1. Xếp hạng doanh thu sản phẩm theo tháng (RANK())
- 7.4.2. Xếp hạng nhà cung cấp theo doanh thu
- 7.4.3. Thống kê khách hàng thành viên và hóa đơn
- 7.4.4. Phân tích hiệu suất bán hàng theo ngày trong tuần
- 7.4.5. Báo cáo doanh thu hàng ngày (30 ngày gần nhất)

---

## **PHẦN VIII: DỮ LIỆU MẪU VÀ KIỂM THỬ**

### 8.1. **Kịch bản dữ liệu mẫu**

- 8.1.1. Dữ liệu 1 tháng hoạt động siêu thị
- 8.1.2. Các case đặc biệt để test:
  - Hàng sắp hết hạn
  - Quầy đầy/kho hết
  - Khách hàng nâng cấp membership
  - Nhân viên làm thêm giờ

### 8.2. **Kiểm thử các ràng buộc**

- 8.2.1. Test ràng buộc giá (selling_price > import_price)
- 8.2.2. Test ràng buộc số lượng (không âm, không vượt max)
- 8.2.3. Test ràng buộc phân loại (product category = shelf category)
- 8.2.4. Test ràng buộc unique (mã sản phẩm, mã nhân viên, v.v.)

### 8.3. **Kiểm thử triggers và procedures**

- 8.3.1. Kịch bản test cho từng trigger:
  - Test chuyển hàng kho → quầy
  - Test bán hàng trừ tồn
  - Test cảnh báo low stock
  - Test tự động giảm giá
- 8.3.2. Test cases cho procedures:
  - Test sp_process_sale với JSON input
  - Test sp_replenish_shelf_stock với FIFO
  - Test sp_calculate_employee_salary
- 8.3.3. Kết quả và xử lý lỗi (RAISE EXCEPTION)

---

## **PHẦN IX: ĐÁNH GIÁ VÀ KẾT LUẬN**

### 9.1. **Kết quả đạt được**

- 9.1.1. So sánh với yêu cầu đề tài (100% đáp ứng)
- 9.1.2. Điểm mạnh của thiết kế:
  - Database chuẩn BCNF
  - Triggers tự động hóa nghiệp vụ
  - Views tối ưu báo cáo
  - Procedures đóng gói logic phức tạp

### 9.2. **Hạn chế và cải tiến**

- 9.2.1. Những hạn chế hiện tại:
  - Chưa có partitioning cho bảng lớn
  - Chưa có backup/restore strategy
  - Chưa có user permission management
- 9.2.2. Hướng phát triển tương lai:
  - Tích hợp với hệ thống POS
  - Thêm module e-commerce
  - Analytics và BI dashboard

### 9.3. **Kết luận**
