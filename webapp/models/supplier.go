package models

import "time"

// Supplier represents suppliers table
type Supplier struct {
	SupplierID    uint      `gorm:"primaryKey;column:supplier_id" json:"supplier_id"`
	SupplierCode  string    `gorm:"type:varchar(20);not null;unique" json:"supplier_code"`
	SupplierName  string    `gorm:"type:varchar(200);not null" json:"supplier_name"`
	ContactPerson *string   `gorm:"type:varchar(100)" json:"contact_person,omitempty"`
	Phone         *string   `gorm:"type:varchar(20)" json:"phone,omitempty"`
	Email         *string   `gorm:"type:varchar(100)" json:"email,omitempty"`
	Address       *string   `gorm:"type:text" json:"address,omitempty"`
	TaxCode       *string   `gorm:"type:varchar(20)" json:"tax_code,omitempty"`
	BankAccount   *string   `gorm:"type:varchar(50)" json:"bank_account,omitempty"`
	IsActive      bool      `gorm:"default:true" json:"is_active"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`

	// Relationships - commented out to avoid circular dependency issues during migration
	// Products       []Product       `gorm:"foreignKey:SupplierID" json:"products,omitempty"`
	// PurchaseOrders []PurchaseOrder `gorm:"foreignKey:SupplierID" json:"purchase_orders,omitempty"`
}

// TableName specifies the table name for Supplier
func (Supplier) TableName() string {
	return "suppliers"
}
