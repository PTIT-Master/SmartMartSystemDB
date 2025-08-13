-- =====================================================
-- COMPLEX QUERIES & REPORTING VIEWS
-- File: 03_queries.sql
-- Content: Views, Complex Queries, and Reporting Functions
-- =====================================================

SET search_path TO supermarket;

-- =====================================================
-- 1. QUERY: List products by category with sorting options
-- =====================================================

-- a. Sort by remaining quantity on shelf (ascending)
CREATE OR REPLACE VIEW v_products_by_shelf_quantity AS
SELECT 
    pc.category_name,
    p.product_code,
    p.product_name,
    p.unit,
    COALESCE(SUM(si.current_quantity), 0) as shelf_quantity,
    COALESCE((SELECT SUM(quantity) FROM warehouse_inventory wi 
              WHERE wi.product_id = p.product_id), 0) as warehouse_quantity,
    p.selling_price,
    CASE 
        WHEN COALESCE(SUM(si.current_quantity), 0) = 0 THEN 'Hết hàng'
        WHEN COALESCE(SUM(si.current_quantity), 0) < p.low_stock_threshold THEN 'Sắp hết'
        ELSE 'Còn hàng'
    END as status
FROM products p
JOIN product_categories pc ON p.category_id = pc.category_id
LEFT JOIN shelf_inventory si ON p.product_id = si.product_id
WHERE p.is_active = TRUE
GROUP BY p.product_id, p.product_code, p.product_name, 
         pc.category_name, p.unit, p.selling_price, p.low_stock_threshold
ORDER BY shelf_quantity ASC, p.product_name;

-- b. Sort by daily sales quantity
CREATE OR REPLACE VIEW v_products_by_daily_sales AS
SELECT 
    DATE(si.invoice_date) as sale_date,
    pc.category_name,
    p.product_code,
    p.product_name,
    SUM(sid.quantity) as quantity_sold,
    SUM(sid.subtotal) as revenue,
    COUNT(DISTINCT si.invoice_id) as transaction_count
FROM products p
JOIN product_categories pc ON p.category_id = pc.category_id
JOIN sales_invoice_details sid ON p.product_id = sid.product_id
JOIN sales_invoices si ON sid.invoice_id = si.invoice_id
WHERE DATE(si.invoice_date) = CURRENT_DATE
GROUP BY DATE(si.invoice_date), p.product_id, p.product_code, 
         p.product_name, pc.category_name
ORDER BY quantity_sold DESC;

-- =====================================================
-- 2. QUERY: Products low on shelf but available in warehouse
-- =====================================================
CREATE OR REPLACE VIEW v_products_need_restocking AS
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    ds.shelf_code,
    ds.shelf_name,
    si.current_quantity as shelf_qty,
    p.low_stock_threshold,
    sl.max_quantity as max_shelf_capacity,
    COALESCE(w_inv.warehouse_qty, 0) as warehouse_available,
    sl.position_code as shelf_position,
    GREATEST(0, p.low_stock_threshold - si.current_quantity) as suggested_restock_qty
FROM products p
JOIN product_categories pc ON p.category_id = pc.category_id
JOIN shelf_inventory si ON p.product_id = si.product_id
JOIN shelf_layout sl ON sl.product_id = p.product_id AND sl.shelf_id = si.shelf_id
JOIN display_shelves ds ON ds.shelf_id = si.shelf_id
LEFT JOIN LATERAL (
    SELECT SUM(quantity) as warehouse_qty
    FROM warehouse_inventory wi
    WHERE wi.product_id = p.product_id
) w_inv ON TRUE
WHERE si.current_quantity < p.low_stock_threshold
  AND COALESCE(w_inv.warehouse_qty, 0) > 0
ORDER BY pc.category_name, (si.current_quantity::FLOAT / p.low_stock_threshold) ASC;

-- =====================================================
-- 3. QUERY: Products out of stock in warehouse but available on shelf
-- =====================================================
CREATE OR REPLACE VIEW v_products_warehouse_empty AS
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    SUM(si.current_quantity) as total_shelf_quantity,
    COUNT(DISTINCT si.shelf_id) as shelf_count,
    STRING_AGG(ds.shelf_code, ', ' ORDER BY ds.shelf_code) as shelf_codes,
    p.supplier_id,
    s.supplier_name,
    s.phone as supplier_phone
FROM products p
JOIN product_categories pc ON p.category_id = pc.category_id
JOIN suppliers s ON p.supplier_id = s.supplier_id
JOIN shelf_inventory si ON p.product_id = si.product_id
JOIN display_shelves ds ON si.shelf_id = ds.shelf_id
LEFT JOIN warehouse_inventory wi ON p.product_id = wi.product_id AND wi.quantity > 0
WHERE wi.product_id IS NULL
  AND si.current_quantity > 0
GROUP BY p.product_id, p.product_code, p.product_name, 
         pc.category_name, s.supplier_name, s.phone
ORDER BY total_shelf_quantity ASC;

-- =====================================================
-- 4. QUERY: Total inventory sorted by quantity (shelf + warehouse)
-- =====================================================
CREATE OR REPLACE VIEW v_total_inventory AS
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    COALESCE(shelf_inv.shelf_qty, 0) as shelf_quantity,
    COALESCE(warehouse_inv.warehouse_qty, 0) as warehouse_quantity,
    COALESCE(shelf_inv.shelf_qty, 0) + COALESCE(warehouse_inv.warehouse_qty, 0) as total_quantity,
    p.import_price,
    p.selling_price,
    (COALESCE(shelf_inv.shelf_qty, 0) + COALESCE(warehouse_inv.warehouse_qty, 0)) * p.import_price as inventory_value
FROM products p
JOIN product_categories pc ON p.category_id = pc.category_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) as shelf_qty
    FROM shelf_inventory
    GROUP BY product_id
) shelf_inv ON p.product_id = shelf_inv.product_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) as warehouse_qty
    FROM warehouse_inventory
    GROUP BY product_id
) warehouse_inv ON p.product_id = warehouse_inv.product_id
ORDER BY total_quantity ASC, p.product_name;

-- =====================================================
-- 5. QUERY: Monthly product revenue ranking
-- =====================================================
CREATE OR REPLACE FUNCTION fn_product_revenue_ranking(
    p_year INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE),
    p_month INTEGER DEFAULT EXTRACT(MONTH FROM CURRENT_DATE)
)
RETURNS TABLE(
    rank BIGINT,
    product_code VARCHAR,
    product_name VARCHAR,
    category_name VARCHAR,
    quantity_sold BIGINT,
    revenue DECIMAL,
    profit DECIMAL,
    profit_margin DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ROW_NUMBER() OVER (ORDER BY SUM(sid.subtotal) DESC) as rank,
        p.product_code,
        p.product_name,
        pc.category_name,
        SUM(sid.quantity) as quantity_sold,
        SUM(sid.subtotal) as revenue,
        SUM(sid.quantity * (p.selling_price - p.import_price)) as profit,
        ROUND((SUM(sid.quantity * (p.selling_price - p.import_price)) / 
               NULLIF(SUM(sid.subtotal), 0)) * 100, 2) as profit_margin
    FROM products p
    JOIN product_categories pc ON p.category_id = pc.category_id
    JOIN sales_invoice_details sid ON p.product_id = sid.product_id
    JOIN sales_invoices si ON sid.invoice_id = si.invoice_id
    WHERE EXTRACT(YEAR FROM si.invoice_date) = p_year
      AND EXTRACT(MONTH FROM si.invoice_date) = p_month
    GROUP BY p.product_id, p.product_code, p.product_name, 
             pc.category_name, p.import_price
    ORDER BY revenue DESC;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 6. QUERY: Expired products detection
-- =====================================================
CREATE OR REPLACE VIEW v_expired_products AS
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    wi.batch_code,
    wi.quantity,
    wi.import_date,
    wi.expiry_date,
    wi.expiry_date - CURRENT_DATE as days_until_expiry,
    CASE 
        WHEN wi.expiry_date < CURRENT_DATE THEN 'ĐÃ HẾT HẠN'
        WHEN wi.expiry_date - CURRENT_DATE <= 3 THEN 'SẮP HẾT HẠN (≤3 ngày)'
        WHEN wi.expiry_date - CURRENT_DATE <= 7 THEN 'GẦN HẾT HẠN (≤7 ngày)'
        ELSE 'CÒN HẠN'
    END as expiry_status,
    -- Calculate discount based on rules
    COALESCE(
        (SELECT dr.discount_percentage 
         FROM discount_rules dr 
         WHERE dr.category_id = p.category_id 
           AND wi.expiry_date - CURRENT_DATE <= dr.days_before_expiry
           AND dr.is_active = TRUE
         ORDER BY dr.days_before_expiry ASC
         LIMIT 1), 0
    ) as applicable_discount
FROM warehouse_inventory wi
JOIN products p ON wi.product_id = p.product_id
JOIN product_categories pc ON p.category_id = pc.category_id
WHERE wi.expiry_date IS NOT NULL
  AND wi.quantity > 0
  AND wi.expiry_date - CURRENT_DATE <= 30  -- Show products expiring within 30 days
ORDER BY wi.expiry_date ASC, p.product_name;

-- =====================================================
-- 7. QUERY: Customer ranking with tier benefits
-- =====================================================
CREATE OR REPLACE VIEW v_customer_tier_analysis AS
WITH customer_stats AS (
    SELECT 
        c.customer_id,
        c.customer_code,
        c.full_name,
        c.phone,
        c.membership_card_no,
        ml.level_name as current_level,
        ml.discount_percentage as current_discount,
        c.total_spending,
        c.loyalty_points,
        COUNT(DISTINCT si.invoice_id) as total_purchases,
        MAX(si.invoice_date) as last_purchase,
        AVG(si.total_amount) as avg_purchase_value,
        -- Calculate next tier
        LEAD(ml2.level_name) OVER (ORDER BY ml2.min_spending) as next_level,
        LEAD(ml2.min_spending) OVER (ORDER BY ml2.min_spending) as next_level_requirement
    FROM customers c
    LEFT JOIN membership_levels ml ON c.membership_level_id = ml.level_id
    LEFT JOIN sales_invoices si ON c.customer_id = si.customer_id
    CROSS JOIN membership_levels ml2
    WHERE c.total_spending >= ml2.min_spending
    GROUP BY c.customer_id, c.customer_code, c.full_name, c.phone,
             c.membership_card_no, ml.level_name, ml.discount_percentage,
             c.total_spending, c.loyalty_points, ml2.level_name, ml2.min_spending
)
SELECT DISTINCT
    customer_id,
    customer_code,
    full_name,
    phone,
    membership_card_no,
    current_level,
    current_discount,
    total_spending,
    loyalty_points,
    total_purchases,
    last_purchase,
    ROUND(avg_purchase_value, 0) as avg_purchase_value,
    next_level,
    COALESCE(next_level_requirement - total_spending, 0) as spending_to_next_level,
    CURRENT_DATE - DATE(last_purchase) as days_since_last_purchase
FROM customer_stats
ORDER BY total_spending DESC;

-- =====================================================
-- 8. QUERY: Employee performance ranking
-- =====================================================
CREATE OR REPLACE VIEW v_employee_performance AS
WITH monthly_sales AS (
    SELECT 
        e.employee_id,
        e.employee_code,
        e.full_name,
        p.position_name,
        DATE_TRUNC('month', si.invoice_date) as month,
        COUNT(si.invoice_id) as transactions,
        SUM(si.total_amount) as total_sales,
        AVG(si.total_amount) as avg_transaction
    FROM employees e
    JOIN positions p ON e.position_id = p.position_id
    LEFT JOIN sales_invoices si ON e.employee_id = si.employee_id
    WHERE si.invoice_date >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '3 months')
    GROUP BY e.employee_id, e.employee_code, e.full_name, 
             p.position_name, DATE_TRUNC('month', si.invoice_date)
)
SELECT 
    employee_code,
    full_name,
    position_name,
    TO_CHAR(month, 'YYYY-MM') as month,
    transactions,
    total_sales,
    ROUND(avg_transaction, 0) as avg_transaction,
    RANK() OVER (PARTITION BY month ORDER BY total_sales DESC) as monthly_rank,
    ROUND(total_sales / NULLIF(SUM(total_sales) OVER (PARTITION BY month), 0) * 100, 2) as sales_percentage
FROM monthly_sales
ORDER BY month DESC, total_sales DESC;

-- =====================================================
-- 9. QUERY: Supplier performance analysis
-- =====================================================
CREATE OR REPLACE VIEW v_supplier_performance AS
WITH supplier_metrics AS (
    SELECT 
        s.supplier_id,
        s.supplier_code,
        s.supplier_name,
        COUNT(DISTINCT p.product_id) as product_count,
        COUNT(DISTINCT po.order_id) as total_orders,
        SUM(pod.quantity * pod.unit_price) as total_purchase_value,
        SUM(sid.quantity) as total_units_sold,
        SUM(sid.subtotal) as total_revenue,
        AVG(sid.subtotal / NULLIF(sid.quantity, 0)) as avg_selling_price
    FROM suppliers s
    LEFT JOIN products p ON s.supplier_id = p.supplier_id
    LEFT JOIN purchase_order_details pod ON p.product_id = pod.product_id
    LEFT JOIN purchase_orders po ON pod.order_id = po.order_id
    LEFT JOIN sales_invoice_details sid ON p.product_id = sid.product_id
    WHERE s.is_active = TRUE
    GROUP BY s.supplier_id, s.supplier_code, s.supplier_name
)
SELECT 
    supplier_code,
    supplier_name,
    product_count,
    total_orders,
    COALESCE(total_purchase_value, 0) as total_purchase_value,
    COALESCE(total_units_sold, 0) as total_units_sold,
    COALESCE(total_revenue, 0) as total_revenue,
    ROUND(COALESCE(total_revenue - total_purchase_value, 0), 0) as gross_profit,
    ROUND(COALESCE((total_revenue - total_purchase_value) / NULLIF(total_revenue, 0) * 100, 0), 2) as profit_margin,
    RANK() OVER (ORDER BY total_revenue DESC) as revenue_rank
FROM supplier_metrics
ORDER BY total_revenue DESC;

-- =====================================================
-- 10. Comprehensive Dashboard Query
-- =====================================================
CREATE OR REPLACE FUNCTION fn_dashboard_summary(
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE(
    metric_name VARCHAR,
    metric_value TEXT
) AS $$
BEGIN
    RETURN QUERY
    -- Today's sales
    SELECT 'Doanh thu hôm nay'::VARCHAR, 
           TO_CHAR(COALESCE(SUM(total_amount), 0), 'FM999,999,999đ')
    FROM sales_invoices WHERE DATE(invoice_date) = p_date
    
    UNION ALL
    -- Month to date sales
    SELECT 'Doanh thu tháng này'::VARCHAR,
           TO_CHAR(COALESCE(SUM(total_amount), 0), 'FM999,999,999đ')
    FROM sales_invoices 
    WHERE DATE_TRUNC('month', invoice_date) = DATE_TRUNC('month', p_date)
    
    UNION ALL
    -- Today's transactions
    SELECT 'Giao dịch hôm nay'::VARCHAR,
           COUNT(*)::TEXT
    FROM sales_invoices WHERE DATE(invoice_date) = p_date
    
    UNION ALL
    -- Low stock products
    SELECT 'Sản phẩm sắp hết'::VARCHAR,
           COUNT(*)::TEXT
    FROM shelf_inventory si
    JOIN products p ON si.product_id = p.product_id
    WHERE si.current_quantity < p.low_stock_threshold
    
    UNION ALL
    -- Products near expiry
    SELECT 'Sản phẩm gần hết hạn'::VARCHAR,
           COUNT(*)::TEXT
    FROM warehouse_inventory
    WHERE expiry_date IS NOT NULL 
      AND expiry_date - p_date <= 7
      AND quantity > 0
    
    UNION ALL
    -- Active customers today
    SELECT 'Khách hàng hôm nay'::VARCHAR,
           COUNT(DISTINCT customer_id)::TEXT
    FROM sales_invoices 
    WHERE DATE(invoice_date) = p_date
    
    UNION ALL
    -- Top selling product today
    SELECT 'Sản phẩm bán chạy nhất'::VARCHAR,
           (SELECT p.product_name || ' (' || SUM(sid.quantity) || ' ' || p.unit || ')'
            FROM products p
            JOIN sales_invoice_details sid ON p.product_id = sid.product_id
            JOIN sales_invoices si ON sid.invoice_id = si.invoice_id
            WHERE DATE(si.invoice_date) = p_date
            GROUP BY p.product_id, p.product_name, p.unit
            ORDER BY SUM(sid.quantity) DESC
            LIMIT 1)
    
    UNION ALL
    -- Total inventory value
    SELECT 'Giá trị tồn kho'::VARCHAR,
           TO_CHAR(SUM(total_value), 'FM999,999,999đ')
    FROM (
        SELECT SUM(quantity * import_price) as total_value
        FROM warehouse_inventory wi
        JOIN products p ON wi.product_id = p.product_id
        UNION ALL
        SELECT SUM(si.current_quantity * p.import_price) as total_value
        FROM shelf_inventory si
        JOIN products p ON si.product_id = p.product_id
    ) inv;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 11. Alert System for Critical Operations
-- =====================================================
CREATE OR REPLACE FUNCTION fn_get_system_alerts()
RETURNS TABLE(
    alert_type VARCHAR,
    alert_level VARCHAR,
    description TEXT,
    affected_count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    -- Critical: Out of stock
    SELECT 'TỒN KHO'::VARCHAR, 
           'CRITICAL'::VARCHAR,
           'Sản phẩm hết hàng hoàn toàn'::TEXT,
           COUNT(*)::INTEGER
    FROM products p
    WHERE NOT EXISTS (
        SELECT 1 FROM shelf_inventory si WHERE si.product_id = p.product_id AND si.current_quantity > 0
    ) AND NOT EXISTS (
        SELECT 1 FROM warehouse_inventory wi WHERE wi.product_id = p.product_id AND wi.quantity > 0
    )
    HAVING COUNT(*) > 0
    
    UNION ALL
    -- Warning: Low stock
    SELECT 'TỒN KHO'::VARCHAR,
           'WARNING'::VARCHAR,
           'Sản phẩm sắp hết trên quầy'::TEXT,
           COUNT(*)::INTEGER
    FROM shelf_inventory si
    JOIN products p ON si.product_id = p.product_id
    WHERE si.current_quantity < p.low_stock_threshold
    HAVING COUNT(*) > 0
    
    UNION ALL
    -- Critical: Expired products
    SELECT 'HẠN SỬ DỤNG'::VARCHAR,
           'CRITICAL'::VARCHAR,
           'Sản phẩm đã hết hạn'::TEXT,
           COUNT(*)::INTEGER
    FROM warehouse_inventory
    WHERE expiry_date < CURRENT_DATE AND quantity > 0
    HAVING COUNT(*) > 0
    
    UNION ALL
    -- Warning: Near expiry
    SELECT 'HẠN SỬ DỤNG'::VARCHAR,
           'WARNING'::VARCHAR,
           'Sản phẩm sắp hết hạn (≤3 ngày)'::TEXT,
           COUNT(*)::INTEGER
    FROM warehouse_inventory
    WHERE expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 3
      AND quantity > 0
    HAVING COUNT(*) > 0
    
    UNION ALL
    -- Info: Inactive customers
    SELECT 'KHÁCH HÀNG'::VARCHAR,
           'INFO'::VARCHAR,
           'Khách hàng không mua hàng >30 ngày'::TEXT,
           COUNT(*)::INTEGER
    FROM customers c
    WHERE EXISTS (
        SELECT 1 FROM sales_invoices si 
        WHERE si.customer_id = c.customer_id
        GROUP BY si.customer_id
        HAVING MAX(si.invoice_date) < CURRENT_TIMESTAMP - INTERVAL '30 days'
    )
    HAVING COUNT(*) > 0;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Example usage queries
-- =====================================================

-- Get products by monthly revenue for current month
-- SELECT * FROM fn_product_revenue_ranking();

-- Get dashboard summary
-- SELECT * FROM fn_dashboard_summary();

-- Get system alerts
-- SELECT * FROM fn_get_system_alerts();

-- View products needing restock
-- SELECT * FROM v_products_need_restocking;

-- View expired products with applicable discounts
-- SELECT * FROM v_expired_products;

-- View customer tier analysis
-- SELECT * FROM v_customer_tier_analysis;

-- View employee monthly performance
-- SELECT * FROM v_employee_performance;

-- View supplier performance ranking
-- SELECT * FROM v_supplier_performance;