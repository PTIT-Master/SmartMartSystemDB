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
	ShelfID      uint      `gorm:"not null;column:shelf_id" json:"shelf_id"`
	ProductID    uint      `gorm:"not null;column:product_id" json:"product_id"`
	PositionCode string    `gorm:"type:varchar(20);not null" json:"position_code"`
	MaxQuantity  int       `gorm:"not null;check:max_quantity > 0" json:"max_quantity"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`

	// Relationships
	Shelf   DisplayShelf `gorm:"foreignKey:ShelfID;references:ShelfID" json:"shelf,omitempty"`
	Product Product      `gorm:"foreignKey:ProductID;references:ProductID" json:"product,omitempty"`
}

// TableName specifies the table name for ShelfLayout
func (ShelfLayout) TableName() string {
	return "shelf_layout"
}

// ShelfInventory represents shelf_inventory table - Summary/Aggregate data
type ShelfInventory struct {
	ShelfInventoryID   uint       `gorm:"primaryKey;column:shelf_inventory_id" json:"shelf_inventory_id"`
	ShelfID            uint       `gorm:"not null;column:shelf_id" json:"shelf_id"`
	ProductID          uint       `gorm:"not null;column:product_id" json:"product_id"`
	CurrentQuantity    int        `gorm:"not null;default:0;check:current_quantity >= 0" json:"current_quantity"`
	NearExpiryQuantity int        `gorm:"default:0;check:near_expiry_quantity >= 0" json:"near_expiry_quantity"`
	ExpiredQuantity    int        `gorm:"default:0;check:expired_quantity >= 0" json:"expired_quantity"`
	EarliestExpiryDate *time.Time `gorm:"type:date" json:"earliest_expiry_date,omitempty"`
	LatestExpiryDate   *time.Time `gorm:"type:date" json:"latest_expiry_date,omitempty"`
	LastRestocked      time.Time  `gorm:"default:CURRENT_TIMESTAMP" json:"last_restocked"`
	UpdatedAt          time.Time  `json:"updated_at"`

	// Relationships
	Shelf      DisplayShelf          `gorm:"foreignKey:ShelfID;references:ShelfID" json:"shelf,omitempty"`
	Product    Product               `gorm:"foreignKey:ProductID;references:ProductID" json:"product,omitempty"`
	BatchItems []ShelfBatchInventory `gorm:"foreignKey:ShelfID,ProductID;references:ShelfID,ProductID" json:"batch_items,omitempty"`
}

// TableName specifies the table name for ShelfInventory
func (ShelfInventory) TableName() string {
	return "shelf_inventory"
}

// UpdateSummaryFromBatches recalculates summary fields from batch data
func (si *ShelfInventory) UpdateSummaryFromBatches(batches []ShelfBatchInventory, nearExpiryDays int) {
	si.CurrentQuantity = 0
	si.NearExpiryQuantity = 0
	si.ExpiredQuantity = 0
	si.EarliestExpiryDate = nil
	si.LatestExpiryDate = nil

	for _, batch := range batches {
		si.CurrentQuantity += batch.Quantity

		// Check expiry status
		if batch.IsExpired() {
			si.ExpiredQuantity += batch.Quantity
		} else if batch.ShouldDiscount(nearExpiryDays) {
			si.NearExpiryQuantity += batch.Quantity
		}

		// Update earliest/latest expiry dates
		if batch.ExpiryDate != nil {
			if si.EarliestExpiryDate == nil || batch.ExpiryDate.Before(*si.EarliestExpiryDate) {
				si.EarliestExpiryDate = batch.ExpiryDate
			}
			if si.LatestExpiryDate == nil || batch.ExpiryDate.After(*si.LatestExpiryDate) {
				si.LatestExpiryDate = batch.ExpiryDate
			}
		}
	}
	si.UpdatedAt = time.Now()
}

// HasExpiredItems returns true if there are expired items
func (si *ShelfInventory) HasExpiredItems() bool {
	return si.ExpiredQuantity > 0
}

// HasNearExpiryItems returns true if there are items near expiry
func (si *ShelfInventory) HasNearExpiryItems() bool {
	return si.NearExpiryQuantity > 0
}

// GetHealthyQuantity returns quantity of items that are not expired or near expiry
func (si *ShelfInventory) GetHealthyQuantity() int {
	return si.CurrentQuantity - si.NearExpiryQuantity - si.ExpiredQuantity
}
