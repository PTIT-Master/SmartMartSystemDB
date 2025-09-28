# Go Fiber Templates - Cấu trúc và Hướng dẫn

## 📁 Cấu trúc thư mục templates

```
webapp/web/templates/
├── layouts/
│   └── base.html           # Layout chính cho tất cả trang
├── pages/
│   ├── home.html          # Trang chủ
│   ├── error.html         # Trang lỗi
│   └── products/
│       ├── list.html      # Danh sách sản phẩm
│       ├── form.html      # Form thêm/sửa sản phẩm
│       └── view.html      # Chi tiết sản phẩm
└── partials/              # Các phần tử có thể tái sử dụng
```

## 🔧 Cách hoạt động của Go Fiber Templates

### 1. Layout System
Go Fiber sử dụng `{{embed}}` trong layout để nhúng nội dung template:

```html
<!-- layouts/base.html -->
<!DOCTYPE html>
<html>
<head>
    <title>{{.Title}}</title>
</head>
<body>
    <nav><!-- Navigation --></nav>
    
    <div class="container">
        {{embed}}  <!-- Nội dung template được nhúng tại đây -->
    </div>
</body>
</html>
```

### 2. Content Templates
Các template nội dung chỉ chứa HTML thuần, KHÔNG có wrapper:

```html
<!-- pages/products/list.html -->
<div class="card">
    <h1>Danh sách sản phẩm</h1>
    <!-- Nội dung template -->
</div>
```

### 3. Handler Usage
Trong handler, sử dụng layout làm tham số thứ 3:

```go
// ✅ ĐÚNG - Sử dụng layout parameter
return c.Render("pages/products/list", fiber.Map{
    "Title": "Sản phẩm",
    "Data": data,
}, "layouts/base")
```

## ⚠️ Lỗi thường gặp và cách tránh

### ❌ SAI - Mixing Template Systems

```html
<!-- SAI: Không được dùng {{template}} với {{define}} khi dùng Fiber layout -->
{{template "layouts/base" .}}
{{define "content"}}
    <div>Content here</div>
{{end}}
```

### ❌ SAI - Missing Layout Parameter

```go
// SAI: Thiếu layout parameter
return c.Render("pages/home", data)
```

### ❌ SAI - Wrong embed function

```html
<!-- SAI: {{embed}} không phải function -->
<div>{{template "content" .}}</div>
```

### ✅ ĐÚNG - Correct Structure

**Layout (layouts/base.html):**
```html
<!DOCTYPE html>
<html>
<head><title>{{.Title}}</title></head>
<body>
    <div class="container">{{embed}}</div>
</body>
</html>
```

**Content Template (pages/example.html):**
```html
<div class="card">
    <h1>{{.Title}}</h1>
    <p>Content goes here</p>
</div>
```

**Handler:**
```go
return c.Render("pages/example", fiber.Map{
    "Title": "Page Title",
}, "layouts/base")
```

## 📋 Checklist cho mỗi template mới

### Khi tạo Content Template:
- [ ] Chỉ chứa HTML content thuần
- [ ] KHÔNG có `{{template "layouts/base" .}}`
- [ ] KHÔNG có `{{define "content"}}`
- [ ] KHÔNG có wrapper HTML structure

### Khi tạo Handler:
- [ ] Sử dụng `c.Render()` với 3 parameters
- [ ] Parameter thứ 3 là `"layouts/base"`
- [ ] Pass đủ data cần thiết trong `fiber.Map`

### Khi sửa Layout:
- [ ] Sử dụng `{{embed}}` để nhúng content
- [ ] KHÔNG dùng `{{template "content" .}}`
- [ ] Đảm bảo tất cả CSS/JS global ở đây

## 🎯 Template Data Best Practices

### Standard Data cho mọi template:
```go
fiber.Map{
    "Title":           "Page Title",
    "Active":          "menu_name",      // Cho navigation active state
    "SQLQueries":      c.Locals("SQLQueries"),     // SQL debug
    "TotalSQLQueries": c.Locals("TotalSQLQueries"), // SQL debug
    // ... other page-specific data
}
```

### Navigation Active States:
- `"home"` - Trang chủ
- `"products"` - Sản phẩm  
- `"inventory"` - Kho hàng
- `"sales"` - Bán hàng
- `"employees"` - Nhân viên
- `"customers"` - Khách hàng
- `"reports"` - Báo cáo

## 🔍 Debug Templates

### Template Rendering Errors:
1. **"template not found"** → Kiểm tra đường dẫn file
2. **"embed: function not defined"** → Kiểm tra layout có đúng `{{embed}}` không
3. **"invalid value; expected X"** → Kiểm tra data type trong `fiber.Map`
4. **"executing template"** → Kiểm tra syntax trong template

### Testing Template Changes:
```bash
# Restart server để reload templates
cd webapp
go run main.go
```

## 📝 Ví dụ hoàn chỉnh

### Handler mới:
```go
func ExampleHandler(c *fiber.Ctx) error {
    // Lấy data từ database
    var items []Item
    db.Find(&items)
    
    return c.Render("pages/example", fiber.Map{
        "Title":           "Example Page",
        "Active":          "example",
        "Items":           items,
        "SQLQueries":      c.Locals("SQLQueries"),
        "TotalSQLQueries": c.Locals("TotalSQLQueries"),
    }, "layouts/base")
}
```

### Template mới (pages/example.html):
```html
<div class="card">
    <div class="card-header">{{.Title}}</div>
    <table>
        <thead>
            <tr><th>Name</th><th>Value</th></tr>
        </thead>
        <tbody>
            {{range .Items}}
            <tr>
                <td>{{.Name}}</td>
                <td>{{.Value}}</td>
            </tr>
            {{else}}
            <tr>
                <td colspan="2">No items found</td>
            </tr>
            {{end}}
        </tbody>
    </table>
</div>
```

## 🚀 Performance Tips

1. **Template Hot Reload**: Trong development, templates tự động reload
2. **Static Assets**: Đặt CSS/JS trong `layouts/base.html` hoặc `/static` folder  
3. **Database Queries**: Always pass `SQLQueries` data cho debug panel

---

## 📞 Khi gặp lỗi template:

1. Kiểm tra cấu trúc file theo guide này
2. Verify handler có sử dụng đúng 3 parameters không
3. Check layout file có `{{embed}}` không
4. Đảm bảo content template không có wrapper
5. Restart server sau khi sửa

**Ghi nhớ**: Fiber templates hoạt động khác với standard Go templates. Luôn dùng layout parameter thay vì template inheritance!
