## Supermarket DBMS Project — Requirements Compliance Checklist

This checklist maps each requirement from `Report/De_tai_10_He_CSDL_quan_ly_sieu_thi.md` to current implementation status across:
- Database schema, constraints, triggers, views, procedures (`Report/schema_only.sql`)
- Application routes/handlers/templates (`webapp/web/...`)

Legend:
- [x] Covered
- [~] Partially covered (needs refinement or UI wiring)
- [ ] Not covered yet

### A. Database Requirements
- [x] Nhân viên, hàng hóa, chủng loại, quầy, nhà cung cấp, kho, khách hàng (thành viên)
  - Tables: `employees`, `products`, `product_categories`, `display_shelves`, `suppliers`, `warehouse`, `warehouse_inventory`, `customers`, `membership_levels`
- [x] Nhân viên bán hàng/quản lý hàng hóa (quan hệ dữ liệu sẵn sàng)
  - `sales_invoices.employee_id`, activity logs, indexes
- [x] Hàng hóa trong kho và trên quầy; theo dõi batch, hạn dùng
  - `warehouse_inventory`, `shelf_inventory`, `shelf_batch_inventory`
- [x] Mỗi quầy trưng bày sản phẩm theo vị trí với giới hạn tối đa
  - `shelf_layout(position_code, max_quantity)`, constraints + triggers `validate_shelf_capacity`
- [x] Mỗi quầy chỉ cho cùng chủng loại
  - Trigger `validate_shelf_category_consistency` on `shelf_inventory` and `shelf_layout`
- [x] Giá bán > giá nhập
  - Constraint `check_price` and trigger `validate_product_price`
- [x] Lương theo vị trí: lương cơ bản + theo giờ; theo dõi giờ công
  - `positions(base_salary, hourly_rate)`, `employee_work_hours` + trigger `calculate_work_hours`
- [x] Dữ liệu ít nhất 1 tháng (hỗ trợ bằng seed/simulation)
  - Seeds/simulations in `webapp/database/*seed*.go`, `realistic_simulation.go`

### B. Application Requirements
- [~] CRUD các đối tượng chính với ràng buộc
  - Covered: `products`, `display_shelves`, `shelf_layout`, `customers`, `employees` (cả `work_hours` + `salary_summary`), `purchase_orders`, `sales`
    - Routes in `web/web/server.go`; handlers in `web/web/handlers/*.go`; templates under `web/web/templates/pages/...`
  - Pending admin UI: `membership_levels` (đã triển khai), `positions` (đã triển khai)
- [x] Bổ sung hàng từ kho lên quầy, không vượt quá tồn kho/quy hoạch quầy, FIFO theo lô
  - Procedure `transfer_stock_to_shelf`, triggers `validate_stock_transfer`, `process_stock_transfer`
  - UI: `inventory/transfer.html`
- [x] Cảnh báo thiếu hàng khi dưới ngưỡng, có còn trong kho
  - Trigger `check_low_stock`, view `v_low_shelf_products`, page `inventory/low_stock.html`
- [x] Thanh toán cập nhật tồn quầy; không vượt số lượng trên quầy
  - Trigger `process_sales_stock_deduction`; procedure `process_sale_payment`
  - Sales pages present; totals triggers in `calculate_invoice_totals`
- [x] Liệt kê theo chủng loại/quầy, sắp xếp tăng dần số lượng còn trên quầy
  - Inventory pages support filters + sort by quantity (`Inventory.ShelfInventory`, `Inventory.WarehouseInventory`)
  - APIs: `/api/categories/:id/products`, `/api/shelves/:id/products`
- [~] Sắp xếp theo số lượng được mua trong ngày
  - Available data in `sales_invoice_details` joined by `DATE(invoice_date)=CURRENT_DATE`.
  - To add: sort option in listing endpoints/pages (today’s sold count)
- [x] Liệt kê sắp hết trên quầy nhưng còn trong kho
  - View: `v_low_shelf_products`; page exists
- [x] Liệt kê hết hàng trong kho nhưng còn trên quầy
  - View: `v_warehouse_empty_products`; page exists
- [x] Liệt kê toàn bộ hàng hóa, sắp xếp theo tổng tồn (quầy+kho)
  - View: `v_product_overview` (có tổng tồn). UI có thể thêm sort rõ ràng nếu cần
- [x] Xếp hạng doanh thu theo tháng cụ thể
  - Pages `reports/sales.html`, `reports/products.html` hỗ trợ `date_from/date_to` và group theo `day|week|month`
  - DB: `v_product_revenue`, function `get_revenue_report(start,end)`
- [x] Tìm hàng hóa quá hạn, gần hết hạn; loại khỏi danh sách còn hạn
  - View `v_expiring_products`; triggers `log_expiry_alert`
- [x] Cập nhật giá khi gần hạn theo quy tắc theo loại hàng
  - `discount_rules`, procedure `update_expiry_discounts`, function `calculate_discount_price`
- [x] Hiển thị khách hàng thành viên, hóa đơn và điểm/thăng hạng
  - View `v_vip_customers`; triggers `update_customer_metrics`, `check_membership_upgrade`
- [x] Thống kê doanh thu sản phẩm, xếp hạng theo doanh số
  - View `v_product_revenue`, function `get_best_selling_products`, reports pages
- [x] Thống kê doanh thu nhà cung cấp, xếp hạng
  - View `v_supplier_revenue`; report pages exist
- [x] Các ràng buộc số lượng thể hiện trong CSDL và áp vào ứng dụng
  - Triggers/constraints across transfers, shelf capacity, pricing, quantities

### C. Reports/Pages present in app
- Inventory: `inventory/overview.html`, `low_stock.html`, `expired.html`, `warehouse.html`, `shelf.html`, `transfer.html`
- Products: `list.html`, `view.html`, `form.html`, shelf-related pages
- Sales: `list.html`, `form.html`, `invoice.html`, `view.html`
- Purchase Orders: `list.html`, `form.html`, `edit.html`, `view.html`
- Customers: `list.html`, `view.html`, `form.html`
- Employees: `list.html`, `view.html`, `form.html`, `work_hours_*`, `salary_summary.html`
- Reports: `reports/overview.html`, `sales.html`, `products.html`, `suppliers.html`, `revenue.html`

Route-to-template confirmation:
- `/inventory`: `inventory/overview.html`
- `/inventory/warehouse`: `inventory/warehouse.html`
- `/inventory/shelf`: `inventory/shelf.html`
- `/inventory/transfer`: `inventory/transfer.html`
- `/inventory/low-stock`: `inventory/low_stock.html`
- `/inventory/expired`: `inventory/expired.html`
- `/inventory/discount-rules`: `inventory/discount_rules.html`
- `/purchase-orders/*`: `purchase_orders/{list,form,edit,view}.html`
- `/products/*`: `products/{list,form,view}.html` and `products/shelf_*` for shelves/layouts
- `/customers/*`: `customers/{list,form,view}.html`
- `/employees/*`: `employees/{list,form,view}.html`, `employees/work_hours_*`, `employees/salary_summary.html`
- `/sales/*`: `sales/{list,form,invoice,view}.html`
- `/reports/*`: `reports/{overview,sales,products,suppliers,revenue}.html`

### D. Gaps and Suggested Next Actions
1) Complete CRUD coverage and UI for remaining entities
   - [x] `warehouse` management pages (entity CRUD)
   - [x] `positions` admin pages (list/create/edit/delete)
   - [x] `membership_levels` admin pages (list/create/edit/delete)
2) Sorting/filters endpoints
   - [x] Add sort by “sold today” to shelf listing
   - [x] Ensure explicit UI sort by total stock (warehouse + shelf) on product list
3) Monthly revenue ranking
   - [x] Add quick month picker + ranking section to `reports/products.html`
   - [ ] Optional: add `v_product_revenue_monthly` for performance
4) Salary calculation report
   - [x] `employees/salary_summary.html` exists; query combines `positions` + `employee_work_hours`
5) Operational jobs
   - [x] Provide UI/API trigger: `POST /inventory/apply-discount` applies `discount_rules`
   - [ ] Optional: background schedule or admin button to run daily

### F. Implementation Tasks Tracker
- [x] Build `warehouse` CRUD: list/form/view/edit/delete + routes and templates
  - Routes: `/warehouses/*`; Tables: `warehouse`
- [x] Build `positions` admin CRUD: list/form/view/edit/delete
  - Routes: `/positions/*`; Tables: `positions`
- [x] Build `membership_levels` admin CRUD: list/form/view/edit/delete
  - Routes: `/membership-levels/*`; Tables: `membership_levels`
- [x] Add “sold today” sorting option
  - Update handlers: category/shelf product listings; join `sales_invoice_details` with `DATE(invoice_date)=CURRENT_DATE`
- [x] Add explicit sort-by-total-stock in product list UI
  - Use `v_product_overview` totals; add UI control and ORDER BY
- [x] Add month picker + ranking section to `reports/products.html`
  - Group by month; show top N by revenue and by units
- [ ] Optional: add daily scheduler or admin button to call `update_expiry_discounts()`
  - Wire to `/inventory/apply-discount` or a new admin endpoint

### E. Tracking
Use this file to tick off items as implemented. For each item, reference the handler/view and SQL object added or updated.


