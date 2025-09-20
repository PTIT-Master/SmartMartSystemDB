### 2.1.3. Quy trình bán hàng

#### **a. Quy trình xử lý giao dịch bán hàng**

**Mô tả quy trình:**
1. **Khởi tạo giao dịch**:
   - Nhân viên tạo sales_invoice với invoice_no duy nhất (format: INV-YYYYMMDD-000001)
   - Xác định customer_id (NULL nếu khách vãng lai)
   - Chọn payment_method: CASH, CARD, TRANSFER, VOUCHER

2. **Thêm sản phẩm vào hóa đơn**:
   - Quét barcode hoặc nhập product_code
   - Hệ thống kiểm tra shelf_inventory.current_quantity
   - Nhập quantity và discount_percentage (nếu có)
   - Trigger `tr_calculate_detail_subtotal` tự động tính:
     ```sql
     discount_amount = unit_price × quantity × (discount_percentage/100)
     subtotal = (unit_price × quantity) - discount_amount
     ```

3. **Kiểm tra và trừ tồn kho**:
   - Trigger `tr_process_sales_stock_deduction` kiểm tra:
     - Đủ hàng trên quầy: shelf_inventory.current_quantity ≥ requested_quantity
     - Nếu không đủ → RAISE EXCEPTION với thông báo cụ thể
   - Tự động cập nhật: current_quantity = current_quantity - sold_quantity

4. **Tính toán tổng hóa đơn**:
   - Trigger `tr_calculate_invoice_totals` tự động:
     ```sql
     subtotal = SUM(sales_invoice_details.subtotal)
     tax_amount = subtotal × 0.10  -- VAT 10%
     total_amount = subtotal - discount_amount + tax_amount
     ```

5. **Xử lý điểm thành viên** (nếu có customer_id):
   - Trigger `tr_update_customer_metrics`:
     - Tính points_earned = FLOOR(total_amount × points_multiplier)
     - Cập nhật: total_spending += total_amount
     - Cập nhật: loyalty_points += points_earned - points_used
   - Trigger `tr_check_membership_upgrade` kiểm tra nâng cấp

**Ràng buộc nghiệp vụ:**
- Invoice_no phải UNIQUE
- Không thể bán số lượng > tồn kho trên quầy
- Unit_price lấy từ products.selling_price tại thời điểm bán
- Discount_percentage: 0-100%
- Points chỉ tính cho khách thành viên

**Stored Procedure hỗ trợ:**
```sql
sp_process_sale(
    p_customer_id BIGINT,
    p_employee_id BIGINT,
    p_payment_method VARCHAR,
    p_product_list JSON,  -- [{product_id, quantity, discount_percentage}]
    p_points_used BIGINT
)
```

#### **b. Quy trình hoàn trả và hủy đơn**

**Mô tả quy trình:**
1. **Xác định hóa đơn cần xử lý**: Tìm theo invoice_no
2. **Hoàn trả sản phẩm**:
   - Cập nhật lại shelf_inventory.current_quantity
   - Ghi nhận lý do hoàn trả
   - Tính lại điểm thành viên

3. **Hủy toàn bộ đơn**:
   - Rollback tất cả thay đổi về tồn kho
   - Hoàn điểm đã sử dụng
   - Cập nhật trạng thái hóa đơn

**Ràng buộc nghiệp vụ:**
- Chỉ hoàn trả trong vòng 7 ngày
- Sản phẩm phải còn nguyên vẹn
- Phải có hóa đơn gốc

#### **c. Báo cáo bán hàng**

**Các báo cáo quan trọng:**

1. **Doanh thu theo sản phẩm** (View `v_product_revenue`):
   - Tổng số lượng bán
   - Tổng doanh thu
   - Doanh thu trung bình/giao dịch
   - Group by tháng/quý/năm

2. **Hiệu suất bán hàng theo thời gian**:
   ```sql
   -- Query: Doanh thu theo ngày trong tuần
   SELECT 
       TO_CHAR(invoice_date, 'Day') AS day_of_week,
       COUNT(DISTINCT invoice_id) AS transactions,
       SUM(total_amount) AS revenue
   FROM sales_invoices
   GROUP BY TO_CHAR(invoice_date, 'Day'), EXTRACT(DOW FROM invoice_date)
   ORDER BY EXTRACT(DOW FROM invoice_date)
   ```

3. **Top sản phẩm bán chạy**:
   - Xếp hạng theo số lượng hoặc doanh thu
   - Sử dụng RANK() OVER (ORDER BY ...)

**Dashboard metrics:**
- Doanh thu hôm nay/tuần/tháng
- Số giao dịch và giá trị trung bình
- Top 10 sản phẩm bán chạy
- Tỷ lệ khách hàng thành viên

### 2.1.4. Quy trình quản lý nhân viên

#### **a. Quản lý thông tin và chức vụ**

**Cấu trúc tổ chức:**
1. **Positions (Chức vụ)**:
   - Manager: Quản lý toàn bộ siêu thị
   - Supervisor: Giám sát ca làm việc
   - Cashier: Thu ngân
   - Stock Clerk: Nhân viên kho
   - Sales Staff: Nhân viên bán hàng

2. **Thông tin nhân viên**:
   ```sql
   employees:
   - employee_code: Mã nhân viên (UNIQUE)
   - full_name, phone, email, address
   - position_id → positions
   - hire_date: Ngày bắt đầu làm việc
   - id_card: CMND/CCCD (UNIQUE)
   - bank_account: Tài khoản nhận lương
   - is_active: Trạng thái làm việc
   ```

**Ràng buộc nghiệp vụ:**
- Employee_code format: EMP-XXXXX
- Email và id_card phải UNIQUE
- Một position có thể có nhiều employees
- Không thể xóa employee có sales_invoices

#### **b. Quản lý giờ làm việc và chấm công**

**Quy trình chấm công:**
1. **Check-in/Check-out hàng ngày**:
   ```sql
   employee_work_hours:
   - work_date: Ngày làm việc
   - check_in_time: Giờ vào ca
   - check_out_time: Giờ tan ca
   - total_hours: Tự động tính bởi trigger
   ```

2. **Tính giờ làm việc**:
   - Trigger `tr_calculate_work_hours`:
     ```sql
     total_hours = EXTRACT(EPOCH FROM (check_out_time - check_in_time)) / 3600
     ```

3. **Kiểm soát chấm công**:
   - UNIQUE constraint: (employee_id, work_date)
   - Một nhân viên chỉ có 1 record/ngày
   - Validate: check_out_time > check_in_time

**Báo cáo giờ làm:**
- Tổng giờ làm trong tháng
- Giờ làm thêm (> 8h/ngày)
- Ngày nghỉ/vắng mặt

#### **c. Tính toán lương**

**Cấu trúc lương:**
1. **Thành phần lương** (từ bảng positions):
   - base_salary: Lương cơ bản cố định/tháng
   - hourly_rate: Lương theo giờ

2. **Công thức tính lương**:
   ```sql
   Tổng lương = base_salary + (total_hours × hourly_rate)
   ```

3. **Stored Procedure tính lương**:
   ```sql
   sp_calculate_employee_salary(
       p_employee_id BIGINT,
       p_month INTEGER,
       p_year INTEGER,
       OUT p_base_salary NUMERIC,
       OUT p_hourly_salary NUMERIC,
       OUT p_total_salary NUMERIC
   )
   ```

**Chi tiết procedure:**
- Lấy base_salary và hourly_rate từ positions
- Tính tổng giờ làm trong tháng từ employee_work_hours
- Tính hourly_salary = total_hours × hourly_rate
- Tổng lương = base_salary + hourly_salary

**Ví dụ tính lương:**
```
Position: Cashier
- Base salary: 5,000,000 VND
- Hourly rate: 30,000 VND/h
- Total hours in month: 180h
- Hourly salary: 180 × 30,000 = 5,400,000
- Total salary: 5,000,000 + 5,400,000 = 10,400,000 VND
```

#### **d. Đánh giá hiệu suất nhân viên**

**Các chỉ số đánh giá:**

1. **Hiệu suất bán hàng** (cho Sales Staff & Cashier):
   ```sql
   SELECT 
       e.employee_code,
       e.full_name,
       COUNT(si.invoice_id) AS total_transactions,
       SUM(si.total_amount) AS total_revenue,
       AVG(si.total_amount) AS avg_transaction_value
   FROM employees e
   JOIN sales_invoices si ON e.employee_id = si.employee_id
   WHERE EXTRACT(MONTH FROM si.invoice_date) = ?
   GROUP BY e.employee_id
   ORDER BY total_revenue DESC
   ```

2. **Hiệu suất quản lý kho** (cho Stock Clerk):
   - Số lần chuyển hàng kho→quầy
   - Thời gian xử lý trung bình
   - Số lỗi trong stock transfer

3. **Độ chuyên cần**:
   - Tỷ lệ ngày làm việc/tổng ngày
   - Số lần đi muộn (check_in_time > scheduled_time)
   - Tổng giờ làm thêm

**Dashboard nhân viên:**
- Top nhân viên theo doanh số
- Biểu đồ giờ làm việc
- Thống kê lương theo phòng ban
- Tỷ lệ nhân viên active/inactive

**Quyền hạn theo position:**
- Manager: Full access, có thể xem báo cáo tổng hợp
- Supervisor: Quản lý ca, chấm công, stock transfer
- Cashier: Chỉ tạo sales_invoices
- Stock Clerk: Chỉ xử lý warehouse, stock transfer
- Sales Staff: Hỗ trợ khách, không trực tiếp thu tiền

Các quy trình này đảm bảo việc quản lý nhân sự chặt chẽ, tính lương chính xác và đánh giá hiệu suất công bằng, đồng thời tạo động lực làm việc thông qua hệ thống lương thưởng rõ ràng.