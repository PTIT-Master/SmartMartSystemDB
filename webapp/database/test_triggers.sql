-- ============================================================================
-- TRIGGER TESTING SCRIPT
-- ============================================================================
-- This script demonstrates and tests the database triggers
-- Run this after setting up the database with sample data
-- ============================================================================

SET search_path TO supermarket;

-- ============================================================================
-- TEST 1: PRODUCT PRICE VALIDATION
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '=== TEST 1: Product Price Validation ===';
END $$;

-- Test 1a: Valid product (should succeed)
DO $$
BEGIN
    INSERT INTO products (product_code, product_name, category_id, supplier_id, 
                         unit, import_price, selling_price, shelf_life_days, barcode)
    VALUES ('TEST001', 'Test Product 1', 1, 1, 'piece', 10.00, 15.00, 30, 'TEST001');
    
    RAISE NOTICE '✅ Test 1a PASSED: Valid price product created successfully';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Test 1a FAILED: %', SQLERRM;
END $$;

-- Test 1b: Invalid product (should fail)
DO $$
BEGIN
    INSERT INTO products (product_code, product_name, category_id, supplier_id, 
                         unit, import_price, selling_price, shelf_life_days, barcode)
    VALUES ('TEST002', 'Test Product 2', 1, 1, 'piece', 15.00, 10.00, 30, 'TEST002');
    
    RAISE NOTICE '❌ Test 1b FAILED: Invalid price product should not be created';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '✅ Test 1b PASSED: Price validation working - %', SQLERRM;
END $$;

-- ============================================================================
-- TEST 2: TIMESTAMP TRIGGERS
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 2: Timestamp Triggers ===';
END $$;

-- Test 2: Check if timestamps are set automatically
DO $$
DECLARE
    test_created_at TIMESTAMP;
    test_updated_at TIMESTAMP;
BEGIN
    -- Insert a product and check created_at
    INSERT INTO products (product_code, product_name, category_id, supplier_id, 
                         unit, import_price, selling_price, barcode)
    VALUES ('TS001', 'Timestamp Test', 1, 1, 'piece', 5.00, 8.00, 'TS001')
    RETURNING created_at INTO test_created_at;
    
    IF test_created_at IS NOT NULL THEN
        RAISE NOTICE '✅ Test 2a PASSED: created_at timestamp set automatically';
    ELSE
        RAISE NOTICE '❌ Test 2a FAILED: created_at timestamp not set';
    END IF;
    
    -- Update the product and check updated_at
    UPDATE products 
    SET product_name = 'Updated Timestamp Test'
    WHERE product_code = 'TS001'
    RETURNING updated_at INTO test_updated_at;
    
    IF test_updated_at IS NOT NULL THEN
        RAISE NOTICE '✅ Test 2b PASSED: updated_at timestamp set automatically';
    ELSE
        RAISE NOTICE '❌ Test 2b FAILED: updated_at timestamp not set';
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Test 2 FAILED: %', SQLERRM;
END $$;

-- ============================================================================
-- TEST 3: INVOICE CALCULATION TRIGGERS
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 3: Invoice Calculation Triggers ===';
END $$;

-- Test 3: Invoice detail subtotal calculation
DO $$
DECLARE
    calculated_subtotal NUMERIC(12,2);
    calculated_discount NUMERIC(12,2);
    expected_subtotal NUMERIC(12,2);
    expected_discount NUMERIC(12,2);
BEGIN
    -- Create a test invoice
    INSERT INTO sales_invoices (invoice_no, employee_id, payment_method)
    VALUES ('INV-TEST', 1, 'CASH');
    
    -- Add invoice detail with 10% discount
    INSERT INTO sales_invoice_details (invoice_id, product_id, quantity, unit_price, discount_percentage)
    SELECT 
        si.invoice_id,
        p.product_id,
        2,  -- quantity
        15.00,  -- unit_price
        10.0    -- 10% discount
    FROM sales_invoices si, products p
    WHERE si.invoice_no = 'INV-TEST' 
    AND p.product_code = 'TEST001'
    LIMIT 1;
    
    -- Check calculated values
    SELECT subtotal, discount_amount 
    INTO calculated_subtotal, calculated_discount
    FROM sales_invoice_details sid
    JOIN sales_invoices si ON sid.invoice_id = si.invoice_id
    WHERE si.invoice_no = 'INV-TEST';
    
    expected_discount := 15.00 * 2 * 0.10;  -- 3.00
    expected_subtotal := (15.00 * 2) - expected_discount;  -- 27.00
    
    IF calculated_discount = expected_discount THEN
        RAISE NOTICE '✅ Test 3a PASSED: Discount calculation correct (% = %)', calculated_discount, expected_discount;
    ELSE
        RAISE NOTICE '❌ Test 3a FAILED: Discount calculation incorrect (% ≠ %)', calculated_discount, expected_discount;
    END IF;
    
    IF calculated_subtotal = expected_subtotal THEN
        RAISE NOTICE '✅ Test 3b PASSED: Subtotal calculation correct (% = %)', calculated_subtotal, expected_subtotal;
    ELSE
        RAISE NOTICE '❌ Test 3b FAILED: Subtotal calculation incorrect (% ≠ %)', calculated_subtotal, expected_subtotal;
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Test 3 FAILED: %', SQLERRM;
END $$;

-- ============================================================================
-- TEST 4: WORK HOURS CALCULATION
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 4: Work Hours Calculation ===';
END $$;

-- Test 4: Work hours calculation
DO $$
DECLARE
    calculated_hours NUMERIC(5,2);
    expected_hours NUMERIC(5,2) := 8.00;  -- 8 hour shift
BEGIN
    -- Add work hours record
    INSERT INTO employee_work_hours (employee_id, work_date, check_in_time, check_out_time)
    VALUES (
        1, 
        CURRENT_DATE, 
        CURRENT_DATE + TIME '09:00:00',  -- 9 AM
        CURRENT_DATE + TIME '17:00:00'   -- 5 PM
    )
    RETURNING total_hours INTO calculated_hours;
    
    IF ABS(calculated_hours - expected_hours) < 0.01 THEN
        RAISE NOTICE '✅ Test 4 PASSED: Work hours calculated correctly (% hours)', calculated_hours;
    ELSE
        RAISE NOTICE '❌ Test 4 FAILED: Work hours incorrect (% ≠ %)', calculated_hours, expected_hours;
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Test 4 FAILED: %', SQLERRM;
END $$;

-- ============================================================================
-- CLEANUP TEST DATA
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== CLEANING UP TEST DATA ===';
    
    -- Delete test data
    DELETE FROM sales_invoice_details WHERE invoice_id IN (
        SELECT invoice_id FROM sales_invoices WHERE invoice_no = 'INV-TEST'
    );
    DELETE FROM sales_invoices WHERE invoice_no = 'INV-TEST';
    DELETE FROM employee_work_hours WHERE employee_id = 1 AND work_date = CURRENT_DATE;
    DELETE FROM products WHERE product_code IN ('TEST001', 'TEST002', 'TS001');
    
    RAISE NOTICE '✅ Test data cleaned up successfully';
END $$;

-- ============================================================================
-- SUMMARY
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TRIGGER TESTING COMPLETED ===';
    RAISE NOTICE 'Review the test results above to verify trigger functionality.';
    RAISE NOTICE 'All triggers should be working correctly if tests passed.';
    RAISE NOTICE '';
    RAISE NOTICE 'To verify all triggers are installed, run:';
    RAISE NOTICE 'SELECT schemaname, tablename, triggername FROM pg_triggers WHERE schemaname = ''supermarket'';';
END $$;
