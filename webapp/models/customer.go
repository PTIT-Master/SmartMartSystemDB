package models

import "time"

// MembershipLevel represents membership_levels table
type MembershipLevel struct {
	LevelID            uint      `gorm:"primaryKey;column:level_id" json:"level_id"`
	LevelName          string    `gorm:"type:varchar(50);not null;unique" json:"level_name"`
	MinSpending        float64   `gorm:"type:decimal(12,2);not null;default:0" json:"min_spending"`
	DiscountPercentage float64   `gorm:"type:decimal(5,2);default:0" json:"discount_percentage"`
	PointsMultiplier   float64   `gorm:"type:decimal(3,2);default:1.0" json:"points_multiplier"`
	CreatedAt          time.Time `json:"created_at"`

	// Relationships - commented out to avoid circular dependency issues during migration
	// Customers []Customer `gorm:"foreignKey:MembershipLevelID" json:"customers,omitempty"`
}

// TableName specifies the table name for MembershipLevel
func (MembershipLevel) TableName() string {
	return "membership_levels"
}

// Customer represents customers table
type Customer struct {
	CustomerID        uint      `gorm:"primaryKey;column:customer_id" json:"customer_id"`
	CustomerCode      *string   `gorm:"type:varchar(20);unique" json:"customer_code,omitempty"`
	FullName          *string   `gorm:"type:varchar(100)" json:"full_name,omitempty"`
	Phone             *string   `gorm:"type:varchar(20);unique" json:"phone,omitempty"`
	Email             *string   `gorm:"type:varchar(100)" json:"email,omitempty"`
	Address           *string   `gorm:"type:text" json:"address,omitempty"`
	MembershipCardNo  *string   `gorm:"type:varchar(20);unique" json:"membership_card_no,omitempty"`
	MembershipLevelID *uint     `json:"membership_level_id,omitempty"`
	RegistrationDate  time.Time `gorm:"type:date;default:CURRENT_DATE" json:"registration_date"`
	TotalSpending     float64   `gorm:"type:decimal(12,2);default:0" json:"total_spending"`
	LoyaltyPoints     int       `gorm:"default:0" json:"loyalty_points"`
	IsActive          bool      `gorm:"default:true" json:"is_active"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`

	// Relationships
	MembershipLevel *MembershipLevel `gorm:"foreignKey:MembershipLevelID" json:"membership_level,omitempty"`
	// Reverse relationships - commented out to avoid circular dependency issues during migration
	// SalesInvoices   []SalesInvoice   `gorm:"foreignKey:CustomerID" json:"sales_invoices,omitempty"`
}

// TableName specifies the table name for Customer
func (Customer) TableName() string {
	return "customers"
}
