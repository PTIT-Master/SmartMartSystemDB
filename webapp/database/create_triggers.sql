-- ============================================================================
-- CREATE TRIGGERS FOR SUPERMARKET DATABASE
-- ============================================================================
-- This file creates all the triggers that use the functions defined in triggers.sql
-- Run this after triggers.sql to set up the complete trigger system
-- ============================================================================

-- Set the schema
SET search_path TO supermarket;

-- ============================================================================
-- 1. VALIDATION TRIGGERS
-- ============================================================================

-- 1.1 Product Price Validation
DROP TRIGGER IF EXISTS tr_validate_product_price ON products;
CREATE TRIGGER tr_validate_product_price
    BEFORE INSERT OR UPDATE ON products
    FOR EACH ROW
    EXECUTE FUNCTION validate_product_price();

-- 1.2 Shelf Capacity Validation
DROP TRIGGER IF EXISTS tr_validate_shelf_capacity ON shelf_inventory;
CREATE TRIGGER tr_validate_shelf_capacity
    BEFORE INSERT OR UPDATE ON shelf_inventory
    FOR EACH ROW
    EXECUTE FUNCTION validate_shelf_capacity();

-- 1.3 Shelf Category Consistency Validation
DROP TRIGGER IF EXISTS tr_validate_shelf_category_layout ON shelf_layout;
CREATE TRIGGER tr_validate_shelf_category_layout
    BEFORE INSERT OR UPDATE ON shelf_layout
    FOR EACH ROW
    EXECUTE FUNCTION validate_shelf_category_consistency();

DROP TRIGGER IF EXISTS tr_validate_shelf_category_inventory ON shelf_inventory;
CREATE TRIGGER tr_validate_shelf_category_inventory
    BEFORE INSERT OR UPDATE ON shelf_inventory
    FOR EACH ROW
    EXECUTE FUNCTION validate_shelf_category_consistency();

-- 1.4 Stock Transfer Validation
DROP TRIGGER IF EXISTS tr_validate_stock_transfer ON stock_transfers;
CREATE TRIGGER tr_validate_stock_transfer
    BEFORE INSERT ON stock_transfers
    FOR EACH ROW
    EXECUTE FUNCTION validate_stock_transfer();

-- ============================================================================
-- 2. INVENTORY MANAGEMENT TRIGGERS
-- ============================================================================

-- 2.1 Process Stock Transfer (after validation passes)
DROP TRIGGER IF EXISTS tr_process_stock_transfer ON stock_transfers;
CREATE TRIGGER tr_process_stock_transfer
    AFTER INSERT ON stock_transfers
    FOR EACH ROW
    EXECUTE FUNCTION process_stock_transfer();

-- 2.2 Sales Stock Deduction
DROP TRIGGER IF EXISTS tr_process_sales_stock_deduction ON sales_invoice_details;
CREATE TRIGGER tr_process_sales_stock_deduction
    AFTER INSERT ON sales_invoice_details
    FOR EACH ROW
    EXECUTE FUNCTION process_sales_stock_deduction();

-- 2.3 Auto-calculate Expiry Date
DROP TRIGGER IF EXISTS tr_calculate_expiry_date ON warehouse_inventory;
CREATE TRIGGER tr_calculate_expiry_date
    BEFORE INSERT OR UPDATE ON warehouse_inventory
    FOR EACH ROW
    EXECUTE FUNCTION calculate_expiry_date();

-- 2.4 Low Stock Alert
DROP TRIGGER IF EXISTS tr_check_low_stock ON shelf_inventory;
CREATE TRIGGER tr_check_low_stock
    AFTER UPDATE ON shelf_inventory
    FOR EACH ROW
    EXECUTE FUNCTION check_low_stock();

-- ============================================================================
-- 3. CUSTOMER MANAGEMENT TRIGGERS
-- ============================================================================

-- 3.1 Update Customer Metrics (spending and points)
DROP TRIGGER IF EXISTS tr_update_customer_metrics ON sales_invoices;
CREATE TRIGGER tr_update_customer_metrics
    BEFORE INSERT OR UPDATE ON sales_invoices
    FOR EACH ROW
    EXECUTE FUNCTION update_customer_metrics();

-- 3.2 Check for Membership Upgrades
DROP TRIGGER IF EXISTS tr_check_membership_upgrade ON customers;
CREATE TRIGGER tr_check_membership_upgrade
    AFTER UPDATE OF total_spending ON customers
    FOR EACH ROW
    EXECUTE FUNCTION check_membership_upgrade();

-- ============================================================================
-- 4. FINANCIAL CALCULATION TRIGGERS
-- ============================================================================

-- 4.1 Auto-calculate Sales Invoice Detail Subtotal
DROP TRIGGER IF EXISTS tr_calculate_detail_subtotal ON sales_invoice_details;
CREATE TRIGGER tr_calculate_detail_subtotal
    BEFORE INSERT OR UPDATE ON sales_invoice_details
    FOR EACH ROW
    EXECUTE FUNCTION calculate_detail_subtotal();

-- 4.2 Auto-calculate Invoice Totals
DROP TRIGGER IF EXISTS tr_calculate_invoice_totals ON sales_invoice_details;
CREATE TRIGGER tr_calculate_invoice_totals
    AFTER INSERT OR UPDATE OR DELETE ON sales_invoice_details
    FOR EACH ROW
    EXECUTE FUNCTION calculate_invoice_totals();

-- 4.3 Purchase Order Detail Subtotal
DROP TRIGGER IF EXISTS tr_calculate_purchase_detail_subtotal ON purchase_order_details;
CREATE TRIGGER tr_calculate_purchase_detail_subtotal
    BEFORE INSERT OR UPDATE ON purchase_order_details
    FOR EACH ROW
    EXECUTE FUNCTION calculate_purchase_detail_subtotal();

-- 4.4 Update Purchase Order Total
DROP TRIGGER IF EXISTS tr_update_purchase_order_total_insert ON purchase_order_details;
CREATE TRIGGER tr_update_purchase_order_total_insert
    AFTER INSERT OR UPDATE OR DELETE ON purchase_order_details
    FOR EACH ROW
    EXECUTE FUNCTION update_purchase_order_total();

-- ============================================================================
-- 5. EMPLOYEE MANAGEMENT TRIGGERS
-- ============================================================================

-- 5.1 Auto-calculate Work Hours
DROP TRIGGER IF EXISTS tr_calculate_work_hours ON employee_work_hours;
CREATE TRIGGER tr_calculate_work_hours
    BEFORE INSERT OR UPDATE ON employee_work_hours
    FOR EACH ROW
    EXECUTE FUNCTION calculate_work_hours();

-- ============================================================================
-- 6. PRICING MANAGEMENT TRIGGERS
-- ============================================================================

-- 6.1 Auto-apply Expiry Discounts
DROP TRIGGER IF EXISTS tr_apply_expiry_discounts ON warehouse_inventory;
CREATE TRIGGER tr_apply_expiry_discounts
    AFTER INSERT OR UPDATE OF expiry_date ON warehouse_inventory
    FOR EACH ROW
    EXECUTE FUNCTION apply_expiry_discounts();

-- ============================================================================
-- 8. ACTIVITY LOGGING TRIGGERS
-- ============================================================================

-- 8.1 Product Activity Logging
DROP TRIGGER IF EXISTS tr_log_product_activity ON products;
CREATE TRIGGER tr_log_product_activity
    AFTER INSERT OR UPDATE OR DELETE ON products
    FOR EACH ROW
    EXECUTE FUNCTION log_product_activity();

-- 8.2 Stock Transfer Activity Logging
DROP TRIGGER IF EXISTS tr_log_stock_transfer_activity ON stock_transfers;
CREATE TRIGGER tr_log_stock_transfer_activity
    AFTER INSERT ON stock_transfers
    FOR EACH ROW
    EXECUTE FUNCTION log_stock_transfer_activity();

-- 8.3 Sales Activity Logging
DROP TRIGGER IF EXISTS tr_log_sales_activity ON sales_invoices;
CREATE TRIGGER tr_log_sales_activity
    AFTER INSERT ON sales_invoices
    FOR EACH ROW
    EXECUTE FUNCTION log_sales_activity();

-- 8.4 Low Stock Alert Logging
DROP TRIGGER IF EXISTS tr_log_low_stock_alert ON shelf_inventory;
CREATE TRIGGER tr_log_low_stock_alert
    AFTER UPDATE ON shelf_inventory
    FOR EACH ROW
    EXECUTE FUNCTION log_low_stock_alert();

-- 8.5 Expiry Alert Logging
DROP TRIGGER IF EXISTS tr_log_expiry_alert ON shelf_batch_inventory;
CREATE TRIGGER tr_log_expiry_alert
    AFTER INSERT OR UPDATE ON shelf_batch_inventory
    FOR EACH ROW
    EXECUTE FUNCTION log_expiry_alert();

-- ============================================================================
-- 7. AUDIT AND TIMESTAMP TRIGGERS
-- ============================================================================

-- 7.1 Auto-update timestamps for tables with updated_at column
DROP TRIGGER IF EXISTS tr_update_timestamp_products ON products;
CREATE TRIGGER tr_update_timestamp_products
    BEFORE UPDATE ON products
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

DROP TRIGGER IF EXISTS tr_update_timestamp_customers ON customers;
CREATE TRIGGER tr_update_timestamp_customers
    BEFORE UPDATE ON customers
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

DROP TRIGGER IF EXISTS tr_update_timestamp_employees ON employees;
CREATE TRIGGER tr_update_timestamp_employees
    BEFORE UPDATE ON employees
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

DROP TRIGGER IF EXISTS tr_update_timestamp_suppliers ON suppliers;
CREATE TRIGGER tr_update_timestamp_suppliers
    BEFORE UPDATE ON suppliers
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

DROP TRIGGER IF EXISTS tr_update_timestamp_categories ON product_categories;
CREATE TRIGGER tr_update_timestamp_categories
    BEFORE UPDATE ON product_categories
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

DROP TRIGGER IF EXISTS tr_update_timestamp_purchase_orders ON purchase_orders;
CREATE TRIGGER tr_update_timestamp_purchase_orders
    BEFORE UPDATE ON purchase_orders
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

DROP TRIGGER IF EXISTS tr_update_timestamp_warehouse_inventory ON warehouse_inventory;
CREATE TRIGGER tr_update_timestamp_warehouse_inventory
    BEFORE UPDATE ON warehouse_inventory
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

DROP TRIGGER IF EXISTS tr_update_timestamp_shelf_inventory ON shelf_inventory;
CREATE TRIGGER tr_update_timestamp_shelf_inventory
    BEFORE UPDATE ON shelf_inventory
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

DROP TRIGGER IF EXISTS tr_update_timestamp_shelf_layout ON shelf_layout;
CREATE TRIGGER tr_update_timestamp_shelf_layout
    BEFORE UPDATE ON shelf_layout
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

-- 7.2 Auto-set created_at timestamps for new records
DROP TRIGGER IF EXISTS tr_set_created_timestamp_products ON products;
CREATE TRIGGER tr_set_created_timestamp_products
    BEFORE INSERT ON products
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_customers ON customers;
CREATE TRIGGER tr_set_created_timestamp_customers
    BEFORE INSERT ON customers
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_employees ON employees;
CREATE TRIGGER tr_set_created_timestamp_employees
    BEFORE INSERT ON employees
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_suppliers ON suppliers;
CREATE TRIGGER tr_set_created_timestamp_suppliers
    BEFORE INSERT ON suppliers
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_categories ON product_categories;
CREATE TRIGGER tr_set_created_timestamp_categories
    BEFORE INSERT ON product_categories
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_positions ON positions;
CREATE TRIGGER tr_set_created_timestamp_positions
    BEFORE INSERT ON positions
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_membership_levels ON membership_levels;
CREATE TRIGGER tr_set_created_timestamp_membership_levels
    BEFORE INSERT ON membership_levels
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_discount_rules ON discount_rules;
CREATE TRIGGER tr_set_created_timestamp_discount_rules
    BEFORE INSERT ON discount_rules
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_display_shelves ON display_shelves;
CREATE TRIGGER tr_set_created_timestamp_display_shelves
    BEFORE INSERT ON display_shelves
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_warehouse ON warehouse;
CREATE TRIGGER tr_set_created_timestamp_warehouse
    BEFORE INSERT ON warehouse
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_purchase_orders ON purchase_orders;
CREATE TRIGGER tr_set_created_timestamp_purchase_orders
    BEFORE INSERT ON purchase_orders
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_purchase_order_details ON purchase_order_details;
CREATE TRIGGER tr_set_created_timestamp_purchase_order_details
    BEFORE INSERT ON purchase_order_details
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_sales_invoices ON sales_invoices;
CREATE TRIGGER tr_set_created_timestamp_sales_invoices
    BEFORE INSERT ON sales_invoices
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_sales_invoice_details ON sales_invoice_details;
CREATE TRIGGER tr_set_created_timestamp_sales_invoice_details
    BEFORE INSERT ON sales_invoice_details
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_stock_transfers ON stock_transfers;
CREATE TRIGGER tr_set_created_timestamp_stock_transfers
    BEFORE INSERT ON stock_transfers
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_employee_work_hours ON employee_work_hours;
CREATE TRIGGER tr_set_created_timestamp_employee_work_hours
    BEFORE INSERT ON employee_work_hours
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_warehouse_inventory ON warehouse_inventory;
CREATE TRIGGER tr_set_created_timestamp_warehouse_inventory
    BEFORE INSERT ON warehouse_inventory
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

DROP TRIGGER IF EXISTS tr_set_created_timestamp_shelf_layout ON shelf_layout;
CREATE TRIGGER tr_set_created_timestamp_shelf_layout
    BEFORE INSERT ON shelf_layout
    FOR EACH ROW
    EXECUTE FUNCTION set_created_timestamp();

-- ============================================================================
-- TRIGGER CREATION COMPLETE
-- ============================================================================

-- Log completion
DO $$
BEGIN
    RAISE NOTICE 'All supermarket database triggers have been created successfully!';
    RAISE NOTICE 'The following trigger categories are now active:';
    RAISE NOTICE '  ✓ Validation Triggers (price, capacity, category consistency)';
    RAISE NOTICE '  ✓ Inventory Management Triggers (stock transfers, sales deduction, expiry)';
    RAISE NOTICE '  ✓ Customer Management Triggers (spending, points, membership upgrades)';
    RAISE NOTICE '  ✓ Financial Calculation Triggers (invoice totals, discounts)';
    RAISE NOTICE '  ✓ Employee Management Triggers (work hours calculation)';
    RAISE NOTICE '  ✓ Pricing Management Triggers (expiry discounts)';
    RAISE NOTICE '  ✓ Audit Triggers (timestamps, created_at)';
END $$;
