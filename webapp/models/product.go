package models

import (
	"time"
)

// Product represents products table
type Product struct {
	ProductID         uint      `gorm:"primaryKey;column:product_id" json:"product_id"`
	ProductCode       string    `gorm:"type:varchar(50);not null;unique" json:"product_code"`
	ProductName       string    `gorm:"type:varchar(200);not null" json:"product_name"`
	CategoryID        uint      `gorm:"not null" json:"category_id"`
	SupplierID        uint      `gorm:"not null" json:"supplier_id"`
	Unit              string    `gorm:"type:varchar(20);not null" json:"unit"`
	ImportPrice       float64   `gorm:"type:decimal(12,2);not null;check:import_price > 0" json:"import_price"`
	SellingPrice      float64   `gorm:"type:decimal(12,2);not null" json:"selling_price"`
	ShelfLifeDays     *int      `json:"shelf_life_days,omitempty"`
	LowStockThreshold int       `gorm:"default:10" json:"low_stock_threshold"`
	Barcode           *string   `gorm:"type:varchar(50);unique" json:"barcode,omitempty"`
	Description       *string   `gorm:"type:text" json:"description,omitempty"`
	IsActive          bool      `gorm:"default:true" json:"is_active"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`

	// Relationships
	Category ProductCategory `gorm:"foreignKey:CategoryID" json:"category,omitempty"`
	Supplier Supplier        `gorm:"foreignKey:SupplierID" json:"supplier,omitempty"`
	// Reverse relationships - commented out to avoid circular dependency issues during migration
	// WarehouseInventories []WarehouseInventory  `gorm:"foreignKey:ProductID" json:"warehouse_inventories,omitempty"`
	// ShelfLayouts         []ShelfLayout         `gorm:"foreignKey:ProductID" json:"shelf_layouts,omitempty"`
	// ShelfInventories     []ShelfInventory      `gorm:"foreignKey:ProductID" json:"shelf_inventories,omitempty"`
	// SalesInvoiceDetails  []SalesInvoiceDetail  `gorm:"foreignKey:ProductID" json:"sales_invoice_details,omitempty"`
	// PurchaseOrderDetails []PurchaseOrderDetail `gorm:"foreignKey:ProductID" json:"purchase_order_details,omitempty"`
	// StockTransfers       []StockTransfer       `gorm:"foreignKey:ProductID" json:"stock_transfers,omitempty"`
}

// TableName specifies the table name for Product
func (Product) TableName() string {
	return "products"
}
