-- =====================================================
-- VIEWS
-- =====================================================

-- View 1: Product inventory summary (both warehouse and shelf)
CREATE OR REPLACE VIEW supermarket.v_product_inventory_summary AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    pc.category_name,
    s.supplier_name,
    COALESCE(wi.warehouse_qty, 0) AS warehouse_quantity,
    COALESCE(si.shelf_qty, 0) AS shelf_quantity,
    COALESCE(wi.warehouse_qty, 0) + COALESCE(si.shelf_qty, 0) AS total_quantity,
    p.low_stock_threshold,
    CASE 
        WHEN COALESCE(si.shelf_qty, 0) <= p.low_stock_threshold THEN 'Low on shelf'
        WHEN COALESCE(wi.warehouse_qty, 0) = 0 AND COALESCE(si.shelf_qty, 0) > 0 THEN 'Out in warehouse'
        WHEN COALESCE(wi.warehouse_qty, 0) + COALESCE(si.shelf_qty, 0) = 0 THEN 'Out of stock'
        ELSE 'Available'
    END AS stock_status
FROM supermarket.products p
LEFT JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
LEFT JOIN supermarket.suppliers s ON p.supplier_id = s.supplier_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS warehouse_qty
    FROM supermarket.warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) AS shelf_qty
    FROM supermarket.shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id
WHERE p.is_active = true;

-- View 2: Expired products view
CREATE OR REPLACE VIEW supermarket.v_expired_products AS
SELECT 
    wi.inventory_id,
    wi.batch_code,
    p.product_code,
    p.product_name,
    pc.category_name,
    wi.quantity,
    wi.import_date,
    wi.expiry_date,
    wi.expiry_date - CURRENT_DATE AS days_until_expiry,
    wi.import_price,
    p.selling_price,
    w.warehouse_name,
    CASE 
        WHEN wi.expiry_date < CURRENT_DATE THEN 'Expired'
        WHEN wi.expiry_date - CURRENT_DATE <= 3 THEN 'Expiring soon'
        ELSE 'Valid'
    END AS expiry_status
FROM supermarket.warehouse_inventory wi
INNER JOIN supermarket.products p ON wi.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.warehouse w ON wi.warehouse_id = w.warehouse_id
WHERE wi.expiry_date IS NOT NULL
ORDER BY wi.expiry_date ASC;

-- View 3: Sales revenue by product
CREATE OR REPLACE VIEW supermarket.v_product_revenue AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    pc.category_name,
    COUNT(DISTINCT si.invoice_id) AS total_transactions,
    SUM(sid.quantity) AS total_quantity_sold,
    SUM(sid.subtotal) AS total_revenue,
    AVG(sid.subtotal) AS avg_revenue_per_transaction,
    DATE_TRUNC('month', si.invoice_date) AS month_year
FROM supermarket.sales_invoice_details sid
INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
INNER JOIN supermarket.products p ON sid.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
GROUP BY p.product_id, p.product_code, p.product_name, pc.category_name, 
         DATE_TRUNC('month', si.invoice_date);

-- View 4: Supplier performance
CREATE OR REPLACE VIEW supermarket.v_supplier_performance AS
SELECT 
    s.supplier_id,
    s.supplier_code,
    s.supplier_name,
    COUNT(DISTINCT p.product_id) AS total_products,
    COUNT(DISTINCT po.order_id) AS total_orders,
    SUM(po.total_amount) AS total_purchase_amount,
    SUM(revenue.total_revenue) AS total_sales_revenue,
    SUM(revenue.total_revenue) - SUM(po.total_amount) AS profit_margin
FROM supermarket.suppliers s
LEFT JOIN supermarket.products p ON s.supplier_id = p.supplier_id
LEFT JOIN supermarket.purchase_orders po ON s.supplier_id = po.supplier_id
LEFT JOIN (
    SELECT 
        p.supplier_id,
        SUM(sid.subtotal) AS total_revenue
    FROM supermarket.sales_invoice_details sid
    INNER JOIN supermarket.products p ON sid.product_id = p.product_id
    GROUP BY p.supplier_id
) revenue ON s.supplier_id = revenue.supplier_id
WHERE s.is_active = true
GROUP BY s.supplier_id, s.supplier_code, s.supplier_name;

-- View 5: Customer purchase history
CREATE OR REPLACE VIEW supermarket.v_customer_purchase_history AS
SELECT 
    c.customer_id,
    c.customer_code,
    c.full_name,
    c.phone,
    ml.level_name AS membership_level,
    c.total_spending,
    c.loyalty_points,
    COUNT(DISTINCT si.invoice_id) AS total_purchases,
    AVG(si.total_amount) AS avg_purchase_amount,
    MAX(si.invoice_date) AS last_purchase_date
FROM supermarket.customers c
LEFT JOIN supermarket.membership_levels ml ON c.membership_level_id = ml.level_id
LEFT JOIN supermarket.sales_invoices si ON c.customer_id = si.customer_id
GROUP BY c.customer_id, c.customer_code, c.full_name, c.phone, 
         ml.level_name, c.total_spending, c.loyalty_points;

-- View 6: Low stock alert view
CREATE OR REPLACE VIEW supermarket.v_low_stock_alert AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    pc.category_name,
    si.shelf_id,
    ds.shelf_code,
    ds.shelf_name,
    si.current_quantity AS shelf_quantity,
    p.low_stock_threshold,
    wi.warehouse_quantity,
    sl.max_quantity AS shelf_max_capacity,
    CASE 
        WHEN si.current_quantity = 0 THEN 'Out of stock on shelf'
        WHEN si.current_quantity <= p.low_stock_threshold THEN 'Low stock on shelf'
        ELSE 'Sufficient'
    END AS alert_type
FROM supermarket.shelf_inventory si
INNER JOIN supermarket.products p ON si.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
LEFT JOIN supermarket.shelf_layout sl ON si.shelf_id = sl.shelf_id AND si.product_id = sl.product_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS warehouse_quantity
    FROM supermarket.warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
WHERE si.current_quantity <= p.low_stock_threshold
   AND COALESCE(wi.warehouse_quantity, 0) > 0;

-- =====================================================
-- STORED PROCEDURES
-- =====================================================

-- Procedure 1: Process stock replenishment from warehouse to shelf
CREATE OR REPLACE PROCEDURE supermarket.sp_replenish_shelf_stock(
    p_product_id BIGINT,
    p_shelf_id BIGINT,
    p_quantity BIGINT,
    p_employee_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_warehouse_id BIGINT := 1; -- Default warehouse
    v_available_qty BIGINT;
    v_batch_code VARCHAR(50);
    v_expiry_date DATE;
    v_import_price NUMERIC(12,2);
    v_selling_price NUMERIC(12,2);
    v_transfer_code VARCHAR(30);
BEGIN
    -- Get available quantity in warehouse
    SELECT SUM(quantity) INTO v_available_qty
    FROM supermarket.warehouse_inventory
    WHERE product_id = p_product_id;
    
    IF v_available_qty IS NULL OR v_available_qty < p_quantity THEN
        RAISE EXCEPTION 'Insufficient warehouse stock. Available: %, Requested: %', 
                        COALESCE(v_available_qty, 0), p_quantity;
    END IF;
    
    -- Get batch info (FIFO - oldest batch first)
    SELECT batch_code, expiry_date, import_price
    INTO v_batch_code, v_expiry_date, v_import_price
    FROM supermarket.warehouse_inventory
    WHERE product_id = p_product_id AND quantity >= p_quantity
    ORDER BY import_date ASC, expiry_date ASC
    LIMIT 1;
    
    -- Get current selling price
    SELECT selling_price INTO v_selling_price
    FROM supermarket.products
    WHERE product_id = p_product_id;
    
    -- Generate transfer code
    v_transfer_code := 'TRF-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || 
                       LPAD(NEXTVAL('supermarket.stock_transfers_transfer_id_seq')::TEXT, 6, '0');
    
    -- Create stock transfer record
    INSERT INTO supermarket.stock_transfers (
        transfer_code, product_id, from_warehouse_id, to_shelf_id,
        quantity, employee_id, batch_code, expiry_date,
        import_price, selling_price
    ) VALUES (
        v_transfer_code, p_product_id, v_warehouse_id, p_shelf_id,
        p_quantity, p_employee_id, v_batch_code, v_expiry_date,
        v_import_price, v_selling_price
    );
    
    RAISE NOTICE 'Stock transfer completed. Transfer code: %', v_transfer_code;
END;
$$;

-- Procedure 2: Process sale transaction
CREATE OR REPLACE PROCEDURE supermarket.sp_process_sale(
    p_customer_id BIGINT,
    p_employee_id BIGINT,
    p_payment_method VARCHAR(20),
    p_product_list JSON, -- JSON array of {product_id, quantity, discount_percentage}
    p_points_used BIGINT DEFAULT 0
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_invoice_no VARCHAR(30);
    v_invoice_id BIGINT;
    v_product JSON;
    v_unit_price NUMERIC(12,2);
BEGIN
    -- Generate invoice number
    v_invoice_no := 'INV-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || 
                    LPAD(NEXTVAL('supermarket.sales_invoices_invoice_id_seq')::TEXT, 6, '0');
    
    -- Create invoice header
    INSERT INTO supermarket.sales_invoices (
        invoice_no, customer_id, employee_id, payment_method, points_used
    ) VALUES (
        v_invoice_no, p_customer_id, p_employee_id, p_payment_method, p_points_used
    ) RETURNING invoice_id INTO v_invoice_id;
    
    -- Process each product
    FOR v_product IN SELECT * FROM json_array_elements(p_product_list)
    LOOP
        -- Get current selling price
        SELECT selling_price INTO v_unit_price
        FROM supermarket.products
        WHERE product_id = (v_product->>'product_id')::BIGINT;
        
        -- Insert invoice detail
        INSERT INTO supermarket.sales_invoice_details (
            invoice_id, product_id, quantity, unit_price, discount_percentage
        ) VALUES (
            v_invoice_id,
            (v_product->>'product_id')::BIGINT,
            (v_product->>'quantity')::BIGINT,
            v_unit_price,
            COALESCE((v_product->>'discount_percentage')::NUMERIC, 0)
        );
    END LOOP;
    
    RAISE NOTICE 'Sale processed successfully. Invoice: %', v_invoice_no;
END;
$$;

-- Procedure 3: Generate monthly sales report
CREATE OR REPLACE PROCEDURE supermarket.sp_generate_monthly_sales_report(
    p_month INTEGER,
    p_year INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_total_revenue NUMERIC(12,2);
    v_total_transactions INTEGER;
    v_total_customers INTEGER;
BEGIN
    v_start_date := DATE(p_year || '-' || LPAD(p_month::TEXT, 2, '0') || '-01');
    v_end_date := (v_start_date + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
    
    -- Create temporary table for report
    CREATE TEMP TABLE IF NOT EXISTS monthly_sales_report (
        report_date DATE,
        category_name VARCHAR(100),
        product_name VARCHAR(200),
        quantity_sold BIGINT,
        revenue NUMERIC(12,2),
        avg_discount NUMERIC(5,2)
    );
    
    -- Insert report data
    INSERT INTO monthly_sales_report
    SELECT 
        si.invoice_date::DATE,
        pc.category_name,
        p.product_name,
        SUM(sid.quantity),
        SUM(sid.subtotal),
        AVG(sid.discount_percentage)
    FROM supermarket.sales_invoice_details sid
    INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
    INNER JOIN supermarket.products p ON sid.product_id = p.product_id
    INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
    WHERE si.invoice_date >= v_start_date 
      AND si.invoice_date <= v_end_date
    GROUP BY si.invoice_date::DATE, pc.category_name, p.product_name;
    
    -- Calculate totals
    SELECT 
        SUM(revenue),
        COUNT(DISTINCT report_date),
        COUNT(DISTINCT product_name)
    INTO v_total_revenue, v_total_transactions, v_total_customers
    FROM monthly_sales_report;
    
    RAISE NOTICE 'Monthly report for %/% generated. Total revenue: %', 
                 p_month, p_year, v_total_revenue;
END;
$$;

-- Procedure 4: Check and remove expired products
CREATE OR REPLACE PROCEDURE supermarket.sp_remove_expired_products()
LANGUAGE plpgsql
AS $$
DECLARE
    v_expired_count INTEGER := 0;
    v_record RECORD;
BEGIN
    -- Find and process expired products in warehouse
    FOR v_record IN 
        SELECT inventory_id, product_id, batch_code, quantity, expiry_date
        FROM supermarket.warehouse_inventory
        WHERE expiry_date < CURRENT_DATE
    LOOP
        -- Log the removal (you might want to insert into an audit table)
        RAISE NOTICE 'Removing expired batch: % (Product: %, Qty: %)', 
                     v_record.batch_code, v_record.product_id, v_record.quantity;
        
        -- Remove from inventory
        DELETE FROM supermarket.warehouse_inventory 
        WHERE inventory_id = v_record.inventory_id;
        
        v_expired_count := v_expired_count + 1;
    END LOOP;
    
    -- Also check shelf inventory
    UPDATE supermarket.shelf_batch_inventory
    SET quantity = 0, is_near_expiry = true
    WHERE expiry_date < CURRENT_DATE;
    
    RAISE NOTICE 'Expired products removal completed. Total removed: % batches', v_expired_count;
END;
$$;

-- Procedure 5: Calculate employee salary
CREATE OR REPLACE PROCEDURE supermarket.sp_calculate_employee_salary(
    p_employee_id BIGINT,
    p_month INTEGER,
    p_year INTEGER,
    OUT p_base_salary NUMERIC(12,2),
    OUT p_hourly_salary NUMERIC(12,2),
    OUT p_total_salary NUMERIC(12,2)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_position_id BIGINT;
    v_total_hours NUMERIC(10,2);
    v_hourly_rate NUMERIC(10,2);
BEGIN
    -- Get employee position and rates
    SELECT e.position_id, p.base_salary, p.hourly_rate
    INTO v_position_id, p_base_salary, v_hourly_rate
    FROM supermarket.employees e
    INNER JOIN supermarket.positions p ON e.position_id = p.position_id
    WHERE e.employee_id = p_employee_id;
    
    -- Calculate total work hours for the month
    SELECT COALESCE(SUM(total_hours), 0)
    INTO v_total_hours
    FROM supermarket.employee_work_hours
    WHERE employee_id = p_employee_id
      AND EXTRACT(MONTH FROM work_date) = p_month
      AND EXTRACT(YEAR FROM work_date) = p_year;
    
    -- Calculate hourly salary
    p_hourly_salary := v_total_hours * v_hourly_rate;
    
    -- Calculate total salary
    p_total_salary := p_base_salary + p_hourly_salary;
    
    RAISE NOTICE 'Salary calculated for employee %: Base=%, Hourly=%, Total=%', 
                 p_employee_id, p_base_salary, p_hourly_salary, p_total_salary;
END;
$$;

-- =====================================================
-- USEFUL QUERIES
-- =====================================================

-- Query 1: Products by category sorted by shelf quantity
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    COALESCE(si.current_quantity, 0) AS shelf_quantity,
    p.selling_price
FROM supermarket.products p
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
LEFT JOIN supermarket.shelf_inventory si ON p.product_id = si.product_id
WHERE pc.category_id = 1 -- Replace with desired category_id
ORDER BY shelf_quantity ASC;

-- Query 2: Low stock on shelf but available in warehouse
SELECT 
    p.product_code,
    p.product_name,
    si.current_quantity AS shelf_qty,
    p.low_stock_threshold,
    wi.warehouse_qty
FROM supermarket.shelf_inventory si
INNER JOIN supermarket.products p ON si.product_id = p.product_id
INNER JOIN (
    SELECT product_id, SUM(quantity) AS warehouse_qty
    FROM supermarket.warehouse_inventory
    GROUP BY product_id
    HAVING SUM(quantity) > 0
) wi ON p.product_id = wi.product_id
WHERE si.current_quantity <= p.low_stock_threshold;

-- Query 3: Out of stock in warehouse but available on shelf
SELECT 
    p.product_code,
    p.product_name,
    si.shelf_qty,
    'Out in warehouse' AS status
FROM (
    SELECT product_id, SUM(current_quantity) AS shelf_qty
    FROM supermarket.shelf_inventory
    GROUP BY product_id
    HAVING SUM(current_quantity) > 0
) si
INNER JOIN supermarket.products p ON si.product_id = p.product_id
LEFT JOIN supermarket.warehouse_inventory wi ON p.product_id = wi.product_id
WHERE wi.product_id IS NULL OR wi.quantity = 0;

-- Query 4: Products sorted by total quantity (warehouse + shelf)
SELECT 
    p.product_code,
    p.product_name,
    COALESCE(wi.warehouse_qty, 0) AS warehouse_qty,
    COALESCE(si.shelf_qty, 0) AS shelf_qty,
    COALESCE(wi.warehouse_qty, 0) + COALESCE(si.shelf_qty, 0) AS total_qty
FROM supermarket.products p
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS warehouse_qty
    FROM supermarket.warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) AS shelf_qty
    FROM supermarket.shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id
ORDER BY total_qty ASC;

-- Query 5: Monthly revenue ranking
SELECT 
    p.product_code,
    p.product_name,
    SUM(sid.quantity) AS total_sold,
    SUM(sid.subtotal) AS total_revenue,
    RANK() OVER (ORDER BY SUM(sid.subtotal) DESC) AS revenue_rank
FROM supermarket.sales_invoice_details sid
INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
INNER JOIN supermarket.products p ON sid.product_id = p.product_id
WHERE EXTRACT(MONTH FROM si.invoice_date) = 12 -- December
  AND EXTRACT(YEAR FROM si.invoice_date) = 2024
GROUP BY p.product_id, p.product_code, p.product_name
ORDER BY total_revenue DESC;

-- Query 6: Expired products that need removal
SELECT 
    wi.batch_code,
    p.product_code,
    p.product_name,
    wi.quantity,
    wi.expiry_date,
    CURRENT_DATE - wi.expiry_date AS days_expired
FROM supermarket.warehouse_inventory wi
INNER JOIN supermarket.products p ON wi.product_id = p.product_id
WHERE wi.expiry_date < CURRENT_DATE
ORDER BY days_expired DESC;

-- Query 7: Customer membership and purchase information
SELECT 
    c.customer_code,
    c.full_name,
    ml.level_name,
    c.total_spending,
    c.loyalty_points,
    COUNT(si.invoice_id) AS total_purchases,
    MAX(si.invoice_date) AS last_purchase
FROM supermarket.customers c
LEFT JOIN supermarket.membership_levels ml ON c.membership_level_id = ml.level_id
LEFT JOIN supermarket.sales_invoices si ON c.customer_id = si.customer_id
WHERE c.is_active = true
GROUP BY c.customer_id, c.customer_code, c.full_name, 
         ml.level_name, c.total_spending, c.loyalty_points
ORDER BY c.total_spending DESC;

-- Query 8: Supplier ranking by revenue
SELECT 
    s.supplier_code,
    s.supplier_name,
    COUNT(DISTINCT p.product_id) AS product_count,
    SUM(sid.subtotal) AS total_revenue,
    RANK() OVER (ORDER BY SUM(sid.subtotal) DESC) AS supplier_rank
FROM supermarket.suppliers s
INNER JOIN supermarket.products p ON s.supplier_id = p.supplier_id
INNER JOIN supermarket.sales_invoice_details sid ON p.product_id = sid.product_id
GROUP BY s.supplier_id, s.supplier_code, s.supplier_name
ORDER BY total_revenue DESC;

-- Query 9: Daily sales summary
SELECT 
    DATE(si.invoice_date) AS sale_date,
    COUNT(DISTINCT si.invoice_id) AS total_transactions,
    COUNT(DISTINCT si.customer_id) AS unique_customers,
    SUM(si.total_amount) AS daily_revenue,
    AVG(si.total_amount) AS avg_transaction_value
FROM supermarket.sales_invoices si
WHERE si.invoice_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE(si.invoice_date)
ORDER BY sale_date DESC;

-- Query 10: Product performance by day of week
SELECT 
    TO_CHAR(si.invoice_date, 'Day') AS day_of_week,
    EXTRACT(DOW FROM si.invoice_date) AS day_number,
    p.product_name,
    SUM(sid.quantity) AS total_quantity,
    SUM(sid.subtotal) AS total_revenue
FROM supermarket.sales_invoice_details sid
INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
INNER JOIN supermarket.products p ON sid.product_id = p.product_id
GROUP BY TO_CHAR(si.invoice_date, 'Day'), 
         EXTRACT(DOW FROM si.invoice_date),
         p.product_name
ORDER BY day_number, total_revenue DESC;