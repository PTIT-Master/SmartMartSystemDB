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
-- TEST 4: SHELF CATEGORY CONSISTENCY VALIDATION
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 4: Shelf Category Consistency Validation ===';
END $$;

-- Test 4a: Valid category match (should succeed)
DO $$
DECLARE
    test_product_id INTEGER;
    test_shelf_id INTEGER;
    beverages_category_id INTEGER;
BEGIN
    -- Get beverages category ID
    SELECT category_id INTO beverages_category_id 
    FROM product_categories 
    WHERE category_name = 'Beverages' 
    LIMIT 1;
    
    -- Create a test product in beverages category
    INSERT INTO products (product_code, product_name, category_id, supplier_id, 
                         unit, import_price, selling_price, barcode)
    VALUES ('BEVTEST', 'Test Beverage', beverages_category_id, 1, 'bottle', 1.00, 2.00, 'BEVTEST')
    RETURNING product_id INTO test_product_id;
    
    -- Find a shelf designated for beverages category
    SELECT shelf_id INTO test_shelf_id 
    FROM display_shelves 
    WHERE category_id = beverages_category_id 
    LIMIT 1;
    
    -- This should succeed - product and shelf have matching categories
    INSERT INTO shelf_layout (shelf_id, product_id, position_code, max_quantity)
    VALUES (test_shelf_id, test_product_id, 'A1', 100);
    
    RAISE NOTICE '✅ Test 4a PASSED: Product correctly assigned to matching category shelf';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Test 4a FAILED: Valid category assignment rejected - %', SQLERRM;
END $$;

-- Test 4b: Invalid category mismatch (should fail)
DO $$
DECLARE
    test_product_id INTEGER;
    wrong_shelf_id INTEGER;
    beverages_category_id INTEGER;
    dairy_category_id INTEGER;
BEGIN
    -- Get category IDs
    SELECT category_id INTO beverages_category_id 
    FROM product_categories 
    WHERE category_name = 'Beverages' 
    LIMIT 1;
    
    SELECT category_id INTO dairy_category_id 
    FROM product_categories 
    WHERE category_name = 'Dairy Products' 
    LIMIT 1;
    
    -- Get the beverage product from previous test
    SELECT product_id INTO test_product_id 
    FROM products 
    WHERE product_code = 'BEVTEST';
    
    -- Find a shelf designated for dairy (different category)
    SELECT shelf_id INTO wrong_shelf_id 
    FROM display_shelves 
    WHERE category_id = dairy_category_id 
    LIMIT 1;
    
    -- This should fail - beverage product on dairy shelf
    INSERT INTO shelf_layout (shelf_id, product_id, position_code, max_quantity)
    VALUES (wrong_shelf_id, test_product_id, 'B1', 50);
    
    RAISE NOTICE '❌ Test 4b FAILED: Category mismatch should have been rejected';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '✅ Test 4b PASSED: Category validation working - %', SQLERRM;
END $$;

-- Test 4c: Shelf inventory category validation
DO $$
DECLARE
    test_product_id INTEGER;
    wrong_shelf_id INTEGER;
    dairy_category_id INTEGER;
BEGIN
    -- Get dairy category and shelf
    SELECT category_id INTO dairy_category_id 
    FROM product_categories 
    WHERE category_name = 'Dairy Products' 
    LIMIT 1;
    
    SELECT shelf_id INTO wrong_shelf_id 
    FROM display_shelves 
    WHERE category_id = dairy_category_id 
    LIMIT 1;
    
    -- Get beverage product (wrong category)
    SELECT product_id INTO test_product_id 
    FROM products 
    WHERE product_code = 'BEVTEST';
    
    -- This should fail - trying to add beverage inventory to dairy shelf
    INSERT INTO shelf_inventory (shelf_id, product_id, current_quantity)
    VALUES (wrong_shelf_id, test_product_id, 25);
    
    RAISE NOTICE '❌ Test 4c FAILED: Shelf inventory category mismatch should have been rejected';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '✅ Test 4c PASSED: Shelf inventory category validation working - %', SQLERRM;
END $$;

-- ============================================================================
-- TEST 5: WORK HOURS CALCULATION
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 5: Work Hours Calculation ===';
END $$;

-- Test 5: Work hours calculation
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
        RAISE NOTICE '✅ Test 5 PASSED: Work hours calculated correctly (% hours)', calculated_hours;
    ELSE
        RAISE NOTICE '❌ Test 5 FAILED: Work hours incorrect (% ≠ %)', calculated_hours, expected_hours;
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Test 5 FAILED: %', SQLERRM;
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
    DELETE FROM shelf_layout WHERE product_id IN (
        SELECT product_id FROM products WHERE product_code = 'BEVTEST'
    );
    DELETE FROM products WHERE product_code IN ('TEST001', 'TEST002', 'TS001', 'BEVTEST');
    
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
