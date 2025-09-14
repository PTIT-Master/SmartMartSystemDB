package models

import "time"

// Warehouse represents warehouse table
type Warehouse struct {
	WarehouseID   uint      `gorm:"primaryKey;column:warehouse_id" json:"warehouse_id"`
	WarehouseCode string    `gorm:"type:varchar(20);not null;unique" json:"warehouse_code"`
	WarehouseName string    `gorm:"type:varchar(100);not null" json:"warehouse_name"`
	Location      *string   `gorm:"type:varchar(200)" json:"location,omitempty"`
	ManagerName   *string   `gorm:"type:varchar(100)" json:"manager_name,omitempty"`
	Capacity      *int      `json:"capacity,omitempty"`
	CreatedAt     time.Time `json:"created_at"`

	// Relationships - commented out to avoid circular dependency issues during migration
	// WarehouseInventories []WarehouseInventory `gorm:"foreignKey:WarehouseID" json:"warehouse_inventories,omitempty"`
	// StockTransfers       []StockTransfer      `gorm:"foreignKey:FromWarehouseID" json:"stock_transfers,omitempty"`
}

// TableName specifies the table name for Warehouse
func (Warehouse) TableName() string {
	return "warehouse"
}

// WarehouseInventory represents warehouse_inventory table
type WarehouseInventory struct {
	InventoryID uint       `gorm:"primaryKey;column:inventory_id" json:"inventory_id"`
	WarehouseID uint       `gorm:"not null;default:1" json:"warehouse_id"`
	ProductID   uint       `gorm:"not null" json:"product_id"`
	BatchCode   string     `gorm:"type:varchar(50);not null" json:"batch_code"`
	Quantity    int        `gorm:"not null;default:0;check:quantity >= 0" json:"quantity"`
	ImportDate  time.Time  `gorm:"type:date;not null;default:CURRENT_DATE" json:"import_date"`
	ExpiryDate  *time.Time `gorm:"type:date" json:"expiry_date,omitempty"`
	ImportPrice float64    `gorm:"type:decimal(12,2);not null" json:"import_price"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`

	// Relationships
	Warehouse Warehouse `gorm:"foreignKey:WarehouseID" json:"warehouse,omitempty"`
	Product   Product   `gorm:"foreignKey:ProductID" json:"product,omitempty"`
}

// TableName specifies the table name for WarehouseInventory
func (WarehouseInventory) TableName() string {
	return "warehouse_inventory"
}
