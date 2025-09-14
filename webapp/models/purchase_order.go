package models

import "time"

// OrderStatus type for order status
type OrderStatus string

const (
	OrderPending   OrderStatus = "PENDING"
	OrderApproved  OrderStatus = "APPROVED"
	OrderReceived  OrderStatus = "RECEIVED"
	OrderCancelled OrderStatus = "CANCELLED"
)

// PurchaseOrder represents purchase_orders table
type PurchaseOrder struct {
	OrderID      uint        `gorm:"primaryKey;column:order_id" json:"order_id"`
	OrderNo      string      `gorm:"type:varchar(30);not null;unique" json:"order_no"`
	SupplierID   uint        `gorm:"not null" json:"supplier_id"`
	EmployeeID   uint        `gorm:"not null" json:"employee_id"`
	OrderDate    time.Time   `gorm:"type:date;not null;default:CURRENT_DATE" json:"order_date"`
	DeliveryDate *time.Time  `gorm:"type:date" json:"delivery_date,omitempty"`
	TotalAmount  float64     `gorm:"type:decimal(12,2);not null;default:0" json:"total_amount"`
	Status       OrderStatus `gorm:"type:varchar(20);default:'PENDING'" json:"status"`
	Notes        *string     `gorm:"type:text" json:"notes,omitempty"`
	CreatedAt    time.Time   `json:"created_at"`
	UpdatedAt    time.Time   `json:"updated_at"`

	// Relationships
	Supplier Supplier `gorm:"foreignKey:SupplierID" json:"supplier,omitempty"`
	Employee Employee `gorm:"foreignKey:EmployeeID" json:"employee,omitempty"`
	// Reverse relationships - commented out to avoid circular dependency issues during migration
	// Details  []PurchaseOrderDetail `gorm:"foreignKey:OrderID" json:"details,omitempty"`
}

// TableName specifies the table name for PurchaseOrder
func (PurchaseOrder) TableName() string {
	return "purchase_orders"
}

// PurchaseOrderDetail represents purchase_order_details table
type PurchaseOrderDetail struct {
	DetailID  uint      `gorm:"primaryKey;column:detail_id" json:"detail_id"`
	OrderID   uint      `gorm:"not null" json:"order_id"`
	ProductID uint      `gorm:"not null" json:"product_id"`
	Quantity  int       `gorm:"not null;check:quantity > 0" json:"quantity"`
	UnitPrice float64   `gorm:"type:decimal(12,2);not null" json:"unit_price"`
	Subtotal  float64   `gorm:"type:decimal(12,2);not null" json:"subtotal"`
	CreatedAt time.Time `json:"created_at"`

	// Relationships
	Order   PurchaseOrder `gorm:"foreignKey:OrderID" json:"order,omitempty"`
	Product Product       `gorm:"foreignKey:ProductID" json:"product,omitempty"`
}

// TableName specifies the table name for PurchaseOrderDetail
func (PurchaseOrderDetail) TableName() string {
	return "purchase_order_details"
}
