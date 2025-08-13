-- =====================================================
-- STORED PROCEDURES & FUNCTIONS FOR SUPERMARKET SYSTEM
-- File: 02_functions.sql
-- Content: Business Logic Functions and Stored Procedures
-- =====================================================

SET search_path TO supermarket;

-- =====================================================
-- FUNCTION: Restock shelf from warehouse
-- =====================================================
CREATE OR REPLACE FUNCTION fn_restock_shelf(
    p_product_id INTEGER,
    p_shelf_id INTEGER,
    p_quantity INTEGER,
    p_employee_id INTEGER,
    p_batch_code VARCHAR DEFAULT NULL
)
RETURNS TABLE(
    success BOOLEAN,
    message TEXT,
    transferred_quantity INTEGER
) AS $$
DECLARE
    v_available_qty INTEGER;
    v_max_shelf_qty INTEGER;
    v_current_shelf_qty INTEGER;
    v_transfer_qty INTEGER;
    v_warehouse_id INTEGER := 1;
    v_transfer_code VARCHAR(30);
BEGIN
    -- Check available quantity in warehouse
    SELECT COALESCE(SUM(quantity), 0) INTO v_available_qty
    FROM warehouse_inventory
    WHERE warehouse_id = v_warehouse_id
      AND product_id = p_product_id
      AND (p_batch_code IS NULL OR batch_code = p_batch_code)
      AND quantity > 0;
    
    -- Check shelf capacity
    SELECT sl.max_quantity, COALESCE(si.current_quantity, 0)
    INTO v_max_shelf_qty, v_current_shelf_qty
    FROM shelf_layout sl
    LEFT JOIN shelf_inventory si ON sl.shelf_id = si.shelf_id AND sl.product_id = si.product_id
    WHERE sl.shelf_id = p_shelf_id AND sl.product_id = p_product_id;
    
    IF v_max_shelf_qty IS NULL THEN
        RETURN QUERY SELECT FALSE, 'Product not configured for this shelf', 0;
        RETURN;
    END IF;
    
    -- Calculate actual transfer quantity
    v_transfer_qty := LEAST(
        p_quantity,
        v_available_qty,
        v_max_shelf_qty - v_current_shelf_qty
    );
    
    IF v_transfer_qty <= 0 THEN
        RETURN QUERY SELECT FALSE, 'Cannot transfer: insufficient warehouse stock or shelf is full', 0;
        RETURN;
    END IF;
    
    -- Generate transfer code
    v_transfer_code := 'TRF' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS');
    
    -- Record the transfer
    INSERT INTO stock_transfers (
        transfer_code, product_id, from_warehouse_id, 
        to_shelf_id, quantity, employee_id, batch_code
    ) VALUES (
        v_transfer_code, p_product_id, v_warehouse_id,
        p_shelf_id, v_transfer_qty, p_employee_id, p_batch_code
    );
    
    -- Update warehouse inventory
    UPDATE warehouse_inventory
    SET quantity = quantity - v_transfer_qty
    WHERE warehouse_id = v_warehouse_id
      AND product_id = p_product_id
      AND (p_batch_code IS NULL OR batch_code = p_batch_code)
      AND quantity > 0;
    
    -- Update or insert shelf inventory
    INSERT INTO shelf_inventory (shelf_id, product_id, current_quantity)
    VALUES (p_shelf_id, p_product_id, v_transfer_qty)
    ON CONFLICT (shelf_id, product_id)
    DO UPDATE SET 
        current_quantity = shelf_inventory.current_quantity + v_transfer_qty,
        last_restocked = CURRENT_TIMESTAMP;
    
    RETURN QUERY SELECT TRUE, 'Transfer successful', v_transfer_qty;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCTION: Process sale transaction
-- =====================================================
CREATE OR REPLACE FUNCTION fn_process_sale(
    p_employee_id INTEGER,
    p_customer_id INTEGER DEFAULT NULL,
    p_payment_method VARCHAR DEFAULT 'CASH',
    p_items JSONB DEFAULT '[]'::JSONB
)
RETURNS TABLE(
    invoice_id INTEGER,
    invoice_no VARCHAR,
    total_amount DECIMAL,
    message TEXT
) AS $$
DECLARE
    v_invoice_id INTEGER;
    v_invoice_no VARCHAR(30);
    v_subtotal DECIMAL(12,2) := 0;
    v_discount DECIMAL(12,2) := 0;
    v_total DECIMAL(12,2) := 0;
    v_item JSONB;
    v_product_id INTEGER;
    v_quantity INTEGER;
    v_unit_price DECIMAL(12,2);
    v_available_qty INTEGER;
BEGIN
    -- Generate invoice number
    v_invoice_no := 'INV' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS');
    
    -- Validate all items have sufficient stock
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::INTEGER;
        v_quantity := (v_item->>'quantity')::INTEGER;
        
        SELECT SUM(si.current_quantity) INTO v_available_qty
        FROM shelf_inventory si
        WHERE si.product_id = v_product_id;
        
        IF v_available_qty IS NULL OR v_available_qty < v_quantity THEN
            RETURN QUERY SELECT 
                NULL::INTEGER, 
                NULL::VARCHAR, 
                NULL::DECIMAL, 
                'Insufficient stock for product_id: ' || v_product_id;
            RETURN;
        END IF;
    END LOOP;
    
    -- Create invoice
    INSERT INTO sales_invoices (
        invoice_no, customer_id, employee_id, 
        payment_method, subtotal, total_amount
    ) VALUES (
        v_invoice_no, p_customer_id, p_employee_id,
        p_payment_method, 0, 0
    ) RETURNING sales_invoices.invoice_id INTO v_invoice_id;
    
    -- Process each item
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::INTEGER;
        v_quantity := (v_item->>'quantity')::INTEGER;
        
        -- Get product price
        SELECT selling_price INTO v_unit_price
        FROM products WHERE product_id = v_product_id;
        
        -- Insert invoice detail
        INSERT INTO sales_invoice_details (
            invoice_id, product_id, quantity, 
            unit_price, subtotal
        ) VALUES (
            v_invoice_id, v_product_id, v_quantity,
            v_unit_price, v_unit_price * v_quantity
        );
        
        v_subtotal := v_subtotal + (v_unit_price * v_quantity);
    END LOOP;
    
    -- Apply customer discount if applicable
    IF p_customer_id IS NOT NULL THEN
        SELECT ml.discount_percentage INTO v_discount
        FROM customers c
        JOIN membership_levels ml ON c.membership_level_id = ml.level_id
        WHERE c.customer_id = p_customer_id;
        
        v_discount := COALESCE(v_discount, 0) * v_subtotal / 100;
    END IF;
    
    v_total := v_subtotal - v_discount;
    
    -- Update invoice totals
    UPDATE sales_invoices
    SET subtotal = v_subtotal,
        discount_amount = v_discount,
        total_amount = v_total
    WHERE sales_invoices.invoice_id = v_invoice_id;
    
    RETURN QUERY SELECT v_invoice_id, v_invoice_no, v_total, 'Sale processed successfully';
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCTION: Get products needing restock
-- =====================================================
CREATE OR REPLACE FUNCTION fn_get_low_stock_products()
RETURNS TABLE(
    product_id INTEGER,
    product_code VARCHAR,
    product_name VARCHAR,
    category_name VARCHAR,
    shelf_quantity INTEGER,
    warehouse_quantity INTEGER,
    threshold INTEGER,
    status VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.product_id,
        p.product_code,
        p.product_name,
        pc.category_name,
        COALESCE(SUM(si.current_quantity), 0)::INTEGER as shelf_quantity,
        COALESCE((SELECT SUM(quantity) FROM warehouse_inventory wi 
                  WHERE wi.product_id = p.product_id), 0)::INTEGER as warehouse_quantity,
        p.low_stock_threshold,
        CASE 
            WHEN COALESCE(SUM(si.current_quantity), 0) = 0 THEN 'OUT_OF_STOCK'
            WHEN COALESCE(SUM(si.current_quantity), 0) < p.low_stock_threshold THEN 'LOW_STOCK'
            ELSE 'OK'
        END as status
    FROM products p
    JOIN product_categories pc ON p.category_id = pc.category_id
    LEFT JOIN shelf_inventory si ON p.product_id = si.product_id
    GROUP BY p.product_id, p.product_code, p.product_name, 
             pc.category_name, p.low_stock_threshold
    HAVING COALESCE(SUM(si.current_quantity), 0) < p.low_stock_threshold
    ORDER BY COALESCE(SUM(si.current_quantity), 0), p.product_name;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCTION: Apply discount for near-expiry products
-- =====================================================
CREATE OR REPLACE FUNCTION fn_apply_expiry_discounts()
RETURNS TABLE(
    product_id INTEGER,
    product_name VARCHAR,
    original_price DECIMAL,
    discounted_price DECIMAL,
    discount_percentage DECIMAL,
    days_until_expiry INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH expiry_products AS (
        SELECT 
            p.product_id,
            p.product_name,
            p.selling_price,
            p.category_id,
            MIN(wi.expiry_date - CURRENT_DATE) as days_left
        FROM products p
        JOIN warehouse_inventory wi ON p.product_id = wi.product_id
        WHERE wi.expiry_date IS NOT NULL
          AND wi.quantity > 0
        GROUP BY p.product_id, p.product_name, p.selling_price, p.category_id
    )
    SELECT 
        ep.product_id,
        ep.product_name,
        ep.selling_price as original_price,
        ep.selling_price * (1 - dr.discount_percentage/100) as discounted_price,
        dr.discount_percentage,
        ep.days_left::INTEGER as days_until_expiry
    FROM expiry_products ep
    JOIN discount_rules dr ON ep.category_id = dr.category_id
    WHERE ep.days_left <= dr.days_before_expiry
      AND dr.is_active = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM discount_rules dr2
          WHERE dr2.category_id = ep.category_id
            AND dr2.days_before_expiry < dr.days_before_expiry
            AND ep.days_left <= dr2.days_before_expiry
            AND dr2.is_active = TRUE
      )
    ORDER BY ep.days_left, ep.product_name;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCTION: Calculate employee salary
-- =====================================================
CREATE OR REPLACE FUNCTION fn_calculate_employee_salary(
    p_employee_id INTEGER,
    p_month DATE
)
RETURNS TABLE(
    employee_name VARCHAR,
    position_name VARCHAR,
    base_salary DECIMAL,
    total_hours DECIMAL,
    hourly_rate DECIMAL,
    hourly_payment DECIMAL,
    total_salary DECIMAL,
    sales_bonus DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.full_name,
        p.position_name,
        p.base_salary,
        COALESCE(SUM(ewh.total_hours), 0) as total_hours,
        p.hourly_rate,
        COALESCE(SUM(ewh.total_hours), 0) * p.hourly_rate as hourly_payment,
        p.base_salary + (COALESCE(SUM(ewh.total_hours), 0) * p.hourly_rate) as total_salary,
        COALESCE((
            SELECT SUM(si.total_amount) * 0.001
            FROM sales_invoices si
            WHERE si.employee_id = e.employee_id
              AND DATE_TRUNC('month', si.invoice_date) = DATE_TRUNC('month', p_month)
        ), 0) as sales_bonus
    FROM employees e
    JOIN positions p ON e.position_id = p.position_id
    LEFT JOIN employee_work_hours ewh ON e.employee_id = ewh.employee_id
        AND DATE_TRUNC('month', ewh.work_date) = DATE_TRUNC('month', p_month)
    WHERE e.employee_id = p_employee_id
    GROUP BY e.employee_id, e.full_name, p.position_name, 
             p.base_salary, p.hourly_rate;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCTION: Get top customers
-- =====================================================
CREATE OR REPLACE FUNCTION fn_get_top_customers(
    p_limit INTEGER DEFAULT 10,
    p_month DATE DEFAULT NULL
)
RETURNS TABLE(
    rank INTEGER,
    customer_id INTEGER,
    customer_name VARCHAR,
    membership_level VARCHAR,
    total_spending DECIMAL,
    transaction_count BIGINT,
    avg_transaction DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ROW_NUMBER() OVER (ORDER BY SUM(si.total_amount) DESC)::INTEGER as rank,
        c.customer_id,
        c.full_name,
        ml.level_name,
        SUM(si.total_amount) as total_spending,
        COUNT(si.invoice_id) as transaction_count,
        AVG(si.total_amount) as avg_transaction
    FROM customers c
    LEFT JOIN membership_levels ml ON c.membership_level_id = ml.level_id
    JOIN sales_invoices si ON c.customer_id = si.customer_id
    WHERE p_month IS NULL 
       OR DATE_TRUNC('month', si.invoice_date) = DATE_TRUNC('month', p_month)
    GROUP BY c.customer_id, c.full_name, ml.level_name
    ORDER BY total_spending DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCTION: Get supplier ranking
-- =====================================================
CREATE OR REPLACE FUNCTION fn_get_supplier_ranking()
RETURNS TABLE(
    rank INTEGER,
    supplier_id INTEGER,
    supplier_name VARCHAR,
    product_count BIGINT,
    total_revenue DECIMAL,
    avg_product_revenue DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ROW_NUMBER() OVER (ORDER BY SUM(sid.subtotal) DESC)::INTEGER as rank,
        s.supplier_id,
        s.supplier_name,
        COUNT(DISTINCT p.product_id) as product_count,
        COALESCE(SUM(sid.subtotal), 0) as total_revenue,
        COALESCE(AVG(sid.subtotal), 0) as avg_product_revenue
    FROM suppliers s
    JOIN products p ON s.supplier_id = p.supplier_id
    LEFT JOIN sales_invoice_details sid ON p.product_id = sid.product_id
    GROUP BY s.supplier_id, s.supplier_name
    ORDER BY total_revenue DESC;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCTION: Daily sales report
-- =====================================================
CREATE OR REPLACE FUNCTION fn_daily_sales_report(
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE(
    report_date DATE,
    total_invoices BIGINT,
    total_items_sold BIGINT,
    total_revenue DECIMAL,
    total_discount DECIMAL,
    net_revenue DECIMAL,
    top_product VARCHAR,
    top_employee VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p_date,
        COUNT(DISTINCT si.invoice_id) as total_invoices,
        COALESCE(SUM(sid.quantity), 0) as total_items_sold,
        COALESCE(SUM(si.subtotal), 0) as total_revenue,
        COALESCE(SUM(si.discount_amount), 0) as total_discount,
        COALESCE(SUM(si.total_amount), 0) as net_revenue,
        (
            SELECT p.product_name 
            FROM products p
            JOIN sales_invoice_details sid2 ON p.product_id = sid2.product_id
            JOIN sales_invoices si2 ON sid2.invoice_id = si2.invoice_id
            WHERE DATE(si2.invoice_date) = p_date
            GROUP BY p.product_name
            ORDER BY SUM(sid2.quantity) DESC
            LIMIT 1
        ) as top_product,
        (
            SELECT e.full_name
            FROM employees e
            JOIN sales_invoices si3 ON e.employee_id = si3.employee_id
            WHERE DATE(si3.invoice_date) = p_date
            GROUP BY e.full_name
            ORDER BY SUM(si3.total_amount) DESC
            LIMIT 1
        ) as top_employee
    FROM sales_invoices si
    LEFT JOIN sales_invoice_details sid ON si.invoice_id = sid.invoice_id
    WHERE DATE(si.invoice_date) = p_date;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- END OF FUNCTIONS AND PROCEDURES
-- =====================================================