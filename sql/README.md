# Supermarket Database SQL Files

## File Structure

The database setup is organized into 4 main SQL files:

### 1. `01_schema.sql`

- **Purpose**: Database schema definition
- **Contents**:
  - Schema creation (`supermarket`)
  - Table definitions (19 tables)
  - Primary/Foreign key constraints
  - Check constraints
  - Indexes for performance
  - Basic triggers (timestamps, inventory updates)
  - Views for common queries

### 2. `02_functions.sql`

- **Purpose**: Business logic implementation
- **Contents**:
  - `fn_restock_shelf()` - Transfer products from warehouse to shelf
  - `fn_process_sale()` - Handle sales transactions
  - `fn_get_low_stock_products()` - Find products needing restock
  - `fn_apply_expiry_discounts()` - Calculate discounts for near-expiry items
  - `fn_calculate_employee_salary()` - Compute employee wages
  - `fn_get_top_customers()` - Customer ranking by spending
  - `fn_get_supplier_ranking()` - Supplier performance metrics
  - `fn_daily_sales_report()` - Daily business summary

### 3. `03_queries.sql`

- **Purpose**: Reporting views and complex queries
- **Contents**:
  - Product inventory views
  - Sales performance views
  - Employee performance tracking
  - Customer analytics
  - Supplier analytics
  - System alerts and monitoring
  - Dashboard summary functions

### 4. `04_insert_sample_data.sql`

- **Purpose**: Sample data for testing
- **Contents**:
  - Master data (categories, positions, levels)
  - 5 suppliers
  - 5 employees
  - 10 products
  - 5 customers
  - 5 display shelves
  - Initial inventory
  - 30 days of sales transactions
  - Purchase orders
  - Employee work hours

## Setup Instructions

1. **Create Database**:

```sql
CREATE DATABASE supermarket_db;
\c supermarket_db;
```

2. **Run SQL Files in Order**:

```bash
psql -U postgres -d supermarket_db -f 01_schema.sql
psql -U postgres -d supermarket_db -f 02_functions.sql
psql -U postgres -d supermarket_db -f 03_queries.sql
psql -U postgres -d supermarket_db -f 04_insert_sample_data.sql
```

Or run all at once:

```bash
psql -U postgres -d supermarket_db -f 01_schema.sql -f 02_functions.sql -f 03_queries.sql -f 04_insert_sample_data.sql
```

## Key Features

### Inventory Management

- Dual inventory tracking (warehouse + shelf)
- Automatic low stock alerts
- Batch tracking with expiry dates
- Smart restocking functions

### Sales Processing

- Point of sale transaction handling
- Customer membership and loyalty points
- Automatic inventory updates
- Multiple payment methods

### Reporting & Analytics

- Real-time dashboard
- Sales performance by product/employee
- Customer segmentation
- Supplier performance metrics
- Expiry date monitoring

### Business Rules Enforced

- Selling price > import price
- One product category per shelf
- Stock limits on shelves
- Automatic membership tier upgrades
- Near-expiry discount rules

## Common Operations

### Check System Status

```sql
SELECT * FROM fn_dashboard_summary();
SELECT * FROM fn_get_system_alerts();
```

### Process a Sale

```sql
SELECT * FROM fn_process_sale(
    p_employee_id := 3,
    p_customer_id := 1,
    p_payment_method := 'CASH',
    p_items := '[
        {"product_id": 1, "quantity": 2},
        {"product_id": 5, "quantity": 1}
    ]'::JSONB
);
```

### Restock Shelf

```sql
SELECT * FROM fn_restock_shelf(
    p_product_id := 1,
    p_shelf_id := 1,
    p_quantity := 20,
    p_employee_id := 5
);
```

### View Low Stock Products

```sql
SELECT * FROM v_products_need_restocking;
SELECT * FROM fn_get_low_stock_products();
```

### Generate Reports

```sql
-- Daily sales report
SELECT * FROM fn_daily_sales_report();

-- Monthly product ranking
SELECT * FROM fn_product_revenue_ranking();

-- Customer tier analysis
SELECT * FROM v_customer_tier_analysis;

-- Employee performance
SELECT * FROM v_employee_performance;
```

## Notes

- The database uses PostgreSQL-specific features (SERIAL, JSONB, etc.)
- All monetary values are in VND (Vietnamese Dong)
- Timestamps use server timezone
- Sample data generates ~300-900 sales transactions
- Triggers handle most automated updates
