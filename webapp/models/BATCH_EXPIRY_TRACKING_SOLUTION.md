# 📦 Batch Expiry Tracking Solution

## 🎯 Vấn đề cần giải quyết

### Vấn đề ban đầu
- **ShelfInventory** chỉ có `CurrentQuantity` tổng
- Không thể phân biệt batch nào sắp hết hạn để discount
- Không thể thực hiện FIFO (First In, First Out) một cách chính xác
- Mất thông tin về expiry date khi chuyển từ kho lên kệ
- Khó quản lý pricing theo từng batch

### Ví dụ thực tế
```
Kệ A1 có:
- 50 chai sữa batch A001 (HSD: 15/12/2024) 
- 80 chai sữa batch B002 (HSD: 22/12/2024)
- Tổng: 130 chai

❌ Trước: Chỉ biết có 130 chai, không biết cái nào sắp hết hạn
✅ Sau: Biết chính xác 50 chai cần discount, 80 chai bình thường
```

---

## 🏗️ Giải pháp: Dual-Layer Tracking System

### Kiến trúc tổng quan

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│ WarehouseInv    │    │   StockTransfer  │    │ ShelfBatchInventory │
│ (Batch Details) │───▶│  (Transfer Log)  │───▶│   (Batch Details)   │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
                                                            │
                                                            ▼
                                               ┌─────────────────────┐
                                               │  ShelfInventory     │
                                               │ (Summary/Aggregate) │
                                               └─────────────────────┘
```

### Dual-Layer Explained

**Layer 1: ShelfBatchInventory** - Chi tiết từng batch
- Track từng batch riêng biệt
- Expiry date, pricing, discount cho mỗi batch
- Cho phép FIFO và smart pricing

**Layer 2: ShelfInventory** - Summary/Aggregate  
- Tổng hợp dữ liệu từ các batch
- Quick queries cho dashboard
- Performance optimization

---

## 📋 Database Schema

### 1. ShelfBatchInventory (MỚI)

```sql
CREATE TABLE shelf_batch_inventory (
    shelf_batch_id      INT PRIMARY KEY AUTO_INCREMENT,
    shelf_id           INT NOT NULL,
    product_id         INT NOT NULL,
    batch_code         VARCHAR(50) NOT NULL,
    quantity           INT NOT NULL CHECK (quantity >= 0),
    expiry_date        DATE,
    stocked_date       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    import_price       DECIMAL(12,2) NOT NULL,
    current_price      DECIMAL(12,2) NOT NULL,
    discount_percent   DECIMAL(5,2) DEFAULT 0,
    is_near_expiry     BOOLEAN DEFAULT FALSE,
    
    INDEX idx_batch_code (batch_code),
    INDEX idx_expiry_date (expiry_date),
    INDEX idx_shelf_product (shelf_id, product_id),
    
    FOREIGN KEY (shelf_id) REFERENCES display_shelves(shelf_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);
```

### 2. ShelfInventory (CẬP NHẬT)

```sql
ALTER TABLE shelf_inventory ADD COLUMN (
    near_expiry_quantity   INT DEFAULT 0 CHECK (near_expiry_quantity >= 0),
    expired_quantity       INT DEFAULT 0 CHECK (expired_quantity >= 0), 
    earliest_expiry_date   DATE,
    latest_expiry_date     DATE
);
```

### 3. StockTransfer (CẬP NHẬT)

```sql  
ALTER TABLE stock_transfers MODIFY COLUMN batch_code VARCHAR(50) NOT NULL;
ALTER TABLE stock_transfers ADD COLUMN (
    expiry_date     DATE,
    import_price    DECIMAL(12,2) NOT NULL,
    selling_price   DECIMAL(12,2) NOT NULL
);
```

---

## 🔄 Quy trình hoạt động

### 1. Nhập hàng vào kho
```go
// WarehouseInventory đã có batch tracking
warehouseInv := WarehouseInventory{
    ProductID:   101,
    BatchCode:   "MILK_TH_A001", 
    Quantity:    100,
    ImportDate:  time.Now(),
    ExpiryDate:  &expiryDate,
    ImportPrice: 12000,
}
```

### 2. Chuyển hàng lên kệ  
```go
// StockTransfer với đầy đủ batch info
transfer := StockTransfer{
    ProductID:       101,
    FromWarehouseID: 1,
    ToShelfID:      1,
    Quantity:       50,
    BatchCode:      "MILK_TH_A001",
    ExpiryDate:     &expiryDate,
    ImportPrice:    12000,
    SellingPrice:   15000,
}

// Tự động tạo ShelfBatchInventory
shelfBatch := transfer.CreateShelfBatchInventory()
```

### 3. Auto-update summary
```go
// ShelfInventory tự động cập nhật từ batch data
shelfInv.UpdateSummaryFromBatches(batches, nearExpiryDays)
```

### 4. Smart pricing & discounting
```go
// Tự động discount batch sắp hết hạn
if batch.ShouldDiscount(7) { // 7 ngày trước HSD
    batch.ApplyDiscount(20.0) // Giảm 20%
}
```

---

## 💡 Tính năng chính

### 🎯 Expiry Management
- **Near Expiry Warning**: Cảnh báo hàng sắp hết hạn
- **Auto Discount**: Tự động giảm giá theo HSD
- **Expired Tracking**: Track hàng đã hết hạn cần loại bỏ

### 📊 FIFO Implementation
```sql
-- Bán hàng theo thứ tự HSD sớm nhất trước
SELECT * FROM shelf_batch_inventory 
WHERE shelf_id = 1 AND product_id = 101 AND quantity > 0
ORDER BY expiry_date ASC, stocked_date ASC;
```

### 💰 Dynamic Pricing  
```go
// Giá có thể thay đổi theo batch
batch1.CurrentPrice = 15000  // Giá gốc
batch2.CurrentPrice = 12000  // Đã discount 20%
```

### 📈 Performance Optimization
- **Batch Level**: Chi tiết cho operations
- **Summary Level**: Nhanh cho reports/dashboard

---

## 🔍 Use Cases

### 1. Dashboard Overview
```sql
-- Quick overview từ summary table
SELECT 
    s.shelf_code,
    p.product_name,
    si.current_quantity,
    si.near_expiry_quantity,
    si.expired_quantity,
    si.earliest_expiry_date
FROM shelf_inventory si
JOIN display_shelves s ON si.shelf_id = s.shelf_id
JOIN products p ON si.product_id = p.product_id
WHERE si.near_expiry_quantity > 0;
```

### 2. Detailed Batch Analysis
```sql
-- Chi tiết từng batch cho operations
SELECT 
    batch_code,
    quantity,
    current_price,
    discount_percent,
    DATEDIFF(expiry_date, NOW()) as days_left
FROM shelf_batch_inventory
WHERE shelf_id = 1 AND is_near_expiry = true
ORDER BY expiry_date ASC;
```

### 3. Automated Discount Process
```go
// Chạy daily job để discount hàng sắp hết hạn  
func AutoDiscountNearExpiry(nearExpiryDays int, discountPercent float64) {
    var batches []ShelfBatchInventory
    
    db.Where("DATEDIFF(expiry_date, NOW()) <= ? AND DATEDIFF(expiry_date, NOW()) > 0 AND discount_percent = 0", 
             nearExpiryDays).Find(&batches)
    
    for _, batch := range batches {
        batch.ApplyDiscount(discountPercent)
        db.Save(&batch)
    }
    
    // Update summary tables
    updateShelfInventorySummary()
}
```

### 4. POS Integration - FIFO Selling
```go
// Bán hàng theo FIFO
func SellProduct(shelfID, productID uint, quantityToSell int) error {
    var batches []ShelfBatchInventory
    
    // Lấy batch theo thứ tự HSD sớm nhất
    db.Where("shelf_id = ? AND product_id = ? AND quantity > 0 AND expiry_date > NOW()", 
             shelfID, productID).
       Order("expiry_date ASC, stocked_date ASC").
       Find(&batches)
    
    remaining := quantityToSell
    for _, batch := range batches {
        if remaining <= 0 { break }
        
        soldFromBatch := min(batch.Quantity, remaining)
        batch.Quantity -= soldFromBatch
        remaining -= soldFromBatch
        
        db.Save(&batch)
    }
    
    // Update summary
    updateShelfInventorySummary(shelfID, productID)
    return nil
}
```

---

## ✅ BCNF Compliance

### Functional Dependencies Analysis

**ShelfBatchInventory**:
- `shelf_batch_id → shelf_id, product_id, batch_code, quantity, expiry_date, ...`
- `(shelf_id, product_id, batch_code) → shelf_batch_id, quantity, expiry_date, ...`

**ShelfInventory**:  
- `shelf_inventory_id → shelf_id, product_id, current_quantity, near_expiry_quantity, ...`
- `(shelf_id, product_id) → shelf_inventory_id, current_quantity, ...`

**StockTransfer**:
- `transfer_id → product_id, from_warehouse_id, to_shelf_id, batch_code, ...`
- `transfer_code → transfer_id, product_id, ...`

✅ **Tất cả dependencies đều có determinant là superkey → BCNF compliant**

---

## 🚀 Migration Guide

### 1. Run Migration
```bash
cd webapp
go run cmd/migrate/main.go
```

### 2. Data Migration Script
```sql
-- Migrate existing shelf_inventory to new schema
ALTER TABLE shelf_inventory ADD COLUMN near_expiry_quantity INT DEFAULT 0;
ALTER TABLE shelf_inventory ADD COLUMN expired_quantity INT DEFAULT 0;
ALTER TABLE shelf_inventory ADD COLUMN earliest_expiry_date DATE;
ALTER TABLE shelf_inventory ADD COLUMN latest_expiry_date DATE;

-- Create new table
CREATE TABLE shelf_batch_inventory (
    -- Schema as defined above
);
```

### 3. Update Application Code
```go
// Import new model
import "your-app/models"

// Use new functions
shelfInv.UpdateSummaryFromBatches(batches, 7)
if batch.ShouldDiscount(7) {
    batch.ApplyDiscount(20.0)
}
```

---

## 📊 Benefits Summary

| Aspect | Before | After |
|--------|--------|-------|
| **Expiry Tracking** | ❌ Không có | ✅ Chi tiết từng batch |
| **FIFO** | ❌ Không thể | ✅ Chính xác theo HSD |
| **Auto Discount** | ❌ Manual | ✅ Tự động theo rule |
| **Performance** | 🔶 OK cho simple queries | ✅ Optimized dual-layer |
| **Data Integrity** | 🔶 Basic | ✅ BCNF compliant |
| **Scalability** | 🔶 Limited | ✅ Enterprise ready |

---

## 🔧 Maintenance

### Daily Tasks
- Run auto-discount job
- Update summary tables  
- Alert on expired items

### Weekly Tasks  
- Cleanup expired batches
- Performance optimization
- Data consistency checks

### Monitoring Queries
```sql
-- Health check
SELECT 
    COUNT(*) as total_batches,
    SUM(CASE WHEN expiry_date <= NOW() THEN 1 ELSE 0 END) as expired,
    SUM(CASE WHEN DATEDIFF(expiry_date, NOW()) <= 7 THEN 1 ELSE 0 END) as near_expiry
FROM shelf_batch_inventory;
```

---

## 📝 Example SQL Scenarios

Xem file `batch_tracking_example.sql` để có ví dụ chi tiết về:
- Nhập hàng và chuyển kệ
- Auto-discount process  
- FIFO selling queries
- Reporting và analytics

---

**🎉 Giải pháp này giúp bạn quản lý expiry date một cách thông minh, tự động discount, và đảm bảo FIFO - tất cả đều tuân thủ chuẩn BCNF!**
