# 10.1. QUÁ TRÌNH CÀI ĐẶT CƠ SỞ DỮ LIỆU

## 10.1.1. Yêu cầu hệ thống

### Phần mềm cần thiết
- **PostgreSQL 12+** hoặc tương đương (khuyến nghị PostgreSQL 15)
- **Go 1.19+** (cho ứng dụng web backend)
- **Git** (để clone source code)

### Yêu cầu phần cứng
- **RAM**: Tối thiểu 4GB (khuyến nghị 8GB)
- **Disk space**: Tối thiểu 10GB trống
- **CPU**: Dual-core trở lên
- **OS**: Windows 10/11, macOS, hoặc Linux

### Yêu cầu mạng
- Kết nối internet để tải dependencies
- Port 5432 (PostgreSQL) và 8080 (Web app) cần mở

## 10.1.2. Các bước cài đặt chi tiết

### Bước 1: Cài đặt PostgreSQL và tạo database

```bash
# Trên Windows (sử dụng Chocolatey)
choco install postgresql

# Trên macOS (sử dụng Homebrew)
brew install postgresql
brew services start postgresql

# Trên Ubuntu/Debian
sudo apt update
sudo apt install postgresql postgresql-contrib

# Khởi động PostgreSQL
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

**Tạo database và user:**

```sql
-- Đăng nhập vào PostgreSQL
sudo -u postgres psql

-- Tạo database
CREATE DATABASE supermarket;

-- Tạo user (tùy chọn)
CREATE USER supermarket_user WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE supermarket TO supermarket_user;

-- Thoát
\q
```

### Bước 2: Cấu hình environment variables

Tạo file `.env` trong thư mục `webapp/`:

```env
# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=supermarket
DB_SSLMODE=disable

# Application Configuration
APP_PORT=8080
APP_ENV=development
LOG_LEVEL=debug

# Simulation Configuration
SIMULATION_START_DATE=2025-09-01
SIMULATION_END_DATE=2025-09-24
SIMULATION_ENABLE_QUERY_LOG=true
```

### Bước 3: Chạy migration scripts

```bash
# Di chuyển vào thư mục webapp
cd webapp

# Tải dependencies
make deps

# Chạy migration để tạo bảng
make migrate

# Hoặc chạy trực tiếp
go run ./cmd/migrate
```

**Kết quả mong đợi:**
- Tạo thành công tất cả các bảng
- Tạo indexes và constraints
- Không có lỗi trong quá trình migration

### Bước 4: Tạo triggers và stored procedures

```bash
# Chạy script tạo triggers
go run ./cmd/migrate -triggers

# Kiểm tra triggers đã được tạo
psql -d supermarket -c "\df"  # List functions
psql -d supermarket -c "\dt"  # List tables
```

**Các triggers chính được tạo:**
- `tr_process_sales_stock_deduction`
- `tr_process_stock_transfer`
- `tr_calculate_invoice_totals`
- `tr_validate_shelf_capacity`
- `tr_apply_expiry_discounts`

### Bước 5: Khởi tạo dữ liệu mẫu

```bash
# Chạy seed data cơ bản
make seed

# Hoặc chạy trực tiếp
go run ./cmd/seed

# Force re-seed (xóa dữ liệu cũ và tạo mới)
make seed-force
```

**Dữ liệu được tạo:**
- Master data: categories, suppliers, positions, membership levels
- Basic entities: products, employees, customers, warehouses, shelves
- Sample transactions: purchase orders, stock transfers

### Bước 6: Chạy simulation để tạo dữ liệu hoạt động

```bash
# Chạy simulation cơ bản (2025-09-01 đến 2025-09-24)
make simulate

# Chạy simulation đầy đủ với xóa dữ liệu cũ
make simulate-full

# Hoặc chạy trực tiếp
go run ./cmd/simulate
```

**Simulation tạo ra:**
- Dữ liệu hoạt động 1 tháng (24 ngày)
- Sales transactions với hóa đơn chi tiết
- Stock movements và transfers
- Employee work hours
- Customer purchase history

### Bước 7: Kiểm tra kết nối và hoạt động

```bash
# Test kết nối database
make test-connection

# Chạy ứng dụng web
make run

# Hoặc chạy với auto-reload (development)
make dev
```

**Kiểm tra endpoints:**
- http://localhost:8080 - Homepage
- http://localhost:8080/inventory - Quản lý tồn kho
- http://localhost:8080/reports - Báo cáo thống kê

## 10.1.3. Cấu hình database

### Database connection settings

File `config/config.go` chứa cấu hình kết nối:

```go
type Config struct {
    Database struct {
        Host     string `env:"DB_HOST" envDefault:"localhost"`
        Port     int    `env:"DB_PORT" envDefault:"5432"`
        User     string `env:"DB_USER" envDefault:"postgres"`
        Password string `env:"DB_PASSWORD" envDefault:"postgres"`
        Name     string `env:"DB_NAME" envDefault:"supermarket"`
        SSLMode  string `env:"DB_SSLMODE" envDefault:"disable"`
    }
    App struct {
        Port string `env:"APP_PORT" envDefault:"8080"`
        Env  string `env:"APP_ENV" envDefault:"development"`
    }
}
```

### User permissions và security

```sql
-- Tạo role cho ứng dụng
CREATE ROLE supermarket_app;
GRANT CONNECT ON DATABASE supermarket TO supermarket_app;
GRANT USAGE ON SCHEMA public TO supermarket_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO supermarket_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO supermarket_app;

-- Tạo user cho ứng dụng
CREATE USER app_user WITH PASSWORD 'secure_password';
GRANT supermarket_app TO app_user;
```

### Backup và maintenance procedures

**Script backup hàng ngày:**

```bash
#!/bin/bash
# backup_daily.sh
DATE=$(date +%Y%m%d_%H%M%S)
pg_dump -h localhost -U postgres supermarket > "backup_supermarket_$DATE.sql"
```

**Script maintenance:**

```bash
#!/bin/bash
# maintenance.sh
psql -d supermarket -c "VACUUM ANALYZE;"
psql -d supermarket -c "REINDEX DATABASE supermarket;"
```

## 10.1.4. Troubleshooting

### Lỗi thường gặp và cách khắc phục

**1. Lỗi kết nối database:**
```
Error: failed to connect to database
```
- Kiểm tra PostgreSQL đang chạy: `pg_ctl status`
- Kiểm tra port 5432: `netstat -an | grep 5432`
- Kiểm tra file `.env` có đúng thông tin kết nối

**2. Lỗi migration:**
```
Error: relation already exists
```
- Chạy: `make migrate-drop` để xóa bảng cũ
- Hoặc: `make reset` để reset toàn bộ

**3. Lỗi seed data:**
```
Error: duplicate key value violates unique constraint
```
- Chạy: `make seed-force` để force re-seed
- Kiểm tra dữ liệu cũ chưa được xóa

**4. Lỗi simulation:**
```
Error: foreign key constraint fails
```
- Đảm bảo đã chạy seed data trước
- Kiểm tra dữ liệu master (suppliers, categories) đã có

### Log files và monitoring

**Xem logs:**
```bash
# Logs ứng dụng
tail -f logs/app.log

# Logs database
tail -f /var/log/postgresql/postgresql-15-main.log

# Logs simulation
tail -f seed_log.txt
```

**Monitoring commands:**
```bash
# Kiểm tra kết nối database
psql -d supermarket -c "SELECT count(*) FROM information_schema.tables;"

# Kiểm tra dữ liệu
psql -d supermarket -c "SELECT count(*) FROM products;"
psql -d supermarket -c "SELECT count(*) FROM sales_invoices;"
```

## 10.1.5. Kết luận

Quá trình cài đặt đã được thiết kế để đơn giản hóa việc triển khai hệ thống quản lý siêu thị. Với các lệnh Makefile được chuẩn bị sẵn, người dùng có thể:

1. **Setup nhanh**: Chỉ cần `make setup` để có hệ thống hoàn chỉnh
2. **Reset dễ dàng**: `make reset` để bắt đầu lại từ đầu
3. **Simulation đầy đủ**: `make simulate-full` để có dữ liệu test thực tế
4. **Development thuận tiện**: `make dev` cho auto-reload

Hệ thống đã được test trên các môi trường Windows, macOS và Linux với PostgreSQL 12-15.
