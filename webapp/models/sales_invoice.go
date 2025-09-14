package models

import "time"

// PaymentMethod type for payment methods
type PaymentMethod string

const (
	PaymentCash     PaymentMethod = "CASH"
	PaymentCard     PaymentMethod = "CARD"
	PaymentTransfer PaymentMethod = "TRANSFER"
	PaymentVoucher  PaymentMethod = "VOUCHER"
)

// SalesInvoice represents sales_invoices table
type SalesInvoice struct {
	InvoiceID      uint           `gorm:"primaryKey;column:invoice_id" json:"invoice_id"`
	InvoiceNo      string         `gorm:"type:varchar(30);not null;unique" json:"invoice_no"`
	CustomerID     *uint          `json:"customer_id,omitempty"`
	EmployeeID     uint           `gorm:"not null" json:"employee_id"`
	InvoiceDate    time.Time      `gorm:"not null;default:CURRENT_TIMESTAMP" json:"invoice_date"`
	Subtotal       float64        `gorm:"type:decimal(12,2);not null;default:0" json:"subtotal"`
	DiscountAmount float64        `gorm:"type:decimal(12,2);default:0" json:"discount_amount"`
	TaxAmount      float64        `gorm:"type:decimal(12,2);default:0" json:"tax_amount"`
	TotalAmount    float64        `gorm:"type:decimal(12,2);not null;default:0" json:"total_amount"`
	PaymentMethod  *PaymentMethod `gorm:"type:varchar(20)" json:"payment_method,omitempty"`
	PointsEarned   int            `gorm:"default:0" json:"points_earned"`
	PointsUsed     int            `gorm:"default:0" json:"points_used"`
	Notes          *string        `gorm:"type:text" json:"notes,omitempty"`
	CreatedAt      time.Time      `json:"created_at"`

	// Relationships
	Customer *Customer `gorm:"foreignKey:CustomerID" json:"customer,omitempty"`
	Employee Employee  `gorm:"foreignKey:EmployeeID" json:"employee,omitempty"`
	// Reverse relationships - commented out to avoid circular dependency issues during migration
	// Details  []SalesInvoiceDetail `gorm:"foreignKey:InvoiceID" json:"details,omitempty"`
}

// TableName specifies the table name for SalesInvoice
func (SalesInvoice) TableName() string {
	return "sales_invoices"
}

// SalesInvoiceDetail represents sales_invoice_details table
type SalesInvoiceDetail struct {
	DetailID           uint      `gorm:"primaryKey;column:detail_id" json:"detail_id"`
	InvoiceID          uint      `gorm:"not null" json:"invoice_id"`
	ProductID          uint      `gorm:"not null" json:"product_id"`
	Quantity           int       `gorm:"not null;check:quantity > 0" json:"quantity"`
	UnitPrice          float64   `gorm:"type:decimal(12,2);not null" json:"unit_price"`
	DiscountPercentage float64   `gorm:"type:decimal(5,2);default:0" json:"discount_percentage"`
	DiscountAmount     float64   `gorm:"type:decimal(12,2);default:0" json:"discount_amount"`
	Subtotal           float64   `gorm:"type:decimal(12,2);not null" json:"subtotal"`
	CreatedAt          time.Time `json:"created_at"`

	// Relationships
	Invoice SalesInvoice `gorm:"foreignKey:InvoiceID" json:"invoice,omitempty"`
	Product Product      `gorm:"foreignKey:ProductID" json:"product,omitempty"`
}

// TableName specifies the table name for SalesInvoiceDetail
func (SalesInvoiceDetail) TableName() string {
	return "sales_invoice_details"
}
