# PHẦN II: PHÂN TÍCH YÊU CẦU HỆ THỐNG

## 2.1. Phân tích nghiệp vụ

Để xây dựng một hệ thống quản lý siêu thị hiệu quả, việc đầu tiên là phải hiểu rõ các quy trình nghiệp vụ diễn ra hàng ngày trong môi trường siêu thị. Mỗi quy trình đều có những đặc thù riêng, đòi hỏi cơ sở dữ liệu phải được thiết kế để đáp ứng chính xác các yêu cầu này.

### 2.1.1. Quy trình quản lý hàng hóa

#### **a. Quy trình nhập hàng từ nhà cung cấp**

**Mô tả quy trình:**
1. **Tạo đơn đặt hàng (Purchase Order)**: Nhân viên quản lý kho tạo đơn đặt hàng với nhà cung cấp, xác định sản phẩm và số lượng cần nhập
2. **Nhận hàng và kiểm tra**: Khi hàng về, nhân viên kiểm tra số lượng, chất lượng và hạn sử dụng
3. **Nhập kho theo batch**: Mỗi lô hàng được gán mã batch riêng (batch_code) để theo dõi
4. **Cập nhật warehouse_inventory**: Hệ thống tự động:
   - Tạo record mới trong warehouse_inventory với batch_code, quantity, import_date
   - Tính toán expiry_date = import_date + shelf_life_days (nếu có)
   - Lưu import_price để tính toán lợi nhuận sau này

**Ràng buộc nghiệp vụ:**
- Mỗi batch phải có mã duy nhất (warehouse_id + product_id + batch_code)
- Giá nhập (import_price) phải > 0
- Với sản phẩm có hạn sử dụng: phải kiểm tra expiry_date > import_date
- Cập nhật trạng thái purchase_order từ 'PENDING' sang 'COMPLETED'

**Trigger hỗ trợ:**
- `tr_calculate_expiry_date`: Tự động tính hạn sử dụng nếu không được nhập
- `tr_update_purchase_order_total`: Cập nhật tổng giá trị đơn hàng

#### **b. Quy trình quản lý tồn kho**

**Mô tả quy trình:**
1. **Theo dõi hai cấp độ tồn kho**:
   - **Warehouse level**: Tổng số lượng trong kho (warehouse_inventory)
   - **Shelf level**: Số lượng trên quầy bày bán (shelf_inventory)

2. **Kiểm tra ngưỡng tồn kho**:
   - So sánh current_quantity với low_stock_threshold
   - Phát cảnh báo khi shelf_inventory.current_quantity ≤ products.low_stock_threshold

3. **Quản lý vị trí và sức chứa**:
   - Mỗi shelf có max_capacity giới hạn tổng số lượng hàng
   - Mỗi product trên shelf có max_quantity riêng (shelf_layout)
   - Position_code xác định vị trí cụ thể trên quầy

**Ràng buộc nghiệp vụ:**
- Tổng tồn kho = Σ(warehouse_inventory.quantity) + Σ(shelf_inventory.current_quantity)
- shelf_inventory.current_quantity ≤ shelf_layout.max_quantity
- Chỉ sản phẩm cùng category với shelf mới được phép bày bán

**Views hỗ trợ:**
- `v_product_inventory_summary`: Tổng hợp tồn kho warehouse + shelf
- `v_low_stock_alert`: Danh sách sản phẩm cần bổ sung

#### **c. Quy trình xử lý hàng hết hạn**

**Mô tả quy trình:**
1. **Kiểm tra định kỳ**: Hệ thống kiểm tra expiry_date hàng ngày
2. **Phân loại theo mức độ**:
   - **Expired** (expiry_date < CURRENT_DATE): Cần loại bỏ ngay
   - **Expiring soon** (expiry_date - CURRENT_DATE ≤ 3): Cần giảm giá
   - **Valid**: Bán bình thường

3. **Xử lý tự động**:
   - Áp dụng discount_rules theo category và days_before_expiry
   - Cập nhật selling_price = original_price × (1 - discount_percentage/100)
   - Đảm bảo giá sau giảm vẫn ≥ import_price × 1.1 (lãi tối thiểu 10%)

**Ràng buộc nghiệp vụ:**
- Mỗi category có discount_rules riêng (ví dụ: rau quả giảm 50% khi còn 3 ngày, bánh mì giảm 30% khi còn 5 ngày)
- Hàng hết hạn phải được remove khỏi cả warehouse và shelf
- Ghi nhận loss cho báo cáo

**Stored Procedure hỗ trợ:**
- `sp_remove_expired_products`: Loại bỏ hàng hết hạn
- Trigger `tr_apply_expiry_discounts`: Tự động áp dụng giảm giá

### 2.1.2. Quy trình chuyển hàng từ kho lên quầy

#### **a. Logic chuyển hàng FIFO (First In First Out)**

**Mô tả quy trình:**
1. **Nhận yêu cầu bổ sung**: Khi shelf_inventory.current_quantity ≤ low_stock_threshold
2. **Xác định batch để chuyển**:
   ```sql
   -- Chọn batch cũ nhất (FIFO)
   SELECT batch_code, quantity, expiry_date
   FROM warehouse_inventory
   WHERE product_id = ?
   ORDER BY import_date ASC, expiry_date ASC
   ```

3. **Kiểm tra điều kiện chuyển**:
   - Kiểm tra tồn kho: warehouse_quantity ≥ transfer_quantity
   - Kiểm tra sức chứa: (shelf_current + transfer_quantity) ≤ shelf_max_capacity
   - Kiểm tra category: product.category_id = shelf.category_id

4. **Thực hiện chuyển kho**:
   - Tạo record trong stock_transfers với transfer_code duy nhất
   - Trigger `tr_process_stock_transfer` tự động:
     - Giảm warehouse_inventory.quantity
     - Tăng shelf_inventory.current_quantity
   - Cập nhật last_restocked = CURRENT_TIMESTAMP

**Ràng buộc nghiệp vụ:**
- Một product phải được config trong shelf_layout trước khi chuyển
- Transfer_quantity không được vượt quá:
  - Số lượng available trong warehouse
  - Không gian còn lại trên shelf (max_quantity - current_quantity)
- Ưu tiên chuyển hàng có hạn sử dụng gần nhất

**Triggers kiểm soát:**
- `tr_validate_stock_transfer`: Kiểm tra điều kiện TRƯỚC khi chuyển
- `tr_process_stock_transfer`: Thực hiện chuyển kho
- `tr_validate_shelf_capacity`: Đảm bảo không vượt sức chứa

#### **b. Quản lý batch trên quầy**

**Mô tả quy trình:**
1. **Theo dõi nhiều batch trên cùng quầy**:
   - Một product có thể có nhiều batch với expiry_date khác nhau
   - Bảng shelf_batch_inventory lưu chi tiết từng batch

2. **Cập nhật thông tin tổng hợp**:
   ```sql
   shelf_inventory.current_quantity = SUM(shelf_batch_inventory.quantity)
   shelf_inventory.earliest_expiry_date = MIN(expiry_date)
   shelf_inventory.latest_expiry_date = MAX(expiry_date)
   ```

3. **Xử lý khi bán hàng**:
   - Ưu tiên bán batch có hạn sử dụng gần nhất
   - Tự động chuyển sang batch tiếp theo khi batch hiện tại hết

**Ràng buộc nghiệp vụ:**
- Tổng quantity các batch = shelf_inventory.current_quantity
- Batch có is_near_expiry = true được ưu tiên bán trước
- Giá bán có thể khác nhau theo batch (do discount)

**Stored Procedure hỗ trợ:**
- `sp_replenish_shelf_stock`: Xử lý toàn bộ logic chuyển hàng
  - Input: product_id, shelf_id, quantity, employee_id
  - Tự động chọn batch phù hợp (FIFO)
  - Tạo transfer record với đầy đủ thông tin
  - Raise exception nếu có lỗi

#### **c. Cảnh báo và monitoring**

**Hệ thống cảnh báo tự động:**
1. **Low stock alert**: Trigger `tr_check_low_stock` phát cảnh báo khi:
   - current_quantity ≤ low_stock_threshold
   - Có hàng trong kho để bổ sung

2. **Capacity warning**: Cảnh báo khi shelf gần đầy:
   - current_quantity > max_quantity × 0.9

3. **Expiry monitoring**: View `v_expired_products` theo dõi:
   - Sản phẩm expired cần loại bỏ
   - Sản phẩm expiring soon cần giảm giá
   - Thống kê theo category và supplier

**Dashboard metrics:**
- Tỷ lệ lấp đầy quầy: current_quantity / max_quantity × 100%
- Thời gian tồn kho trung bình
- Tần suất bổ sung hàng
- Giá trị hàng hết hạn phải hủy

Các quy trình này được thiết kế để hoạt động tự động tối đa thông qua triggers và procedures, giảm thiểu sai sót do thao tác thủ công và đảm bảo tính nhất quán của dữ liệu.