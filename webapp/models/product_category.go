package models

import "time"

// ProductCategory represents product categories table
type ProductCategory struct {
	CategoryID   uint      `gorm:"primaryKey;column:category_id" json:"category_id"`
	CategoryName string    `gorm:"type:varchar(100);not null;unique" json:"category_name"`
	Description  *string   `gorm:"type:text" json:"description,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`

	// Relationships - commented out to avoid circular dependency issues during migration
	// Uncomment these after tables are created if you need eager loading
	// Products       []Product      `gorm:"foreignKey:CategoryID" json:"products,omitempty"`
	// DisplayShelves []DisplayShelf `gorm:"foreignKey:CategoryID" json:"display_shelves,omitempty"`
	// DiscountRules  []DiscountRule `gorm:"foreignKey:CategoryID" json:"discount_rules,omitempty"`
}

// TableName specifies the table name for ProductCategory
func (ProductCategory) TableName() string {
	return "product_categories"
}
