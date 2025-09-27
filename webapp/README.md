# Hệ thống quản lý siêu thị - Web Application

## 📋 Giới thiệu

Ứng dụng web quản lý siêu thị được xây dựng với Go Fiber và HTML templates, tập trung vào database operations với VIEWs và stored procedures cho môn học Cơ sở dữ liệu.

## 🚀 Tính năng chính

- **SQL Debug Panel**: Hiển thị tất cả câu lệnh SQL được thực thi
- **Quản lý sản phẩm**: CRUD operations sử dụng raw SQL và VIEWs
- **Quản lý kho hàng**: Theo dõi hàng hóa trong kho và trên quầy
- **Cảnh báo tự động**: Sản phẩm sắp hết hàng, sản phẩm sắp hết hạn
- **Báo cáo thống kê**: Sử dụng VIEWs và stored procedures

## 🛠️ Công nghệ sử dụng

- **Backend**: Go 1.24+
- **Web Framework**: Fiber v2
- **Template Engine**: HTML/Template
- **Database**: PostgreSQL 16+
- **ORM**: GORM (với raw SQL queries)

## 📦 Cài đặt

### Yêu cầu hệ thống
- Go 1.24 hoặc cao hơn
- PostgreSQL 16 hoặc cao hơn
- Git

### Các bước cài đặt

1. **Clone repository**
```bash
git clone <repository-url>
cd webapp
```

2. **Cấu hình database**
```bash
# Copy file cấu hình mẫu
copy env.example .env

# Chỉnh sửa .env với thông tin database của bạn
notepad .env
```

3. **Cài đặt dependencies**
```bash
go mod download
```

4. **Chạy migration và seed data**
```bash
# Chạy migration để tạo tables, views, procedures
go run main.go -migrate

# Seed dữ liệu mẫu
go run main.go -seed

# Hoặc chạy cả hai
go run main.go -migrate -seed
```

5. **Khởi động server**
```bash
go run main.go
```

Server sẽ chạy tại: http://localhost:8080

## 📝 Sử dụng

### SQL Debug Panel
- Panel ở trên cùng hiển thị tất cả SQL queries đã thực thi
- Click "Toggle" để thu gọn/mở rộng
- Click "Clear" để xóa logs
- Auto-refresh mỗi 2 giây

### Quản lý sản phẩm
1. Truy cập menu "Sản phẩm"
2. Thêm/Sửa/Xóa sản phẩm
3. Xem chi tiết với thông tin tồn kho
4. Lưu ý: Giá bán phải > giá nhập (constraint)

### Database Views (được tạo tự động)
- `v_product_overview`: Tổng quan sản phẩm
- `v_low_stock_products`: Sản phẩm sắp hết hàng (tổng kho + kệ < threshold)
- `v_low_shelf_products`: Sản phẩm cần bổ sung lên kệ (kệ < threshold, còn kho)
- `v_warehouse_empty_products`: Sản phẩm hết kho nhưng còn trên quầy (cần nhập thêm)
- `v_expiring_products`: Sản phẩm sắp hết hạn
- `v_product_revenue`: Doanh thu theo sản phẩm
- `v_supplier_revenue`: Doanh thu theo nhà cung cấp
- `v_vip_customers`: Khách hàng VIP
- `v_shelf_status`: Tình trạng quầy hàng

### Stored Procedures (được tạo tự động)
- `transfer_stock_to_shelf()`: Chuyển hàng từ kho lên quầy
- `calculate_invoice_total()`: Tính tổng hóa đơn với giảm giá
- `process_sale_payment()`: Xử lý thanh toán và cập nhật inventory
- `update_expiry_discounts()`: Cập nhật giảm giá cho hàng sắp hết hạn
- `get_revenue_report()`: Báo cáo doanh thu theo thời gian
- `check_restock_alerts()`: Kiểm tra cảnh báo bổ sung hàng

## 🔧 Makefile Commands

```bash
# Windows (sử dụng make.bat)
make.bat build      # Build ứng dụng
make.bat run        # Chạy server
make.bat migrate    # Chạy migration
make.bat seed       # Seed dữ liệu
make.bat clean      # Xóa build files

# Linux/Mac
make build
make run
make migrate
make seed
make clean
```

## 📚 Cấu trúc project

```
webapp/
├── web/                    # Web application
│   ├── handlers/          # Route handlers
│   ├── middleware/        # Middleware (SQL logger)
│   └── templates/         # HTML templates
│       ├── layouts/       # Base layout với SQL debug panel
│       └── pages/         # Page templates
├── database/              # Database layer
│   ├── connection.go      # Database connection
│   ├── migration.go       # Migration logic
│   ├── query_logger.go    # SQL query logger
│   └── views_procedures.sql # VIEWs và Stored Procedures
├── models/                # GORM models
├── config/               # Configuration
└── main.go              # Entry point
```

## 🎯 Đặc điểm cho môn học Database

1. **Raw SQL Queries**: Sử dụng raw SQL thay vì ORM methods
2. **Database VIEWs**: Tận dụng VIEWs cho các queries phức tạp
3. **Stored Procedures**: Business logic trong database
4. **SQL Debug Panel**: Xem real-time SQL execution
5. **Constraints**: Check constraints, foreign keys được implement đầy đủ
6. **Triggers**: Tự động update inventory, validate data

## 🐛 Troubleshooting

### Lỗi kết nối database
- Kiểm tra PostgreSQL đang chạy
- Kiểm tra thông tin trong file .env
- Đảm bảo schema `supermarket` tồn tại

### Lỗi migration
- Xóa schema và tạo lại: `DROP SCHEMA supermarket CASCADE;`
- Chạy lại migration: `go run main.go -migrate`

### Lỗi template
- Đảm bảo đang ở thư mục webapp khi chạy
- Templates phải có đuôi .html

## 📄 License

MIT