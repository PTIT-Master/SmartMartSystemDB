package models

import "time"

// StockTransfer represents stock_transfers table
type StockTransfer struct {
	TransferID      uint      `gorm:"primaryKey;column:transfer_id" json:"transfer_id"`
	TransferCode    string    `gorm:"type:varchar(30);not null;unique" json:"transfer_code"`
	ProductID       uint      `gorm:"not null" json:"product_id"`
	FromWarehouseID uint      `gorm:"not null" json:"from_warehouse_id"`
	ToShelfID       uint      `gorm:"not null" json:"to_shelf_id"`
	Quantity        int       `gorm:"not null;check:quantity > 0" json:"quantity"`
	TransferDate    time.Time `gorm:"not null;default:CURRENT_TIMESTAMP" json:"transfer_date"`
	EmployeeID      uint      `gorm:"not null" json:"employee_id"`
	BatchCode       *string   `gorm:"type:varchar(50)" json:"batch_code,omitempty"`
	Notes           *string   `gorm:"type:text" json:"notes,omitempty"`
	CreatedAt       time.Time `json:"created_at"`

	// Relationships
	Product       Product      `gorm:"foreignKey:ProductID" json:"product,omitempty"`
	FromWarehouse Warehouse    `gorm:"foreignKey:FromWarehouseID" json:"from_warehouse,omitempty"`
	ToShelf       DisplayShelf `gorm:"foreignKey:ToShelfID" json:"to_shelf,omitempty"`
	Employee      Employee     `gorm:"foreignKey:EmployeeID" json:"employee,omitempty"`
}

// TableName specifies the table name for StockTransfer
func (StockTransfer) TableName() string {
	return "stock_transfers"
}
