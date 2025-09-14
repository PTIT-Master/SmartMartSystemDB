package models

import "time"

// Position represents positions table
type Position struct {
	PositionID   uint      `gorm:"primaryKey;column:position_id" json:"position_id"`
	PositionCode string    `gorm:"type:varchar(20);not null;unique" json:"position_code"`
	PositionName string    `gorm:"type:varchar(100);not null" json:"position_name"`
	BaseSalary   float64   `gorm:"type:decimal(12,2);not null;check:base_salary >= 0" json:"base_salary"`
	HourlyRate   float64   `gorm:"type:decimal(10,2);not null;check:hourly_rate >= 0" json:"hourly_rate"`
	CreatedAt    time.Time `json:"created_at"`

	// Relationships - commented out to avoid circular dependency issues during migration
	// Employees []Employee `gorm:"foreignKey:PositionID" json:"employees,omitempty"`
}

// TableName specifies the table name for Position
func (Position) TableName() string {
	return "positions"
}

// Employee represents employees table
type Employee struct {
	EmployeeID   uint      `gorm:"primaryKey;column:employee_id" json:"employee_id"`
	EmployeeCode string    `gorm:"type:varchar(20);not null;unique" json:"employee_code"`
	FullName     string    `gorm:"type:varchar(100);not null" json:"full_name"`
	PositionID   uint      `gorm:"not null" json:"position_id"`
	Phone        *string   `gorm:"type:varchar(20)" json:"phone,omitempty"`
	Email        *string   `gorm:"type:varchar(100);unique" json:"email,omitempty"`
	Address      *string   `gorm:"type:text" json:"address,omitempty"`
	HireDate     time.Time `gorm:"type:date;not null;default:CURRENT_DATE" json:"hire_date"`
	IDCard       *string   `gorm:"type:varchar(20);unique" json:"id_card,omitempty"`
	BankAccount  *string   `gorm:"type:varchar(50)" json:"bank_account,omitempty"`
	IsActive     bool      `gorm:"default:true" json:"is_active"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`

	// Relationships
	Position Position `gorm:"foreignKey:PositionID" json:"position,omitempty"`
	// Reverse relationships - commented out to avoid circular dependency issues during migration
	// WorkHours      []EmployeeWorkHour `gorm:"foreignKey:EmployeeID" json:"work_hours,omitempty"`
	// SalesInvoices  []SalesInvoice     `gorm:"foreignKey:EmployeeID" json:"sales_invoices,omitempty"`
	// PurchaseOrders []PurchaseOrder    `gorm:"foreignKey:EmployeeID" json:"purchase_orders,omitempty"`
	// StockTransfers []StockTransfer    `gorm:"foreignKey:EmployeeID" json:"stock_transfers,omitempty"`
}

// TableName specifies the table name for Employee
func (Employee) TableName() string {
	return "employees"
}

// EmployeeWorkHour represents employee_work_hours table
type EmployeeWorkHour struct {
	WorkHourID   uint       `gorm:"primaryKey;column:work_hour_id" json:"work_hour_id"`
	EmployeeID   uint       `gorm:"not null" json:"employee_id"`
	WorkDate     time.Time  `gorm:"type:date;not null" json:"work_date"`
	CheckInTime  *time.Time `gorm:"type:time" json:"check_in_time,omitempty"`
	CheckOutTime *time.Time `gorm:"type:time" json:"check_out_time,omitempty"`
	TotalHours   float64    `gorm:"type:decimal(5,2)" json:"total_hours"`
	CreatedAt    time.Time  `json:"created_at"`

	// Relationships
	Employee Employee `gorm:"foreignKey:EmployeeID" json:"employee,omitempty"`
}

// TableName specifies the table name for EmployeeWorkHour
func (EmployeeWorkHour) TableName() string {
	return "employee_work_hours"
}
