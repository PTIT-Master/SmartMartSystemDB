# Database Triggers Documentation

This document describes all the database triggers implemented for the Supermarket Management System to handle validation and data processing at the database level, reducing the need for application-level validation.

## Overview

The trigger system is organized into 7 main categories:

1. **Validation Triggers** - Enforce business rules and data integrity
2. **Inventory Management Triggers** - Handle stock movements and tracking
3. **Customer Management Triggers** - Manage customer metrics and loyalty
4. **Financial Calculation Triggers** - Auto-calculate invoice totals and subtotals
5. **Employee Management Triggers** - Track work hours and status
6. **Pricing Management Triggers** - Handle dynamic pricing based on expiry
7. **Audit Triggers** - Maintain timestamps and audit trails

## 1. Validation Triggers

### 1.1 Product Price Validation (`tr_validate_product_price`)
- **Table**: `products`
- **Event**: `BEFORE INSERT OR UPDATE`
- **Purpose**: Ensures selling price is always higher than import price
- **Validation**: `selling_price > import_price`

### 1.2 Shelf Capacity Validation (`tr_validate_shelf_capacity`)
- **Table**: `shelf_inventory`
- **Event**: `BEFORE INSERT OR UPDATE`
- **Purpose**: Prevents overstocking shelves beyond their maximum capacity
- **Validation**: `current_quantity <= max_quantity` (from shelf_layout)

### 1.3 Category Consistency Validation
- **Tables**: `shelf_layout`, `shelf_inventory`
- **Event**: `BEFORE INSERT OR UPDATE`
- **Purpose**: Ensures products placed on shelves match the shelf's designated category
- **Validation**: Product category must match shelf category

### 1.4 Stock Transfer Validation (`tr_validate_stock_transfer`)
- **Table**: `stock_transfers`
- **Event**: `BEFORE INSERT`
- **Purpose**: Validates stock availability and shelf capacity before transfers
- **Validations**:
  - Sufficient warehouse stock exists
  - Transfer won't exceed shelf capacity
  - Product is configured for target shelf

## 2. Inventory Management Triggers

### 2.1 Stock Transfer Processing (`tr_process_stock_transfer`)
- **Table**: `stock_transfers`
- **Event**: `AFTER INSERT`
- **Purpose**: Automatically updates warehouse and shelf inventories
- **Actions**:
  - Deducts quantity from warehouse_inventory
  - Adds quantity to shelf_inventory
  - Updates timestamps

### 2.2 Sales Stock Deduction (`tr_process_sales_stock_deduction`)
- **Table**: `sales_invoice_details`
- **Event**: `AFTER INSERT`
- **Purpose**: Automatically deducts sold items from shelf inventory
- **Actions**:
  - Validates sufficient shelf stock
  - Deducts sold quantity from shelf_inventory

### 2.3 Expiry Date Calculation (`tr_calculate_expiry_date`)
- **Table**: `warehouse_inventory`
- **Event**: `BEFORE INSERT OR UPDATE`
- **Purpose**: Auto-calculates expiry dates based on import date and shelf life
- **Calculation**: `expiry_date = import_date + shelf_life_days`

### 2.4 Low Stock Alerts (`tr_check_low_stock`)
- **Table**: `shelf_inventory`
- **Event**: `AFTER UPDATE`
- **Purpose**: Generates alerts when stock falls below threshold
- **Action**: Raises NOTICE when `current_quantity <= low_stock_threshold`

## 3. Customer Management Triggers

### 3.1 Customer Metrics Update (`tr_update_customer_metrics`)
- **Table**: `sales_invoices`
- **Event**: `BEFORE INSERT OR UPDATE`
- **Purpose**: Updates customer spending and calculates loyalty points
- **Actions**:
  - Updates `customers.total_spending`
  - Calculates loyalty points with membership multiplier
  - Updates `customers.loyalty_points`

### 3.2 Membership Level Upgrades (`tr_check_membership_upgrade`)
- **Table**: `customers`
- **Event**: `AFTER UPDATE OF total_spending`
- **Purpose**: Automatically upgrades customer membership based on spending
- **Logic**: Finds highest membership level customer qualifies for and upgrades

## 4. Financial Calculation Triggers

### 4.1 Sales Invoice Detail Subtotal (`tr_calculate_detail_subtotal`)
- **Table**: `sales_invoice_details`
- **Event**: `BEFORE INSERT OR UPDATE`
- **Purpose**: Auto-calculates line item subtotals
- **Calculation**: 
  - `discount_amount = unit_price × quantity × (discount_percentage / 100)`
  - `subtotal = (unit_price × quantity) - discount_amount`

### 4.2 Invoice Totals Calculation (`tr_calculate_invoice_totals`)
- **Table**: `sales_invoice_details`
- **Event**: `AFTER INSERT OR UPDATE OR DELETE`
- **Purpose**: Recalculates invoice totals when line items change
- **Calculations**:
  - `subtotal = SUM(detail.subtotal)`
  - `discount_amount = SUM(detail.discount_amount)`
  - `tax_amount = (subtotal - discount_amount) × 0.10`
  - `total_amount = subtotal - discount_amount + tax_amount`

### 4.3 Purchase Order Calculations
- **Tables**: `purchase_order_details`, `purchase_orders`
- **Purpose**: Auto-calculates purchase order subtotals and totals
- **Actions**:
  - Detail subtotal: `unit_price × quantity`
  - Order total: `SUM(detail.subtotal)`

## 5. Employee Management Triggers

### 5.1 Work Hours Calculation (`tr_calculate_work_hours`)
- **Table**: `employee_work_hours`
- **Event**: `BEFORE INSERT OR UPDATE`
- **Purpose**: Auto-calculates work hours from check-in/check-out times
- **Calculation**: `total_hours = (check_out_time - check_in_time) / 3600`

## 6. Pricing Management Triggers

### 6.1 Expiry Discount Application (`tr_apply_expiry_discounts`)
- **Table**: `warehouse_inventory`
- **Event**: `AFTER INSERT OR UPDATE OF expiry_date`
- **Purpose**: Automatically applies discounts to products nearing expiry
- **Logic**:
  - Calculates days until expiry
  - Finds applicable discount rule from `discount_rules`
  - Updates product selling price with discount

## 7. Audit Triggers

### 7.1 Timestamp Updates (`tr_update_timestamp_*`)
- **Tables**: All tables with `updated_at` column
- **Event**: `BEFORE UPDATE`
- **Purpose**: Automatically sets `updated_at = CURRENT_TIMESTAMP`

### 7.2 Created Timestamp (`tr_set_created_timestamp_*`)
- **Tables**: All tables with `created_at` column
- **Event**: `BEFORE INSERT`
- **Purpose**: Automatically sets `created_at = CURRENT_TIMESTAMP`

## Business Rules Enforced

### Inventory Rules
- ✅ Stock transfers cannot exceed warehouse inventory
- ✅ Shelf inventory cannot exceed shelf capacity
- ✅ Sales cannot exceed shelf inventory
- ✅ Products on shelves must match shelf category
- ✅ Low stock alerts when below threshold

### Financial Rules
- ✅ Selling price must be higher than import price
- ✅ Invoice totals auto-calculated from line items
- ✅ Discounts automatically applied
- ✅ Tax calculations (10% VAT)
- ✅ Loyalty points calculated with membership bonuses

### Customer Rules
- ✅ Customer spending automatically tracked
- ✅ Loyalty points earned on purchases
- ✅ Automatic membership level upgrades
- ✅ Points calculation with membership multipliers

### Employee Rules
- ✅ Work hours automatically calculated
- ✅ Timestamp tracking for all activities

### Product Rules
- ✅ Expiry dates auto-calculated
- ✅ Dynamic pricing based on expiry
- ✅ Category-specific discount rules applied

## Implementation in Migration

The triggers are automatically created during database migration:

1. Run migration: `go run cmd/migrate/main.go`
2. The system executes:
   - `triggers.sql` - Creates all trigger functions
   - `create_triggers.sql` - Creates all triggers
3. All triggers are active immediately

## Error Handling

Triggers use PostgreSQL's exception handling:
- **Validation errors**: `RAISE EXCEPTION` stops the operation
- **Warnings**: `RAISE NOTICE` logs but continues
- **Graceful failures**: Some triggers log warnings and continue

## Benefits

### Reduced Application Complexity
- ❌ No need for application-level price validation
- ❌ No need for manual inventory calculations
- ❌ No need for manual invoice total calculations
- ❌ No need for manual loyalty point calculations

### Data Consistency
- ✅ All business rules enforced at database level
- ✅ Cannot bypass validations with direct SQL
- ✅ Atomic operations ensure consistency
- ✅ Audit trails automatically maintained

### Performance
- ✅ Database-level calculations are faster
- ✅ Reduced application logic complexity
- ✅ Fewer round trips between app and database

## Usage Examples

### Example 1: Adding a Product
```sql
-- This will automatically validate that selling_price > import_price
INSERT INTO products (product_code, product_name, category_id, supplier_id, 
                     unit, import_price, selling_price, shelf_life_days)
VALUES ('P001', 'Bread', 1, 1, 'piece', 1.50, 2.00, 3);
-- ✅ Success: 2.00 > 1.50

-- This will fail
INSERT INTO products (product_code, product_name, category_id, supplier_id, 
                     unit, import_price, selling_price, shelf_life_days)
VALUES ('P002', 'Milk', 1, 1, 'liter', 2.00, 1.50, 7);
-- ❌ Error: Selling price (1.50) must be higher than import price (2.00)
```

### Example 2: Stock Transfer
```sql
-- This will automatically validate warehouse stock and shelf capacity
INSERT INTO stock_transfers (transfer_code, product_id, from_warehouse_id, 
                           to_shelf_id, quantity, employee_id)
VALUES ('T001', 1, 1, 1, 50, 1);
-- ✅ If valid: Updates warehouse_inventory and shelf_inventory automatically
-- ❌ If invalid: Error message about insufficient stock or capacity
```

### Example 3: Sales Transaction
```sql
-- This will automatically calculate subtotal and update inventory
INSERT INTO sales_invoice_details (invoice_id, product_id, quantity, 
                                 unit_price, discount_percentage)
VALUES (1, 1, 2, 2.00, 10.0);
-- ✅ Auto-calculates: discount_amount = 0.40, subtotal = 3.60
-- ✅ Auto-deducts: 2 units from shelf_inventory
-- ✅ Auto-updates: invoice totals
```

## Troubleshooting

### Common Issues

1. **"Insufficient warehouse stock"**
   - Check `warehouse_inventory` for product
   - Ensure stock transfer quantities are valid

2. **"Product not configured for shelf"**
   - Add entry to `shelf_layout` table first
   - Ensure shelf category matches product category

3. **"Quantity exceeds maximum allowed"**
   - Check `shelf_layout.max_quantity`
   - Reduce transfer/restock quantity

4. **"Selling price must be higher than import price"**
   - Adjust product pricing
   - Check import price is correct

### Viewing Trigger Status
```sql
-- View all triggers
SELECT schemaname, tablename, triggername 
FROM pg_triggers 
WHERE schemaname = 'supermarket'
ORDER BY tablename, triggername;

-- View trigger functions
SELECT proname, prosrc 
FROM pg_proc 
WHERE proname LIKE '%validate%' OR proname LIKE '%calculate%';
```

This trigger system provides comprehensive data integrity and business rule enforcement at the database level, significantly reducing application complexity while ensuring data consistency.
