package models

import "time"

// DiscountRule represents discount_rules table
type DiscountRule struct {
	RuleID             uint      `gorm:"primaryKey;column:rule_id" json:"rule_id"`
	CategoryID         uint      `gorm:"not null" json:"category_id"`
	DaysBeforeExpiry   int       `gorm:"not null" json:"days_before_expiry"`
	DiscountPercentage float64   `gorm:"type:decimal(5,2);not null;check:discount_percentage >= 0 AND discount_percentage <= 100" json:"discount_percentage"`
	RuleName           *string   `gorm:"type:varchar(100)" json:"rule_name,omitempty"`
	IsActive           bool      `gorm:"default:true" json:"is_active"`
	CreatedAt          time.Time `gorm:"autoCreateTime" json:"created_at"`

	// Relationships
	Category ProductCategory `gorm:"foreignKey:CategoryID" json:"category,omitempty"`
}

// TableName specifies the table name for DiscountRule
func (DiscountRule) TableName() string {
	return "supermarket.discount_rules"
}
