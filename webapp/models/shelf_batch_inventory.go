package models

import "time"

// ShelfBatchInventory represents shelf_batch_inventory table
// Chi tiết từng batch trên kệ để track expiry date và pricing
type ShelfBatchInventory struct {
	ShelfBatchID    uint       `gorm:"primaryKey;column:shelf_batch_id" json:"shelf_batch_id"`
	ShelfID         uint       `gorm:"not null;column:shelf_id" json:"shelf_id"`
	ProductID       uint       `gorm:"not null;column:product_id" json:"product_id"`
	BatchCode       string     `gorm:"type:varchar(50);not null;index" json:"batch_code"`
	Quantity        int        `gorm:"not null;check:quantity >= 0" json:"quantity"`
	ExpiryDate      *time.Time `gorm:"type:date;index" json:"expiry_date,omitempty"`
	StockedDate     time.Time  `gorm:"not null;default:CURRENT_TIMESTAMP" json:"stocked_date"`
	ImportPrice     float64    `gorm:"type:decimal(12,2);not null" json:"import_price"`
	CurrentPrice    float64    `gorm:"type:decimal(12,2);not null" json:"current_price"`
	DiscountPercent float64    `gorm:"type:decimal(5,2);default:0" json:"discount_percent"`
	IsNearExpiry    bool       `gorm:"default:false" json:"is_near_expiry"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`

	// Relationships (foreign keys are handled manually in migration)
	Shelf   DisplayShelf `gorm:"foreignKey:ShelfID;references:ShelfID;constraint:OnUpdate:CASCADE,OnDelete:CASCADE;" json:"shelf,omitempty"`
	Product Product      `gorm:"foreignKey:ProductID;references:ProductID;constraint:OnUpdate:CASCADE,OnDelete:CASCADE;" json:"product,omitempty"`
}

// TableName specifies the table name for ShelfBatchInventory
func (ShelfBatchInventory) TableName() string {
	return "shelf_batch_inventory"
}

// ShouldDiscount checks if batch should be discounted based on expiry date
func (sbi *ShelfBatchInventory) ShouldDiscount(nearExpiryDays int) bool {
	if sbi.ExpiryDate == nil {
		return false
	}

	daysUntilExpiry := int(time.Until(*sbi.ExpiryDate).Hours() / 24)
	return daysUntilExpiry <= nearExpiryDays && daysUntilExpiry > 0
}

// IsExpired checks if batch has expired
func (sbi *ShelfBatchInventory) IsExpired() bool {
	if sbi.ExpiryDate == nil {
		return false
	}
	return time.Now().After(*sbi.ExpiryDate)
}

// ApplyDiscount applies discount to current price
func (sbi *ShelfBatchInventory) ApplyDiscount(discountPercent float64) {
	sbi.DiscountPercent = discountPercent
	sbi.CurrentPrice = sbi.ImportPrice * (1 - discountPercent/100)
	sbi.IsNearExpiry = true
}

// GetDaysUntilExpiry returns days until expiry (negative if expired)
func (sbi *ShelfBatchInventory) GetDaysUntilExpiry() int {
	if sbi.ExpiryDate == nil {
		return 999999 // Never expires
	}
	return int(time.Until(*sbi.ExpiryDate).Hours() / 24)
}
