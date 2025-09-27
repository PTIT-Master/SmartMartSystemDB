-- VIEWs và Stored Procedures cho hệ thống quản lý siêu thị
-- Tập trung vào database operations cho môn học CSDL

-- Set search path
SET search_path TO supermarket;

-- ===========================================================================
-- VIEWs
-- ===========================================================================

-- View: Tổng quan sản phẩm với thông tin kho và quầy
CREATE OR REPLACE VIEW v_product_overview AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    s.supplier_name AS supplier_name,
    p.selling_price,
    p.import_price,
    COALESCE(wi.total_warehouse, 0) AS warehouse_quantity,
    COALESCE(si.total_shelf, 0) AS shelf_quantity,
    COALESCE(wi.total_warehouse, 0) + COALESCE(si.total_shelf, 0) AS total_quantity
FROM products p
LEFT JOIN product_categories c ON p.category_id = c.category_id
LEFT JOIN suppliers s ON p.supplier_id = s.supplier_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS total_warehouse
    FROM warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) AS total_shelf
    FROM shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id;

-- View: Sản phẩm sắp hết hàng (dưới ngưỡng tối thiểu)
CREATE OR REPLACE VIEW v_low_stock_products AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    p.low_stock_threshold,
    COALESCE(wi.total_warehouse, 0) AS warehouse_quantity,
    COALESCE(si.total_shelf, 0) AS shelf_quantity,
    COALESCE(wi.total_warehouse, 0) + COALESCE(si.total_shelf, 0) AS total_quantity
FROM products p
LEFT JOIN product_categories c ON p.category_id = c.category_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS total_warehouse
    FROM warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) AS total_shelf
    FROM shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id
WHERE (COALESCE(wi.total_warehouse, 0) + COALESCE(si.total_shelf, 0)) < p.low_stock_threshold;

-- View: Sản phẩm cần bổ sung lên kệ (shelf quantity thấp nhưng còn hàng trong kho)
CREATE OR REPLACE VIEW v_low_shelf_products AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    p.low_stock_threshold,
    COALESCE(wi.total_warehouse, 0) AS warehouse_quantity,
    COALESCE(si.total_shelf, 0) AS shelf_quantity,
    COALESCE(wi.total_warehouse, 0) + COALESCE(si.total_shelf, 0) AS total_quantity,
    CASE 
        WHEN p.low_stock_threshold > 0 THEN ROUND(100.0 * COALESCE(si.total_shelf, 0) / p.low_stock_threshold, 2)
        ELSE 0 
    END AS shelf_fill_percentage
FROM products p
LEFT JOIN product_categories c ON p.category_id = c.category_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS total_warehouse
    FROM warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) AS total_shelf
    FROM shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id
WHERE COALESCE(si.total_shelf, 0) < p.low_stock_threshold 
  AND COALESCE(wi.total_warehouse, 0) > 0  -- Còn hàng trong kho
  AND p.low_stock_threshold > 0
ORDER BY shelf_fill_percentage ASC, si.total_shelf ASC;

-- View: Sản phẩm hết hàng trong kho nhưng vẫn còn trên quầy
CREATE OR REPLACE VIEW v_warehouse_empty_products AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    p.low_stock_threshold,
    COALESCE(wi.total_warehouse, 0) AS warehouse_quantity,
    COALESCE(si.total_shelf, 0) AS shelf_quantity,
    COALESCE(wi.total_warehouse, 0) + COALESCE(si.total_shelf, 0) AS total_quantity,
    CASE 
        WHEN p.low_stock_threshold > 0 THEN ROUND(100.0 * COALESCE(si.total_shelf, 0) / p.low_stock_threshold, 2)
        ELSE 0 
    END AS shelf_fill_percentage
FROM products p
LEFT JOIN product_categories c ON p.category_id = c.category_id
LEFT JOIN (
    SELECT product_id, SUM(quantity) AS total_warehouse
    FROM warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    SELECT product_id, SUM(current_quantity) AS total_shelf
    FROM shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id
WHERE COALESCE(wi.total_warehouse, 0) = 0  -- Hết hàng trong kho
  AND COALESCE(si.total_shelf, 0) > 0      -- Còn hàng trên quầy
ORDER BY si.total_shelf DESC;

-- View: Sản phẩm sắp hết hạn (trong 7 ngày tới)
CREATE OR REPLACE VIEW v_expiring_products AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    sbi.batch_code,
    sbi.expiry_date,
    sbi.quantity,
    sbi.shelf_id,
    ds.shelf_name,
    sbi.current_price,
    sbi.discount_percent,
    sbi.expiry_date - CURRENT_DATE AS days_remaining
FROM shelf_batch_inventory sbi
JOIN products p ON sbi.product_id = p.product_id
JOIN product_categories c ON p.category_id = c.category_id
JOIN display_shelves ds ON sbi.shelf_id = ds.shelf_id
WHERE sbi.expiry_date <= CURRENT_DATE + INTERVAL '7 days'
  AND sbi.quantity > 0
ORDER BY sbi.expiry_date;

-- View: Doanh thu theo sản phẩm
CREATE OR REPLACE VIEW v_product_revenue AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    SUM(sid.quantity) AS total_sold,
    SUM(sid.subtotal) AS total_revenue,
    COUNT(DISTINCT si.invoice_id) AS transaction_count
FROM sales_invoice_details sid
JOIN products p ON sid.product_id = p.product_id
JOIN product_categories c ON p.category_id = c.category_id
JOIN sales_invoices si ON sid.invoice_id = si.invoice_id
GROUP BY p.product_id, p.product_code, p.product_name, c.category_name;

-- View: Doanh thu theo nhà cung cấp
CREATE OR REPLACE VIEW v_supplier_revenue AS
SELECT 
    s.supplier_id,
    s.supplier_name,
    s.contact_person,
    COUNT(DISTINCT p.product_id) AS product_count,
    SUM(pr.total_sold) AS total_units_sold,
    SUM(pr.total_revenue) AS total_revenue
FROM suppliers s
JOIN products p ON s.supplier_id = p.supplier_id
LEFT JOIN v_product_revenue pr ON p.product_id = pr.product_id
GROUP BY s.supplier_id, s.supplier_name, s.contact_person
ORDER BY total_revenue DESC NULLS LAST;

-- View: Khách hàng VIP (top spending)
CREATE OR REPLACE VIEW v_vip_customers AS
SELECT 
    c.customer_id,
    c.full_name,
    c.phone,
    c.email,
    ml.level_name AS membership_level,
    c.total_spending,
    c.loyalty_points,
    COUNT(si.invoice_id) AS purchase_count,
    MAX(si.invoice_date) AS last_purchase
FROM customers c
LEFT JOIN membership_levels ml ON c.membership_level_id = ml.level_id
LEFT JOIN sales_invoices si ON c.customer_id = si.customer_id
GROUP BY c.customer_id, c.full_name, c.phone, c.email, ml.level_name, c.total_spending, c.loyalty_points
ORDER BY c.total_spending DESC;

-- View: Tình trạng quầy hàng
CREATE OR REPLACE VIEW v_shelf_status AS
SELECT 
    ds.shelf_id,
    ds.shelf_name,
    pc.category_name,
    ds.location,
    COUNT(si.product_id) AS product_count,
    SUM(si.current_quantity) AS total_items,
    SUM(sl.max_quantity) AS total_capacity,
    CASE 
        WHEN SUM(sl.max_quantity) > 0 
        THEN ROUND(100.0 * SUM(si.current_quantity) / SUM(sl.max_quantity), 2)
        ELSE 0 
    END AS fill_percentage
FROM display_shelves ds
JOIN product_categories pc ON ds.category_id = pc.category_id
LEFT JOIN shelf_inventory si ON ds.shelf_id = si.shelf_id
LEFT JOIN shelf_layout sl ON ds.shelf_id = sl.shelf_id
GROUP BY ds.shelf_id, ds.shelf_name, pc.category_name, ds.location;

-- ===========================================================================
-- STORED PROCEDURES và FUNCTIONS
-- ===========================================================================

-- Function: Tính giá sau giảm cho sản phẩm sắp hết hạn
CREATE OR REPLACE FUNCTION calculate_discount_price(
    p_product_id BIGINT,
    p_expiry_date DATE
) RETURNS DECIMAL(12,2) AS $$
DECLARE
    v_days_remaining INT;
    v_discount_percent DECIMAL(5,2);
    v_selling_price DECIMAL(12,2);
    v_category_id BIGINT;
BEGIN
    -- Tính số ngày còn lại
    v_days_remaining := p_expiry_date - CURRENT_DATE;
    
    -- Lấy category và giá bán
    SELECT category_id, selling_price INTO v_category_id, v_selling_price
    FROM products WHERE product_id = p_product_id;
    
    -- Lấy quy tắc giảm giá theo category và số ngày
    SELECT discount_percentage INTO v_discount_percent
    FROM discount_rules
    WHERE category_id = v_category_id
      AND days_before_expiry >= v_days_remaining
    ORDER BY days_before_expiry ASC
    LIMIT 1;
    
    -- Nếu không có quy tắc, không giảm giá
    IF v_discount_percent IS NULL THEN
        v_discount_percent := 0;
    END IF;
    
    -- Tính giá sau giảm
    RETURN v_selling_price * (1 - v_discount_percent / 100);
END;
$$ LANGUAGE plpgsql;

-- Procedure: Chuyển hàng từ kho lên quầy
CREATE OR REPLACE PROCEDURE transfer_stock_to_shelf(
    p_product_id BIGINT,
    p_from_warehouse_id BIGINT,
    p_to_shelf_id BIGINT,
    p_quantity BIGINT,
    p_employee_id BIGINT
) AS $$
DECLARE
    v_available_qty BIGINT;
    v_max_shelf_qty BIGINT;
    v_current_shelf_qty BIGINT;
    v_batch_code VARCHAR(50);
    v_expiry_date DATE;
    v_import_price DECIMAL(12,2);
BEGIN
    -- Kiểm tra số lượng trong kho
    SELECT SUM(quantity) INTO v_available_qty
    FROM warehouse_inventory
    WHERE warehouse_id = p_from_warehouse_id AND product_id = p_product_id;
    
    IF v_available_qty IS NULL OR v_available_qty < p_quantity THEN
        RAISE EXCEPTION 'Không đủ hàng trong kho. Có sẵn: %, Yêu cầu: %', v_available_qty, p_quantity;
    END IF;
    
    -- Kiểm tra giới hạn quầy hàng
    SELECT max_quantity INTO v_max_shelf_qty
    FROM shelf_layout
    WHERE shelf_id = p_to_shelf_id AND product_id = p_product_id;
    
    SELECT COALESCE(current_quantity, 0) INTO v_current_shelf_qty
    FROM shelf_inventory
    WHERE shelf_id = p_to_shelf_id AND product_id = p_product_id;
    
    IF v_max_shelf_qty IS NOT NULL AND (v_current_shelf_qty + p_quantity) > v_max_shelf_qty THEN
        RAISE EXCEPTION 'Vượt quá giới hạn quầy hàng. Giới hạn: %, Hiện tại: %, Yêu cầu thêm: %', 
            v_max_shelf_qty, v_current_shelf_qty, p_quantity;
    END IF;
    
    -- Lấy batch cũ nhất (FIFO)
    SELECT batch_code, expiry_date, import_price 
    INTO v_batch_code, v_expiry_date, v_import_price
    FROM warehouse_inventory
    WHERE warehouse_id = p_from_warehouse_id AND product_id = p_product_id
    ORDER BY expiry_date ASC, batch_code ASC
    LIMIT 1;
    
    -- Giảm số lượng trong kho
    UPDATE warehouse_inventory
    SET quantity = quantity - p_quantity
    WHERE warehouse_id = p_from_warehouse_id 
      AND product_id = p_product_id 
      AND batch_code = v_batch_code;
    
    -- Xóa record nếu hết hàng
    DELETE FROM warehouse_inventory
    WHERE warehouse_id = p_from_warehouse_id 
      AND product_id = p_product_id 
      AND batch_code = v_batch_code
      AND quantity <= 0;
    
    -- Cập nhật số lượng trên quầy
    INSERT INTO shelf_inventory (shelf_id, product_id, current_quantity, restock_threshold)
    VALUES (p_to_shelf_id, p_product_id, p_quantity, 10)
    ON CONFLICT (shelf_id, product_id)
    DO UPDATE SET current_quantity = shelf_inventory.current_quantity + p_quantity;
    
    -- Thêm vào batch tracking trên quầy
    INSERT INTO shelf_batch_inventory (
        shelf_id, product_id, batch_code, quantity, 
        expiry_date, import_price, current_price, discount_percent
    ) VALUES (
        p_to_shelf_id, p_product_id, v_batch_code, p_quantity,
        v_expiry_date, v_import_price, 
        (SELECT selling_price FROM products WHERE product_id = p_product_id), 0
    )
    ON CONFLICT (shelf_id, product_id, batch_code)
    DO UPDATE SET quantity = shelf_batch_inventory.quantity + p_quantity;
    
    -- Ghi log chuyển hàng
    INSERT INTO stock_transfers (
        product_id, from_warehouse_id, to_shelf_id, 
        quantity, transfer_date, employee_id
    ) VALUES (
        p_product_id, p_from_warehouse_id, p_to_shelf_id,
        p_quantity, NOW(), p_employee_id
    );
    
    COMMIT;
END;
$$ LANGUAGE plpgsql;

-- Function: Tính tổng tiền hóa đơn với giảm giá
CREATE OR REPLACE FUNCTION calculate_invoice_total(p_invoice_id BIGINT)
RETURNS TABLE (
    subtotal DECIMAL(12,2),
    discount_amount DECIMAL(12,2),
    total_amount DECIMAL(12,2)
) AS $$
DECLARE
    v_subtotal DECIMAL(12,2);
    v_customer_id BIGINT;
    v_discount_rate DECIMAL(5,2);
    v_discount_amount DECIMAL(12,2);
BEGIN
    -- Tính subtotal
    SELECT SUM(subtotal) INTO v_subtotal
    FROM sales_invoice_details
    WHERE invoice_id = p_invoice_id;
    
    -- Lấy thông tin khách hàng
    SELECT customer_id INTO v_customer_id
    FROM sales_invoices
    WHERE invoice_id = p_invoice_id;
    
    -- Tính discount dựa trên membership level
    IF v_customer_id IS NOT NULL THEN
        SELECT ml.discount_rate INTO v_discount_rate
        FROM customers c
        JOIN membership_levels ml ON c.membership_level_id = ml.level_id
        WHERE c.customer_id = v_customer_id;
    END IF;
    
    v_discount_rate := COALESCE(v_discount_rate, 0);
    v_discount_amount := v_subtotal * v_discount_rate / 100;
    
    RETURN QUERY
    SELECT 
        v_subtotal,
        v_discount_amount,
        v_subtotal - v_discount_amount;
END;
$$ LANGUAGE plpgsql;

-- Procedure: Cập nhật giá giảm cho sản phẩm sắp hết hạn
CREATE OR REPLACE PROCEDURE update_expiry_discounts()
AS $$
DECLARE
    rec RECORD;
    v_discount_percent DECIMAL(5,2);
BEGIN
    -- Duyệt qua tất cả sản phẩm trên quầy
    FOR rec IN 
        SELECT sbi.shelf_batch_id, sbi.product_id, sbi.expiry_date, p.category_id
        FROM shelf_batch_inventory sbi
        JOIN products p ON sbi.product_id = p.product_id
        WHERE sbi.expiry_date > CURRENT_DATE
          AND sbi.quantity > 0
    LOOP
        -- Tính discount theo quy tắc
        SELECT discount_percentage INTO v_discount_percent
        FROM discount_rules
        WHERE category_id = rec.category_id
          AND days_before_expiry >= (rec.expiry_date - CURRENT_DATE)
        ORDER BY days_before_expiry ASC
        LIMIT 1;
        
        IF v_discount_percent IS NOT NULL THEN
            -- Cập nhật discount và đánh dấu near expiry
            UPDATE shelf_batch_inventory
            SET discount_percent = v_discount_percent,
                is_near_expiry = TRUE,
                current_price = (
                    SELECT selling_price * (1 - v_discount_percent / 100)
                    FROM products WHERE product_id = rec.product_id
                )
            WHERE shelf_batch_id = rec.shelf_batch_id;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function: Báo cáo doanh thu theo thời gian
CREATE OR REPLACE FUNCTION get_revenue_report(
    p_start_date DATE,
    p_end_date DATE
) RETURNS TABLE (
    report_date DATE,
    total_invoices BIGINT,
    total_revenue DECIMAL(12,2),
    total_customers BIGINT,
    avg_invoice_value DECIMAL(12,2)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        DATE(si.invoice_date) AS report_date,
        COUNT(DISTINCT si.invoice_id) AS total_invoices,
        SUM(si.total_amount) AS total_revenue,
        COUNT(DISTINCT si.customer_id) AS total_customers,
        AVG(si.total_amount) AS avg_invoice_value
    FROM sales_invoices si
    WHERE DATE(si.invoice_date) BETWEEN p_start_date AND p_end_date
    GROUP BY DATE(si.invoice_date)
    ORDER BY report_date DESC;
END;
$$ LANGUAGE plpgsql;

-- Function: Kiểm tra và cảnh báo hàng hóa cần bổ sung
CREATE OR REPLACE FUNCTION check_restock_alerts()
RETURNS TABLE (
    shelf_id BIGINT,
    shelf_name VARCHAR(100),
    product_id BIGINT,
    product_name VARCHAR(200),
    current_quantity BIGINT,
    restock_threshold BIGINT,
    suggested_restock BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        si.shelf_id,
        ds.shelf_name,
        si.product_id,
        p.product_name,
        si.current_quantity,
        si.restock_threshold,
        sl.max_quantity - si.current_quantity AS suggested_restock
    FROM shelf_inventory si
    JOIN display_shelves ds ON si.shelf_id = ds.shelf_id
    JOIN products p ON si.product_id = p.product_id
    JOIN shelf_layout sl ON si.shelf_id = sl.shelf_id AND si.product_id = sl.product_id
    WHERE si.current_quantity <= si.restock_threshold
    ORDER BY si.current_quantity ASC;
END;
$$ LANGUAGE plpgsql;

-- Procedure: Xử lý thanh toán và cập nhật inventory
CREATE OR REPLACE PROCEDURE process_sale_payment(
    p_invoice_id BIGINT
) AS $$
DECLARE
    rec RECORD;
    v_customer_id BIGINT;
    v_total_amount DECIMAL(12,2);
BEGIN
    -- Duyệt qua các chi tiết hóa đơn
    FOR rec IN 
        SELECT product_id, quantity 
        FROM sales_invoice_details 
        WHERE invoice_id = p_invoice_id
    LOOP
        -- Giảm số lượng trên quầy (FIFO từ batch cũ nhất)
        WITH batch_deduct AS (
            SELECT shelf_batch_id, 
                   LEAST(quantity, rec.quantity) AS deduct_qty
            FROM shelf_batch_inventory
            WHERE product_id = rec.product_id
              AND quantity > 0
            ORDER BY expiry_date ASC, batch_code ASC
            LIMIT 1
        )
        UPDATE shelf_batch_inventory sbi
        SET quantity = sbi.quantity - bd.deduct_qty
        FROM batch_deduct bd
        WHERE sbi.shelf_batch_id = bd.shelf_batch_id;
        
        -- Cập nhật tổng số lượng trên quầy
        UPDATE shelf_inventory
        SET current_quantity = current_quantity - rec.quantity
        WHERE product_id = rec.product_id
          AND current_quantity >= rec.quantity;
    END LOOP;
    
    -- Cập nhật điểm và tổng chi tiêu cho khách hàng
    SELECT customer_id, total_amount 
    INTO v_customer_id, v_total_amount
    FROM sales_invoices 
    WHERE invoice_id = p_invoice_id;
    
    IF v_customer_id IS NOT NULL THEN
        UPDATE customers
        SET total_spending = total_spending + v_total_amount,
            loyalty_points = loyalty_points + FLOOR(v_total_amount / 10000)
        WHERE customer_id = v_customer_id;
    END IF;
    
    COMMIT;
END;
$$ LANGUAGE plpgsql;

-- Function: Thống kê sản phẩm bán chạy
CREATE OR REPLACE FUNCTION get_best_selling_products(
    p_limit INT DEFAULT 10
) RETURNS TABLE (
    product_id BIGINT,
    product_code VARCHAR(50),
    product_name VARCHAR(200),
    category_name VARCHAR(100),
    total_sold BIGINT,
    total_revenue DECIMAL(12,2),
    avg_price DECIMAL(12,2)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.product_id,
        p.product_code,
        p.product_name,
        pc.category_name,
        SUM(sid.quantity)::BIGINT AS total_sold,
        SUM(sid.subtotal) AS total_revenue,
        AVG(sid.unit_price) AS avg_price
    FROM sales_invoice_details sid
    JOIN products p ON sid.product_id = p.product_id
    JOIN product_categories pc ON p.category_id = pc.category_id
    GROUP BY p.product_id, p.product_code, p.product_name, pc.category_name
    ORDER BY total_sold DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- ===========================================================================
-- INDEXES cho VIEWs và queries thường xuyên
-- ===========================================================================

-- Indexes cho performance
CREATE INDEX IF NOT EXISTS idx_sales_invoice_date_range 
ON sales_invoices(invoice_date DESC);

CREATE INDEX IF NOT EXISTS idx_shelf_batch_expiry_active 
ON shelf_batch_inventory(expiry_date) 
WHERE quantity > 0;

CREATE INDEX IF NOT EXISTS idx_warehouse_batch_expiry 
ON warehouse_inventory(expiry_date, batch_code);

-- ===========================================================================
-- Quyền truy cập
-- ===========================================================================

-- Grant permissions cho các views
GRANT SELECT ON ALL TABLES IN SCHEMA supermarket TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA supermarket TO PUBLIC;
