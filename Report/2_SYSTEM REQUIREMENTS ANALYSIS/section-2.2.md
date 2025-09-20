# 2.2. XÁC ĐỊNH CÁC YÊU CẦU CHỨC NĂNG

## 2.2.1. Nhóm chức năng CRUD cơ bản

### 2.2.1.1. Quản lý sản phẩm
- **Thêm sản phẩm mới**: Nhập thông tin cơ bản về sản phẩm bao gồm mã sản phẩm, tên, danh mục, nhà cung cấp, đơn vị tính, giá nhập, giá bán, hạn sử dụng
- **Cập nhật thông tin sản phẩm**: Chỉnh sửa các thuộc tính của sản phẩm, đặc biệt là giá bán (với ràng buộc > giá nhập)
- **Xóa sản phẩm**: Đánh dấu sản phẩm không còn hoạt động (soft delete) thay vì xóa vật lý
- **Tìm kiếm sản phẩm**: Tìm kiếm theo mã, tên, danh mục, nhà cung cấp với khả năng lọc và sắp xếp

### 2.2.1.2. Quản lý khách hàng
- **Đăng ký khách hàng mới**: Tạo tài khoản thành viên với thông tin cá nhân, cấp thẻ membership
- **Cập nhật thông tin khách hàng**: Chỉnh sửa thông tin liên lạc, địa chỉ
- **Quản lý điểm tích lũy**: Tự động tích điểm theo doanh số mua hàng, quy đổi điểm thành tiền
- **Nâng cấp hạng thành viên**: Tự động nâng cấp dựa trên tổng chi tiêu thông qua trigger

### 2.2.1.3. Quản lý nhà cung cấp
- **Thêm nhà cung cấp**: Nhập thông tin về công ty, người liên hệ, thông tin thanh toán
- **Đánh giá hiệu suất nhà cung cấp**: Theo dõi chất lượng, thời gian giao hàng, doanh thu
- **Quản lý hợp đồng**: Lưu trữ điều khoản hợp đồng, giá cả thỏa thuận

### 2.2.1.4. Quản lý nhân viên
- **Thêm nhân viên mới**: Tạo hồ sơ nhân viên với thông tin cá nhân, vị trí công việc
- **Chấm công**: Ghi nhận giờ làm việc hàng ngày thông qua bảng `employee_work_hours`
- **Tính lương**: Sử dụng stored procedure `sp_calculate_employee_salary` để tính lương = lương cơ bản + lương theo giờ

## 2.2.2. Nhóm chức năng quản lý tồn kho

### 2.2.2.1. Quản lý nhập hàng
- **Tạo đơn nhập hàng**: Lập phiếu nhập với thông tin nhà cung cấp, danh sách sản phẩm, số lượng, giá nhập
- **Nhập hàng vào kho**: Cập nhật `warehouse_inventory` với batch_code, ngày nhập, hạn sử dụng
- **Kiểm tra chất lượng**: Xác nhận hàng hóa đạt chuẩn trước khi lưu kho

### 2.2.2.2. Chuyển hàng từ kho lên quầy
- **Kiểm tra capacity quầy**: Validate không vượt quá `max_quantity` trong `shelf_layout`
- **Chuyển hàng theo FIFO**: Ưu tiên hàng nhập trước, hết hạn sớm hơn thông qua `sp_replenish_shelf_stock`
- **Cập nhật inventory**: Trừ `warehouse_inventory`, cộng `shelf_inventory` thông qua trigger `tr_process_stock_transfer`
- **Ghi log chuyển hàng**: Lưu lại thông tin trong `stock_transfers` để audit

### 2.2.2.3. Kiểm soát tồn kho
- **Theo dõi tồn kho realtime**: Sử dụng view `v_product_inventory_summary` để xem tổng quan
- **Phân tích ABC**: Phân loại sản phẩm theo mức độ quan trọng dựa trên doanh thu
- **Dự báo nhu cầu**: Phân tích xu hướng tiêu thụ để lập kế hoạch nhập hàng

## 2.2.3. Nhóm chức năng cảnh báo và tự động hóa

### 2.2.3.1. Cảnh báo tồn kho thấp
- **Cảnh báo low stock**: Trigger `tr_check_low_stock` tự động thông báo khi `current_quantity <= low_stock_threshold`
- **Danh sách cần bổ sung**: View `v_low_stock_alert` hiển thị sản phẩm sắp hết trên quầy nhưng còn trong kho
- **Đề xuất bổ sung**: Gợi ý số lượng và thời điểm optimal để replenish

### 2.2.3.2. Xử lý hàng hết hạn
- **Tính ngày hết hạn**: Trigger `tr_calculate_expiry_date` tự động tính `expiry_date = import_date + shelf_life_days`
- **Giảm giá tự động**: Trigger `tr_apply_expiry_discounts` áp dụng discount rules theo category khi sắp hết hạn
- **Loại bỏ hàng hết hạn**: Stored procedure `sp_remove_expired_products` để xử lý hàng quá hạn

### 2.2.3.3. Tự động hóa business rules
- **Validate ràng buộc**: Các trigger validation đảm bảo business rules (giá bán > giá nhập, capacity, category consistency)
- **Tính toán tự động**: Auto-calculate subtotal, tax, points thông qua triggers
- **Nâng cấp membership**: Trigger `tr_check_membership_upgrade` tự động nâng cấp hạng khách hàng

## 2.2.4. Nhóm chức năng báo cáo thống kê

### 2.2.4.1. Báo cáo bán hàng
- **Doanh thu theo thời gian**: Báo cáo ngày/tháng/quý với khả năng drill-down
- **Top sản phẩm bán chạy**: Sử dụng RANK() function để xếp hạng theo quantity/revenue
- **Phân tích theo nhóm khách hàng**: Segmentation theo membership level, spending behavior
- **Báo cáo tháng**: Stored procedure `sp_generate_monthly_sales_report` tự động tạo báo cáo

### 2.2.4.2. Báo cáo tồn kho
- **Tình trạng tồn kho**: View `v_product_inventory_summary` với status classification
- **Hàng sắp hết hạn**: View `v_expired_products` với phân loại "Expired", "Expiring soon", "Valid"
- **Phân tích tồn kho**: 
  - Hàng sắp hết trên quầy nhưng còn trong kho
  - Hàng hết trong kho nhưng còn trên quầy
  - Sắp xếp theo tổng tồn kho (kho + quầy)

### 2.2.4.3. Báo cáo hiệu suất
- **Hiệu suất nhà cung cấp**: View `v_supplier_performance` với profit margin analysis
- **Lịch sử mua hàng khách hàng**: View `v_customer_purchase_history` với RFM analysis
- **Phân tích theo ngày trong tuần**: Query hiệu suất bán hàng theo từng ngày để optimize staffing

### 2.2.4.4. Dashboard và KPIs
- **Real-time metrics**: Doanh thu hôm nay, số giao dịch, khách hàng mới
- **Trend analysis**: So sánh với cùng kỳ năm trước, growth rate
- **Exception reporting**: Cảnh báo bất thường về doanh thu, tồn kho, expired products

## 2.2.5. Yêu cầu tích hợp và mở rộng

### 2.2.5.1. API và Web Services
- **REST API**: Cung cấp endpoints cho mobile app, third-party integrations
- **Authentication**: JWT-based security cho web và mobile access
- **Rate limiting**: Bảo vệ system khỏi abuse và overload

### 2.2.5.2. Scalability
- **Database partitioning**: Chia partition theo tháng cho sales_invoices
- **Caching**: Redis cache cho frequent queries (products, inventory)
- **Load balancing**: Distribute traffic across multiple app servers

### 2.2.5.3. Backup và Recovery
- **Automated backup**: Backup hàng ngày với retention policy
- **Point-in-time recovery**: Khả năng restore đến thời điểm cụ thể
- **Disaster recovery**: Failover plan và recovery procedures
