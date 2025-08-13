# DBML Generator

Hệ thống tự động tạo file DBML (Database Markup Language) từ SQL schema PostgreSQL.

## 📋 Tổng quan

DBML Generator là công cụ Python cho phép bạn:

- Parse file SQL schema PostgreSQL
- Tạo file DBML tương ứng
- Tự động phát hiện relationships giữa các bảng
- Tạo table groups để tổ chức ERD
- Export sang JSON schema

## 🛠️ Yêu cầu

- Python 3.6+
- File SQL schema PostgreSQL

## 📁 Cấu trúc

```
DBML/
├── generate_dbml.py     # Script chính
├── sql_parser.py        # Module parse SQL
├── dbml_generator.py    # Module tạo DBML
└── output/              # Thư mục chứa file đầu ra
```

## 🚀 Cách sử dụng

### 1. Sử dụng cơ bản

```bash
cd DBML
python generate_dbml.py
```

Mặc định sẽ:

- Đọc file `../sql/01_schema.sql`
- Tạo output trong thư mục `./output`

### 2. Tùy chỉnh đường dẫn

```bash
python generate_dbml.py [sql_file] [output_dir]
```

**Ví dụ:**

```bash
python generate_dbml.py ../sql/01_schema.sql ./my_output
python generate_dbml.py /path/to/schema.sql /path/to/output
```

### 3. Chạy từ thư mục khác

```bash
cd /your/project
python DBML/generate_dbml.py sql/schema.sql output/
```

## 📄 File đầu ra

Sau khi chạy thành công, bạn sẽ có:

### 1. `supermarket.dbml` - DBML cơ bản

```dbml
Project "Supermarket Database" {
  database_type: "PostgreSQL"
  Note: "Hệ thống quản lý siêu thị bán lẻ"
}

Table products {
  product_id int [pk]
  product_name varchar(255)
  category_id int // FK -> product_categories.category_id
  ...
}

// Relationships
Ref: products.category_id > product_categories.category_id
```

### 2. `supermarket_full.dbml` - DBML với table groups

Bao gồm tất cả từ file cơ bản + table groups:

```dbml
// Table Groups
TableGroup "Product Management" {
  product_categories
  suppliers
  products
  discount_rules
}
```

### 3. `parsed_schema.json` - Schema dưới dạng JSON

```json
{
  "tables": {
    "products": {
      "name": "products",
      "columns": [...],
      "foreign_keys": [...]
    }
  },
  "relationships": [...]
}
```

## 🌐 Sử dụng với dbdiagram.io

1. Mở [dbdiagram.io](https://dbdiagram.io/)
2. Tạo diagram mới
3. Upload file `.dbml` đã tạo
4. Hoặc copy-paste nội dung file vào editor

## ⚙️ Tùy chỉnh

### Thêm table notes mới

Edit file `dbml_generator.py`, tìm method `_get_table_note()`:

```python
def _get_table_note(self, table_name: str) -> str:
    table_notes = {
        'your_table': 'Mô tả bảng của bạn',
        # ...
    }
    return table_notes.get(table_name, '')
```

### Thêm relationships thủ công

Edit method `_get_manual_relationships()` trong `dbml_generator.py`:

```python
def _get_manual_relationships(self) -> list:
    relationships = [
        {
            "from_table": "table1", 
            "from_column": "column1",
            "to_table": "table2", 
            "to_column": "column2"
        },
        # ...
    ]
    return relationships
```

### Thay đổi table groups

Edit method `generate_table_groups()` trong `dbml_generator.py`:

```python
def generate_table_groups(self) -> str:
    groups = {
        'Your Group Name': [
            'table1', 'table2', 'table3'
        ],
        # ...
    }
```

## 🔧 Troubleshooting

### Lỗi: File not found

```
FileNotFoundError: [Errno 2] No such file or directory: '../sql/01_schema.sql'
```

**Giải pháp:** Kiểm tra đường dẫn file SQL có đúng không.

### Lỗi: Không parse được bảng

```
❌ Không tìm thấy bảng nào
```

**Nguyên nhân:**

- File SQL không có cú pháp `CREATE TABLE` hợp lệ
- File có encoding không phải UTF-8

**Giải pháp:**

- Kiểm tra cú pháp SQL
- Đảm bảo file được save với encoding UTF-8

### Lỗi: Relationships không chính xác

**Nguyên nhân:** Parser tự động chưa phát hiện được foreign keys

**Giải pháp:**

1. Kiểm tra SQL có `CONSTRAINT ... FOREIGN KEY` đúng cú pháp
2. Thêm relationships thủ công vào `_get_manual_relationships()`

### Lỗi: Thiếu permissions

```
PermissionError: [Errno 13] Permission denied: './output'
```

**Giải pháp:** Đảm bảo có quyền ghi vào thư mục output.

## 📝 Ví dụ SQL được hỗ trợ

```sql
-- ✅ Được hỗ trợ
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_category 
        FOREIGN KEY (category_id) REFERENCES categories(category_id)
);

-- ✅ Index
CREATE INDEX idx_product_name ON products(product_name);

-- ❌ Chưa hỗ trợ
CREATE VIEW product_view AS SELECT * FROM products;
```

## 🆘 Hỗ trợ

Nếu gặp vấn đề:

1. Kiểm tra lại cú pháp SQL
2. Xem console output để debug
3. Kiểm tra file JSON được tạo để verify dữ liệu parsed
4. Thêm relationships thủ công nếu cần thiết

## 📊 Ví dụ output

Sau khi chạy thành công:

```
🚀 DBML Generator - Chỉ tạo file DBML
========================================
📖 Đang parse schema: ../sql/01_schema.sql
✅ Đã parse 20 bảng
🔗 Tìm thấy 25 relationships tự động
📝 Đang tạo DBML...
✅ DBML cơ bản: ./output/supermarket.dbml
✅ DBML đầy đủ: ./output/supermarket_full.dbml
✅ JSON schema: ./output/parsed_schema.json

🎯 Upload file .dbml lên dbdiagram.io để xem ERD online!
```
