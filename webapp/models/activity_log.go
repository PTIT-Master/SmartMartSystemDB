package models

import (
	"time"
)

// ActivityLog represents activity_logs table
type ActivityLog struct {
	LogID        uint      `gorm:"primaryKey;column:log_id" json:"log_id"`
	ActivityType string    `gorm:"type:varchar(50);not null" json:"activity_type"`
	Description  string    `gorm:"type:text;not null" json:"description"`
	TableName    *string   `gorm:"type:varchar(100)" json:"table_name,omitempty"`
	RecordID     *uint     `json:"record_id,omitempty"`
	UserID       *uint     `json:"user_id,omitempty"`
	UserName     *string   `gorm:"type:varchar(100)" json:"user_name,omitempty"`
	IPAddress    *string   `gorm:"type:varchar(45)" json:"ip_address,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

// GetTableName returns the table name for ActivityLog
func (ActivityLog) GetTableName() string {
	return "activity_logs"
}

// Activity types constants
const (
	ActivityTypeProductCreated      = "PRODUCT_CREATED"
	ActivityTypeProductUpdated      = "PRODUCT_UPDATED"
	ActivityTypeProductDeleted      = "PRODUCT_DELETED"
	ActivityTypeStockTransfer       = "STOCK_TRANSFER"
	ActivityTypeSaleCompleted       = "SALE_COMPLETED"
	ActivityTypeCustomerCreated     = "CUSTOMER_CREATED"
	ActivityTypeCustomerUpdated     = "CUSTOMER_UPDATED"
	ActivityTypeEmployeeCreated     = "EMPLOYEE_CREATED"
	ActivityTypeEmployeeUpdated     = "EMPLOYEE_UPDATED"
	ActivityTypeLowStockAlert       = "LOW_STOCK_ALERT"
	ActivityTypeExpiryAlert         = "EXPIRY_ALERT"
	ActivityTypePriceDiscount       = "PRICE_DISCOUNT"
	ActivityTypeInventoryAdjustment = "INVENTORY_ADJUSTMENT"
)
