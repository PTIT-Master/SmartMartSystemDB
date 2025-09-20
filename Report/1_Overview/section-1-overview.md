# PHẦN I: TỔNG QUAN

## 1.1. Giới thiệu đề tài

Trong bối cảnh nền kinh tế phát triển và nhu cầu mua sắm ngày càng tăng cao, các siêu thị bán lẻ đóng vai trò quan trọng trong việc cung cấp hàng hóa thiết yếu cho người tiêu dùng. Việc quản lý hiệu quả một siêu thị với hàng nghìn sản phẩm, nhiều nhà cung cấp, và lượng lớn giao dịch hàng ngày đòi hỏi một hệ thống quản lý cơ sở dữ liệu chặt chẽ và toàn diện.

Đề tài "Xây dựng Hệ Cơ sở dữ liệu quản lý siêu thị bán lẻ" tập trung vào việc thiết kế và triển khai một hệ thống cơ sở dữ liệu có khả năng:

- Quản lý toàn diện thông tin hàng hóa từ kho đến quầy bán
- Tự động hóa các quy trình nghiệp vụ quan trọng
- Theo dõi và cảnh báo tình trạng tồn kho
- Xử lý thông minh việc giảm giá theo hạn sử dụng
- Quản lý hiệu quả nhân viên và khách hàng thành viên
- Cung cấp báo cáo thống kê hỗ trợ ra quyết định

Hệ thống được xây dựng trên nền tảng PostgreSQL với việc tận dụng tối đa các tính năng nâng cao như triggers, views, stored procedures để đảm bảo tính toàn vẹn dữ liệu và tự động hóa các nghiệp vụ phức tạp.

## 1.2. Mục tiêu hệ thống

### 1.2.1. Mục tiêu tổng quát

Xây dựng một hệ thống cơ sở dữ liệu hoàn chỉnh, đáp ứng toàn bộ nhu cầu quản lý vận hành của một siêu thị bán lẻ quy mô vừa và nhỏ, từ khâu nhập hàng, lưu kho, trưng bày, bán hàng đến quản lý nhân sự và khách hàng.

### 1.2.2. Mục tiêu cụ thể

**Về quản lý hàng hóa:**

- Theo dõi chính xác số lượng hàng hóa tại kho và trên quầy bán
- Tự động cảnh báo khi hàng hóa sắp hết hoặc dưới ngưỡng an toàn
- Quản lý hạn sử dụng và tự động áp dụng chính sách giảm giá
- Kiểm soát việc chuyển hàng từ kho lên quầy theo nguyên tắc FIFO

**Về quản lý bán hàng:**

- Xử lý giao dịch bán hàng nhanh chóng và chính xác
- Tự động cập nhật tồn kho sau mỗi giao dịch
- Tính toán và cập nhật điểm thưởng cho khách hàng thành viên
- Hỗ trợ nhiều phương thức thanh toán

**Về quản lý nhân sự:**

- Quản lý thông tin nhân viên và chức vụ
- Tính toán lương dựa trên lương cơ bản và giờ làm việc
- Theo dõi hiệu suất làm việc của nhân viên

**Về báo cáo và phân tích:**

- Cung cấp báo cáo doanh thu theo sản phẩm, thời gian
- Xếp hạng nhà cung cấp dựa trên hiệu suất
- Phân tích hành vi mua hàng của khách hàng
- Dự báo nhu cầu bổ sung hàng hóa

## 1.3. Phạm vi và giới hạn

### 1.3.1. Phạm vi của hệ thống

**Các chức năng được triển khai:**

1. **Quản lý thông tin cơ bản**: Đầy đủ chức năng CRUD cho tất cả đối tượng (sản phẩm, nhân viên, khách hàng, nhà cung cấp)
2. **Quản lý kho và quầy hàng**:
   - Theo dõi tồn kho theo batch và lô hàng
   - Quản lý vị trí và sức chứa của từng quầy hàng
   - Tự động hóa việc chuyển hàng kho-quầy
3. **Xử lý giao dịch**:
   - Bán hàng và xuất hóa đơn
   - Nhập hàng từ nhà cung cấp
   - Chuyển kho nội bộ
4. **Quản lý hạn sử dụng**:
   - Tự động tính hạn sử dụng dựa trên shelf_life_days
   - Áp dụng giảm giá theo quy tắc từng loại sản phẩm
   - Loại bỏ sản phẩm hết hạn
5. **Hệ thống thành viên**:
   - Quản lý cấp độ thành viên
   - Tích điểm và quy đổi điểm
   - Tự động nâng cấp membership
6. **Báo cáo thống kê**:
   - Doanh thu theo nhiều chiều
   - Cảnh báo tồn kho
   - Hiệu suất nhà cung cấp

**Dữ liệu mẫu**: Hệ thống được cung cấp dữ liệu mẫu cho 1 tháng hoạt động, đủ để kiểm thử và minh họa các chức năng.

### 1.3.2. Giới hạn của hệ thống

**Các chức năng chưa triển khai:**

1. **Bảo mật và phân quyền**: Hệ thống chưa có module quản lý user và phân quyền truy cập
2. **Tích hợp thanh toán điện tử**: Chưa kết nối với cổng thanh toán online hoặc POS
3. **Kế toán chi tiết**: Chỉ tập trung vào doanh thu, chưa có module kế toán đầy đủ
4. **Multi-branch**: Thiết kế cho một siêu thị đơn lẻ, chưa hỗ trợ chuỗi siêu thị
5. **E-commerce**: Không có module bán hàng online
6. **Backup/Recovery**: Chưa có chiến lược sao lưu và phục hồi dữ liệu tự động

**Giả định và ràng buộc:**

- Mỗi quầy hàng chỉ bày bán sản phẩm cùng chủng loại
- Giá bán luôn phải lớn hơn giá nhập
- Một sản phẩm có thể có nhiều batch với hạn sử dụng khác nhau
- Warehouse_id mặc định = 1 (một kho duy nhất)
- Thuế VAT cố định 10%

## 1.4. Cấu trúc báo cáo

Báo cáo được tổ chức thành 9 phần chính và 4 phụ lục, tuân theo quy trình phát triển cơ sở dữ liệu chuẩn từ phân tích yêu cầu đến triển khai và kiểm thử:

**Phần II - Phân tích yêu cầu hệ thống**: Trình bày chi tiết các yêu cầu nghiệp vụ, yêu cầu chức năng và các ràng buộc quan trọng của siêu thị bán lẻ.

**Phần III - Mô hình dữ liệu khái niệm (ERD)**: Xác định và mô tả các thực thể, thuộc tính và mối quan hệ thông qua sơ đồ Entity-Relationship.

**Phần IV - Mô hình quan hệ**: Chuyển đổi ERD sang lược đồ quan hệ, thực hiện chuẩn hóa đến BCNF để loại bỏ dư thừa và bất thường dữ liệu.

**Phần V - Triển khai cơ sở dữ liệu vật lý**: Định nghĩa chi tiết cấu trúc bảng, kiểu dữ liệu, ràng buộc và index trong PostgreSQL.

**Phần VI - Xử lý logic nghiệp vụ bằng database**: Trình bày 20+ triggers, 6 views và 5 stored procedures đã được triển khai để tự động hóa và tối ưu hóa các nghiệp vụ.

**Phần VII - Queries thực hiện yêu cầu đề tài**: Tập hợp các câu truy vấn SQL đáp ứng 100% yêu cầu chức năng của đề tài.

**Phần VIII - Dữ liệu mẫu và kiểm thử**: Mô tả kịch bản kiểm thử và kết quả test các chức năng quan trọng.

**Phần IX - Đánh giá và kết luận**: Tổng kết kết quả đạt được, hạn chế và hướng phát triển.

**Phụ lục**: Cung cấp mã nguồn SQL hoàn chỉnh, từ điển dữ liệu và hướng dẫn sử dụng.

Cấu trúc này đảm bảo tính logic, khoa học và dễ theo dõi, phù hợp với yêu cầu của một báo cáo học thuật về cơ sở dữ liệu.
