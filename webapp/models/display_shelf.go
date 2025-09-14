package models

import "time"

// DisplayShelf represents display_shelves table
type DisplayShelf struct {
	ShelfID     uint      `gorm:"primaryKey;column:shelf_id" json:"shelf_id"`
	ShelfCode   string    `gorm:"type:varchar(20);not null;unique" json:"shelf_code"`
	ShelfName   string    `gorm:"type:varchar(100);not null" json:"shelf_name"`
	CategoryID  uint      `gorm:"not null" json:"category_id"`
	Location    *string   `gorm:"type:varchar(100)" json:"location,omitempty"`
	MaxCapacity *int      `json:"max_capacity,omitempty"`
	IsActive    bool      `gorm:"default:true" json:"is_active"`
	CreatedAt   time.Time `json:"created_at"`

	// Relationships
	Category ProductCategory `gorm:"foreignKey:CategoryID" json:"category,omitempty"`
	// Reverse relationships - commented out to avoid circular dependency issues during migration
	// ShelfLayouts     []ShelfLayout    `gorm:"foreignKey:ShelfID" json:"shelf_layouts,omitempty"`
	// ShelfInventories []ShelfInventory `gorm:"foreignKey:ShelfID" json:"shelf_inventories,omitempty"`
	// StockTransfers   []StockTransfer  `gorm:"foreignKey:ToShelfID" json:"stock_transfers,omitempty"`
}

// TableName specifies the table name for DisplayShelf
func (DisplayShelf) TableName() string {
	return "display_shelves"
}

// ShelfLayout represents shelf_layout table
type ShelfLayout struct {
	LayoutID     uint      `gorm:"primaryKey;column:layout_id" json:"layout_id"`
	ShelfID      uint      `gorm:"not null" json:"shelf_id"`
	ProductID    uint      `gorm:"not null" json:"product_id"`
	PositionCode string    `gorm:"type:varchar(20);not null" json:"position_code"`
	MaxQuantity  int       `gorm:"not null;check:max_quantity > 0" json:"max_quantity"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`

	// Relationships
	Shelf   DisplayShelf `gorm:"foreignKey:ShelfID" json:"shelf,omitempty"`
	Product Product      `gorm:"foreignKey:ProductID" json:"product,omitempty"`
}

// TableName specifies the table name for ShelfLayout
func (ShelfLayout) TableName() string {
	return "shelf_layout"
}

// ShelfInventory represents shelf_inventory table
type ShelfInventory struct {
	ShelfInventoryID uint      `gorm:"primaryKey;column:shelf_inventory_id" json:"shelf_inventory_id"`
	ShelfID          uint      `gorm:"not null" json:"shelf_id"`
	ProductID        uint      `gorm:"not null" json:"product_id"`
	CurrentQuantity  int       `gorm:"not null;default:0;check:current_quantity >= 0" json:"current_quantity"`
	LastRestocked    time.Time `gorm:"default:CURRENT_TIMESTAMP" json:"last_restocked"`
	UpdatedAt        time.Time `json:"updated_at"`

	// Relationships
	Shelf   DisplayShelf `gorm:"foreignKey:ShelfID" json:"shelf,omitempty"`
	Product Product      `gorm:"foreignKey:ProductID" json:"product,omitempty"`
}

// TableName specifies the table name for ShelfInventory
func (ShelfInventory) TableName() string {
	return "shelf_inventory"
}
