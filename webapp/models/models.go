package models

// AllModels returns all model structs for auto-migration
// IMPORTANT: Order matters! Parent tables must be created before child tables
func AllModels() []interface{} {
	return []interface{}{
		// 1. Independent tables (no foreign keys)
		&ProductCategory{},
		&Supplier{},
		&Warehouse{},
		&Position{},
		&MembershipLevel{},

		// 2. Tables with single dependencies
		&Product{},      // depends on: ProductCategory, Supplier
		&DiscountRule{}, // depends on: ProductCategory
		&DisplayShelf{}, // depends on: ProductCategory
		&Employee{},     // depends on: Position
		&Customer{},     // depends on: MembershipLevel

		// 3. Tables with multiple dependencies
		&WarehouseInventory{}, // depends on: Warehouse, Product
		&ShelfLayout{},        // depends on: DisplayShelf, Product
		&ShelfInventory{},     // depends on: DisplayShelf, Product
		&EmployeeWorkHour{},   // depends on: Employee
		&SalesInvoice{},       // depends on: Customer, Employee
		&PurchaseOrder{},      // depends on: Supplier, Employee

		// 4. Detail/junction tables
		&SalesInvoiceDetail{},  // depends on: SalesInvoice, Product
		&PurchaseOrderDetail{}, // depends on: PurchaseOrder, Product
		&StockTransfer{},       // depends on: Product, Warehouse, DisplayShelf, Employee
	}
}
