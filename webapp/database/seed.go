package database

// This file now serves as the main entry point for seeding operations.
// All seeding functions have been organized into separate files:
//
// - master_seed.go: Contains SeedData and cleanupPartialData functions
// - basic_data_seed.go: Contains functions for warehouses, categories, positions, membership levels, suppliers
// - entity_seed.go: Contains functions for employees, customers, and employee work hours
// - product_seed.go: Contains functions for products, display shelves, and discount rules
// - inventory_seed.go: Contains functions for warehouse inventory and shelf data
// - transaction_seed.go: Contains functions for purchase orders, stock transfers, and sales invoices
// - helper_seed.go: Contains utility functions and helper methods
//
// The main SeedData function orchestrates the seeding process by calling
// functions from these specialized files in the correct dependency order.

// No imports needed - this is just documentation

// Main seeding functions are implemented in master_seed.go
// They are available at package level since they are in the same package
