--
-- PostgreSQL database dump
--

\restrict LhHbHuD9pTkZ4A9eUbMRNvk4KBWbtlutniI6IEJBs3r4siZmq1Ny9XnoFX6Iuv6

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

-- Started on 2025-09-28 16:49:47

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 6 (class 2615 OID 34852)
-- Name: supermarket; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA supermarket;


ALTER SCHEMA supermarket OWNER TO postgres;

--
-- TOC entry 282 (class 1255 OID 35289)
-- Name: apply_expiry_discounts(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.apply_expiry_discounts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    days_until_expiry INTEGER;
    discount_rule RECORD;
    original_price NUMERIC(12,2);
    new_price NUMERIC(12,2);
    import_price_val NUMERIC(12,2);
BEGIN
    -- Only process if expiry_date is being set or updated
    IF NEW.expiry_date IS NOT NULL THEN
        days_until_expiry := NEW.expiry_date - CURRENT_DATE;
        
        -- Get the product's current selling price
        SELECT selling_price INTO original_price
        FROM products 
        WHERE product_id = NEW.product_id;
        
        -- Find applicable discount rule
        SELECT dr.discount_percentage INTO discount_rule
        FROM discount_rules dr
        INNER JOIN products p ON p.category_id = dr.category_id
        WHERE p.product_id = NEW.product_id
          AND dr.days_before_expiry >= days_until_expiry
          AND dr.is_active = true
        ORDER BY dr.days_before_expiry ASC
        LIMIT 1;
        
        -- Apply discount if rule found
        IF FOUND AND discount_rule IS NOT NULL THEN
            new_price := original_price * (1 - discount_rule.discount_percentage / 100);
            
            -- Get import price for validation
            SELECT import_price INTO import_price_val
            FROM products 
            WHERE product_id = NEW.product_id;
            
            -- Ensure discounted price is still higher than import price
            -- Set minimum price to be 110% of import price to maintain profitability
            IF new_price <= import_price_val THEN
                new_price := import_price_val * 1.1;
            END IF;
            
            UPDATE products 
            SET selling_price = new_price,
                updated_at = CURRENT_TIMESTAMP
            WHERE product_id = NEW.product_id;
            

            RAISE NOTICE '%', format('Applied %s%% discount to product %s due to expiry. New price: %s', 
                         discount_rule.discount_percentage, NEW.product_id, new_price);
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.apply_expiry_discounts() OWNER TO postgres;

--
-- TOC entry 291 (class 1255 OID 35285)
-- Name: calculate_detail_subtotal(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.calculate_detail_subtotal() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Calculate discount amount
    NEW.discount_amount := NEW.unit_price * NEW.quantity * (NEW.discount_percentage / 100);
    
    -- Calculate subtotal
    NEW.subtotal := (NEW.unit_price * NEW.quantity) - NEW.discount_amount;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.calculate_detail_subtotal() OWNER TO postgres;

--
-- TOC entry 293 (class 1255 OID 35391)
-- Name: calculate_discount_price(bigint, date); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.calculate_discount_price(p_product_id bigint, p_expiry_date date) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION supermarket.calculate_discount_price(p_product_id bigint, p_expiry_date date) OWNER TO postgres;

--
-- TOC entry 290 (class 1255 OID 35280)
-- Name: calculate_expiry_date(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.calculate_expiry_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Calculate expiry date if not provided and product has shelf life
    IF NEW.expiry_date IS NULL THEN
        SELECT NEW.import_date + (p.shelf_life_days || ' days')::INTERVAL INTO NEW.expiry_date
        FROM products p
        WHERE p.product_id = NEW.product_id AND p.shelf_life_days IS NOT NULL;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.calculate_expiry_date() OWNER TO postgres;

--
-- TOC entry 296 (class 1255 OID 35393)
-- Name: calculate_invoice_total(bigint); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.calculate_invoice_total(p_invoice_id bigint) RETURNS TABLE(subtotal numeric, discount_amount numeric, total_amount numeric)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION supermarket.calculate_invoice_total(p_invoice_id bigint) OWNER TO postgres;

--
-- TOC entry 303 (class 1255 OID 35284)
-- Name: calculate_invoice_totals(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.calculate_invoice_totals() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    invoice_subtotal NUMERIC(12,2) := 0;
    invoice_discount NUMERIC(12,2) := 0;
    invoice_tax NUMERIC(12,2) := 0;
    invoice_total NUMERIC(12,2) := 0;
BEGIN
    -- Calculate subtotal and total discount from all details
    SELECT 
        COALESCE(SUM(subtotal), 0),
        COALESCE(SUM(discount_amount), 0)
    INTO invoice_subtotal, invoice_discount
    FROM sales_invoice_details 
    WHERE invoice_id = NEW.invoice_id;
    
    -- Calculate tax (assuming 10% VAT, adjust as needed)
    invoice_tax := (invoice_subtotal - invoice_discount) * 0.10;
    
    -- Calculate final total
    invoice_total := invoice_subtotal - invoice_discount + invoice_tax;
    
    -- Update the invoice
    UPDATE sales_invoices 
    SET subtotal = invoice_subtotal,
        discount_amount = invoice_discount,
        tax_amount = invoice_tax,
        total_amount = invoice_total
    WHERE invoice_id = NEW.invoice_id;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.calculate_invoice_totals() OWNER TO postgres;

--
-- TOC entry 280 (class 1255 OID 35286)
-- Name: calculate_purchase_detail_subtotal(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.calculate_purchase_detail_subtotal() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.subtotal := NEW.unit_price * NEW.quantity;
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.calculate_purchase_detail_subtotal() OWNER TO postgres;

--
-- TOC entry 288 (class 1255 OID 35288)
-- Name: calculate_work_hours(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.calculate_work_hours() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.check_in_time IS NOT NULL AND NEW.check_out_time IS NOT NULL THEN
        NEW.total_hours := EXTRACT(EPOCH FROM (NEW.check_out_time - NEW.check_in_time)) / 3600;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.calculate_work_hours() OWNER TO postgres;

--
-- TOC entry 300 (class 1255 OID 35281)
-- Name: check_low_stock(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.check_low_stock() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    threshold INTEGER;
    product_name VARCHAR(200);
BEGIN
    -- Get product threshold and name
    SELECT p.low_stock_threshold, p.product_name 
    INTO threshold, product_name
    FROM products p 
    WHERE p.product_id = NEW.product_id;
    
    -- Check if stock is now below threshold
    IF NEW.current_quantity <= threshold AND 
       (OLD IS NULL OR OLD.current_quantity > threshold) THEN
        
        -- Here you could insert into a notifications table or log table
        RAISE NOTICE '%', format('LOW STOCK ALERT: Product "%s" (ID: %s) is at %s units (threshold: %s)', 
                     product_name, NEW.product_id, NEW.current_quantity, threshold);
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.check_low_stock() OWNER TO postgres;

--
-- TOC entry 302 (class 1255 OID 35283)
-- Name: check_membership_upgrade(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.check_membership_upgrade() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    current_level_id INTEGER;
    new_level_id INTEGER;
    new_level_name VARCHAR(50);
BEGIN
    -- Get customer's current membership level
    SELECT membership_level_id INTO current_level_id
    FROM customers WHERE customer_id = NEW.customer_id;
    
    -- Find the highest membership level this customer qualifies for
    SELECT level_id, level_name INTO new_level_id, new_level_name
    FROM membership_levels 
    WHERE min_spending <= NEW.total_spending
    ORDER BY min_spending DESC
    LIMIT 1;
    
    -- Update membership if eligible for upgrade
    IF new_level_id != current_level_id OR current_level_id IS NULL THEN
        UPDATE customers 
        SET membership_level_id = new_level_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE customer_id = NEW.customer_id;
        
        RAISE NOTICE '%', format('Customer %s upgraded to membership level: %s', NEW.customer_id, new_level_name);
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.check_membership_upgrade() OWNER TO postgres;

--
-- TOC entry 309 (class 1255 OID 35396)
-- Name: check_restock_alerts(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.check_restock_alerts() RETURNS TABLE(shelf_id bigint, shelf_name character varying, product_id bigint, product_name character varying, current_quantity bigint, restock_threshold bigint, suggested_restock bigint)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION supermarket.check_restock_alerts() OWNER TO postgres;

--
-- TOC entry 310 (class 1255 OID 35398)
-- Name: get_best_selling_products(integer); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.get_best_selling_products(p_limit integer DEFAULT 10) RETURNS TABLE(product_id bigint, product_code character varying, product_name character varying, category_name character varying, total_sold bigint, total_revenue numeric, avg_price numeric)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION supermarket.get_best_selling_products(p_limit integer) OWNER TO postgres;

--
-- TOC entry 292 (class 1255 OID 35395)
-- Name: get_revenue_report(date, date); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.get_revenue_report(p_start_date date, p_end_date date) RETURNS TABLE(report_date date, total_invoices bigint, total_revenue numeric, total_customers bigint, avg_invoice_value numeric)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION supermarket.get_revenue_report(p_start_date date, p_end_date date) OWNER TO postgres;

--
-- TOC entry 308 (class 1255 OID 35294)
-- Name: log_expiry_alert(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.log_expiry_alert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    product_name VARCHAR(200);
    activity_desc TEXT;
    days_remaining INT;
BEGIN
    -- Only log if expiry date is within 7 days
    IF NEW.expiry_date IS NOT NULL AND NEW.expiry_date <= CURRENT_DATE + INTERVAL '7 days' THEN
        days_remaining := NEW.expiry_date - CURRENT_DATE;
        
        SELECT p.product_name INTO product_name
        FROM products p WHERE p.product_id = NEW.product_id;
        
        activity_desc := format('Cảnh báo hết hạn: %s - Còn lại %s ngày (Hạn: %s)', 
                               product_name, days_remaining, NEW.expiry_date);
        
        INSERT INTO activity_logs (activity_type, description, table_name, record_id, created_at)
        VALUES ('EXPIRY_ALERT', activity_desc, 'shelf_batch_inventory', NEW.shelf_batch_id, CURRENT_TIMESTAMP);
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.log_expiry_alert() OWNER TO postgres;

--
-- TOC entry 307 (class 1255 OID 35293)
-- Name: log_low_stock_alert(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.log_low_stock_alert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    product_name VARCHAR(200);
    activity_desc TEXT;
BEGIN
    -- Only log if stock just went below threshold
    IF NEW.current_quantity <= (
        SELECT low_stock_threshold FROM products WHERE product_id = NEW.product_id
    ) AND (OLD IS NULL OR OLD.current_quantity > (
        SELECT low_stock_threshold FROM products WHERE product_id = NEW.product_id
    )) THEN
        
        SELECT p.product_name INTO product_name
        FROM products p WHERE p.product_id = NEW.product_id;
        
        activity_desc := format('Cảnh báo hết hàng: %s - Số lượng hiện tại: %s', 
                               product_name, NEW.current_quantity);
        
        INSERT INTO activity_logs (activity_type, description, table_name, record_id, created_at)
        VALUES ('LOW_STOCK_ALERT', activity_desc, 'shelf_inventory', NEW.product_id, CURRENT_TIMESTAMP);
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.log_low_stock_alert() OWNER TO postgres;

--
-- TOC entry 304 (class 1255 OID 35290)
-- Name: log_product_activity(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.log_product_activity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    activity_desc TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        activity_desc := format('Sản phẩm mới được tạo: %s (Mã: %s)', 
                               NEW.product_name, NEW.product_code);
        
        INSERT INTO activity_logs (activity_type, description, table_name, record_id, created_at)
        VALUES ('PRODUCT_CREATED', activity_desc, 'products', NEW.product_id, CURRENT_TIMESTAMP);
        
    ELSIF TG_OP = 'UPDATE' THEN
        activity_desc := format('Sản phẩm được cập nhật: %s (Mã: %s)', 
                               NEW.product_name, NEW.product_code);
        
        INSERT INTO activity_logs (activity_type, description, table_name, record_id, created_at)
        VALUES ('PRODUCT_UPDATED', activity_desc, 'products', NEW.product_id, CURRENT_TIMESTAMP);
        
    ELSIF TG_OP = 'DELETE' THEN
        activity_desc := format('Sản phẩm bị xóa: %s (Mã: %s)', 
                               OLD.product_name, OLD.product_code);
        
        INSERT INTO activity_logs (activity_type, description, table_name, record_id, created_at)
        VALUES ('PRODUCT_DELETED', activity_desc, 'products', OLD.product_id, CURRENT_TIMESTAMP);
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION supermarket.log_product_activity() OWNER TO postgres;

--
-- TOC entry 306 (class 1255 OID 35292)
-- Name: log_sales_activity(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.log_sales_activity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    customer_name VARCHAR(100);
    activity_desc TEXT;
BEGIN
    -- Get customer name if exists
    IF NEW.customer_id IS NOT NULL THEN
        SELECT c.full_name INTO customer_name
        FROM customers c WHERE c.customer_id = NEW.customer_id;
    ELSE
        customer_name := 'Khách vãng lai';
    END IF;
    
    activity_desc := format('Hóa đơn bán hàng: %s - Tổng tiền: %s VNĐ', 
                           customer_name, NEW.total_amount);
    
    INSERT INTO activity_logs (activity_type, description, table_name, record_id, created_at)
    VALUES ('SALE_COMPLETED', activity_desc, 'sales_invoices', NEW.invoice_id, CURRENT_TIMESTAMP);
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.log_sales_activity() OWNER TO postgres;

--
-- TOC entry 305 (class 1255 OID 35291)
-- Name: log_stock_transfer_activity(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.log_stock_transfer_activity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    product_name VARCHAR(200);
    warehouse_name VARCHAR(100);
    shelf_name VARCHAR(100);
    activity_desc TEXT;
BEGIN
    -- Get product name
    SELECT p.product_name INTO product_name
    FROM products p WHERE p.product_id = NEW.product_id;
    
    -- Get warehouse name
    SELECT w.warehouse_name INTO warehouse_name
    FROM warehouse w WHERE w.warehouse_id = NEW.from_warehouse_id;
    
    -- Get shelf name
    SELECT ds.shelf_name INTO shelf_name
    FROM display_shelves ds WHERE ds.shelf_id = NEW.to_shelf_id;
    
    activity_desc := format('Chuyển hàng: %s từ kho %s lên quầy %s (SL: %s)', 
                           product_name, warehouse_name, shelf_name, NEW.quantity);
    
    INSERT INTO activity_logs (activity_type, description, table_name, record_id, created_at)
    VALUES ('STOCK_TRANSFER', activity_desc, 'stock_transfers', NEW.transfer_id, CURRENT_TIMESTAMP);
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.log_stock_transfer_activity() OWNER TO postgres;

--
-- TOC entry 285 (class 1255 OID 35397)
-- Name: process_sale_payment(bigint); Type: PROCEDURE; Schema: supermarket; Owner: postgres
--

CREATE PROCEDURE supermarket.process_sale_payment(IN p_invoice_id bigint)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER PROCEDURE supermarket.process_sale_payment(IN p_invoice_id bigint) OWNER TO postgres;

--
-- TOC entry 299 (class 1255 OID 35279)
-- Name: process_sales_stock_deduction(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.process_sales_stock_deduction() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    available_qty INTEGER;
BEGIN
    -- Check shelf stock availability
    SELECT si.current_quantity INTO available_qty
    FROM shelf_inventory si
    INNER JOIN sales_invoices inv ON inv.invoice_id = NEW.invoice_id
    INNER JOIN products p ON p.product_id = NEW.product_id
    WHERE si.product_id = NEW.product_id;
    
    IF NOT FOUND OR available_qty < NEW.quantity THEN
        RAISE EXCEPTION '%', format('Insufficient shelf stock for product %s. Available: %s, Requested: %s', 
                        NEW.product_id, COALESCE(available_qty, 0), NEW.quantity);
    END IF;
    
    -- Deduct from shelf inventory
    UPDATE shelf_inventory 
    SET current_quantity = current_quantity - NEW.quantity,
        updated_at = CURRENT_TIMESTAMP
    WHERE product_id = NEW.product_id 
      AND current_quantity >= NEW.quantity;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.process_sales_stock_deduction() OWNER TO postgres;

--
-- TOC entry 298 (class 1255 OID 35278)
-- Name: process_stock_transfer(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.process_stock_transfer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Deduct from warehouse inventory
    UPDATE warehouse_inventory 
    SET quantity = quantity - NEW.quantity,
        updated_at = CURRENT_TIMESTAMP
    WHERE warehouse_id = NEW.from_warehouse_id 
      AND product_id = NEW.product_id 
      AND quantity >= NEW.quantity;
    
    -- Check if update was successful
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Failed to deduct stock from warehouse. Check stock availability.';
    END IF;
    
    -- Update or insert shelf inventory
    INSERT INTO shelf_inventory (shelf_id, product_id, current_quantity, last_restocked, updated_at)
    VALUES (NEW.to_shelf_id, NEW.product_id, NEW.quantity, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT (shelf_id, product_id) 
    DO UPDATE SET 
        current_quantity = shelf_inventory.current_quantity + NEW.quantity,
        last_restocked = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.process_stock_transfer() OWNER TO postgres;

--
-- TOC entry 295 (class 1255 OID 35296)
-- Name: set_created_timestamp(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.set_created_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.created_at = CURRENT_TIMESTAMP;
    IF TG_OP = 'UPDATE' THEN
        NEW.updated_at = CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.set_created_timestamp() OWNER TO postgres;

--
-- TOC entry 284 (class 1255 OID 35392)
-- Name: transfer_stock_to_shelf(bigint, bigint, bigint, bigint, bigint); Type: PROCEDURE; Schema: supermarket; Owner: postgres
--

CREATE PROCEDURE supermarket.transfer_stock_to_shelf(IN p_product_id bigint, IN p_from_warehouse_id bigint, IN p_to_shelf_id bigint, IN p_quantity bigint, IN p_employee_id bigint)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER PROCEDURE supermarket.transfer_stock_to_shelf(IN p_product_id bigint, IN p_from_warehouse_id bigint, IN p_to_shelf_id bigint, IN p_quantity bigint, IN p_employee_id bigint) OWNER TO postgres;

--
-- TOC entry 301 (class 1255 OID 35282)
-- Name: update_customer_metrics(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.update_customer_metrics() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    points_earned INTEGER;
    multiplier NUMERIC(3,2) := 1.0;
BEGIN
    IF NEW.customer_id IS NOT NULL THEN
        -- Get points multiplier if customer has membership
        SELECT COALESCE(ml.points_multiplier, 1.0) INTO multiplier
        FROM customers c
        LEFT JOIN membership_levels ml ON c.membership_level_id = ml.level_id
        WHERE c.customer_id = NEW.customer_id;
        
        -- Calculate points earned (1 point per dollar spent, multiplied by membership bonus)
        points_earned := FLOOR(NEW.total_amount * multiplier);
        
        -- Update customer metrics
        UPDATE customers 
        SET total_spending = total_spending + NEW.total_amount,
            loyalty_points = loyalty_points + points_earned,
            updated_at = CURRENT_TIMESTAMP
        WHERE customer_id = NEW.customer_id;
        
        -- Update points earned in the invoice
        NEW.points_earned := points_earned;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.update_customer_metrics() OWNER TO postgres;

--
-- TOC entry 283 (class 1255 OID 35394)
-- Name: update_expiry_discounts(); Type: PROCEDURE; Schema: supermarket; Owner: postgres
--

CREATE PROCEDURE supermarket.update_expiry_discounts()
    LANGUAGE plpgsql
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
$$;


ALTER PROCEDURE supermarket.update_expiry_discounts() OWNER TO postgres;

--
-- TOC entry 281 (class 1255 OID 35287)
-- Name: update_purchase_order_total(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.update_purchase_order_total() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    order_total NUMERIC(12,2);
BEGIN
    -- Calculate total from all details
    SELECT COALESCE(SUM(subtotal), 0) INTO order_total
    FROM purchase_order_details 
    WHERE order_id = COALESCE(NEW.order_id, OLD.order_id);
    
    -- Update the purchase order
    UPDATE purchase_orders 
    SET total_amount = order_total,
        updated_at = CURRENT_TIMESTAMP
    WHERE order_id = COALESCE(NEW.order_id, OLD.order_id);
    
    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION supermarket.update_purchase_order_total() OWNER TO postgres;

--
-- TOC entry 294 (class 1255 OID 35295)
-- Name: update_timestamp(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.update_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.update_timestamp() OWNER TO postgres;

--
-- TOC entry 286 (class 1255 OID 35274)
-- Name: validate_product_price(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.validate_product_price() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.selling_price <= NEW.import_price THEN
        RAISE EXCEPTION '%', format('Selling price (%s) must be higher than import price (%s)', 
                        NEW.selling_price, NEW.import_price);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.validate_product_price() OWNER TO postgres;

--
-- TOC entry 287 (class 1255 OID 35275)
-- Name: validate_shelf_capacity(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.validate_shelf_capacity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    max_qty INTEGER;
BEGIN
    -- Skip validation if this is from stock transfer processing
    -- (capacity is already validated in validate_stock_transfer)
    IF TG_OP = 'UPDATE' AND OLD.current_quantity IS NOT NULL THEN
        -- This is likely from process_stock_transfer, skip validation
        RETURN NEW;
    END IF;

    -- Get maximum quantity allowed for this shelf-product combination
    SELECT sl.max_quantity INTO max_qty
    FROM shelf_layout sl
    WHERE sl.shelf_id = NEW.shelf_id AND sl.product_id = NEW.product_id;

    IF max_qty IS NULL THEN
        RAISE EXCEPTION '%', format('Product is not configured for this shelf');
    END IF;

    IF NEW.current_quantity > max_qty THEN
        RAISE EXCEPTION '%', format('Quantity (%s) exceeds maximum allowed (%s) for shelf %s',
                        NEW.current_quantity, max_qty, NEW.shelf_id);
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.validate_shelf_capacity() OWNER TO postgres;

--
-- TOC entry 289 (class 1255 OID 35276)
-- Name: validate_shelf_category_consistency(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.validate_shelf_category_consistency() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    shelf_category_id INTEGER;
    product_category_id INTEGER;
BEGIN
    -- Get shelf category
    SELECT ds.category_id INTO shelf_category_id
    FROM display_shelves ds
    WHERE ds.shelf_id = NEW.shelf_id;
    
    -- Get product category
    SELECT p.category_id INTO product_category_id
    FROM products p
    WHERE p.product_id = NEW.product_id;
    
    IF shelf_category_id != product_category_id THEN
        RAISE EXCEPTION '%', format('Product category (%s) does not match shelf category (%s)', 
                        product_category_id, shelf_category_id);
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.validate_shelf_category_consistency() OWNER TO postgres;

--
-- TOC entry 297 (class 1255 OID 35277)
-- Name: validate_stock_transfer(); Type: FUNCTION; Schema: supermarket; Owner: postgres
--

CREATE FUNCTION supermarket.validate_stock_transfer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    available_qty INTEGER;
    shelf_max_qty INTEGER;
    shelf_current_qty INTEGER;
    v_product_code TEXT;
    v_shelf_code TEXT;
BEGIN
    -- Lấy product_code từ bảng products
    SELECT product_code INTO v_product_code FROM products WHERE product_id = NEW.product_id;

    -- Lấy shelf_code từ bảng display_shelves
    SELECT shelf_code INTO v_shelf_code FROM display_shelves WHERE shelf_id = NEW.to_shelf_id;

    -- Check warehouse stock availability
    SELECT COALESCE(SUM(wi.quantity), 0) INTO available_qty
    FROM warehouse_inventory wi
    WHERE wi.warehouse_id = NEW.from_warehouse_id 
      AND wi.product_id = NEW.product_id;
    
    IF available_qty < NEW.quantity THEN
        RAISE EXCEPTION '%', format('Insufficient warehouse stock for product %s. Available: %s, Requested: %s', 
                        v_product_code, available_qty, NEW.quantity);
    END IF;
    
    -- Check shelf capacity
    SELECT sl.max_quantity INTO shelf_max_qty
    FROM shelf_layout sl
    WHERE sl.shelf_id = NEW.to_shelf_id AND sl.product_id = NEW.product_id;
    
    -- Validate shelf layout exists
    IF shelf_max_qty IS NULL THEN
        RAISE EXCEPTION '%', format('Product %s is not configured for shelf %s', v_product_code, v_shelf_code);
    END IF;
    
    -- Get current shelf inventory (defaults to 0 if not found)
    SELECT COALESCE(si.current_quantity, 0) INTO shelf_current_qty
    FROM shelf_inventory si
    WHERE si.shelf_id = NEW.to_shelf_id AND si.product_id = NEW.product_id;
    
    IF (shelf_current_qty + NEW.quantity) > shelf_max_qty THEN
        RAISE EXCEPTION '%', format('Transfer would exceed shelf capacity for product %s. Current: %s, Transfer: %s, Max: %s (Shelf: %s)', 
                        v_product_code, shelf_current_qty, NEW.quantity, shelf_max_qty, v_shelf_code);
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION supermarket.validate_stock_transfer() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 259 (class 1259 OID 36986)
-- Name: activity_logs; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.activity_logs (
    log_id bigint NOT NULL,
    activity_type character varying(50) NOT NULL,
    description text NOT NULL,
    table_name character varying(100),
    record_id bigint,
    user_id bigint,
    user_name character varying(100),
    ip_address character varying(45),
    created_at timestamp with time zone
);


ALTER TABLE supermarket.activity_logs OWNER TO postgres;

--
-- TOC entry 258 (class 1259 OID 36985)
-- Name: activity_logs_log_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.activity_logs_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.activity_logs_log_id_seq OWNER TO postgres;

--
-- TOC entry 5371 (class 0 OID 0)
-- Dependencies: 258
-- Name: activity_logs_log_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.activity_logs_log_id_seq OWNED BY supermarket.activity_logs.log_id;


--
-- TOC entry 237 (class 1259 OID 36837)
-- Name: customers; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.customers (
    customer_id bigint NOT NULL,
    customer_code character varying(20),
    full_name character varying(100),
    phone character varying(20),
    email character varying(100),
    address text,
    membership_card_no character varying(20),
    membership_level_id bigint,
    registration_date date DEFAULT CURRENT_DATE,
    total_spending numeric(12,2) DEFAULT 0,
    loyalty_points bigint DEFAULT 0,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


ALTER TABLE supermarket.customers OWNER TO postgres;

--
-- TOC entry 236 (class 1259 OID 36836)
-- Name: customers_customer_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.customers_customer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.customers_customer_id_seq OWNER TO postgres;

--
-- TOC entry 5373 (class 0 OID 0)
-- Dependencies: 236
-- Name: customers_customer_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.customers_customer_id_seq OWNED BY supermarket.customers.customer_id;


--
-- TOC entry 231 (class 1259 OID 36801)
-- Name: discount_rules; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.discount_rules (
    rule_id bigint NOT NULL,
    category_id bigint NOT NULL,
    days_before_expiry bigint NOT NULL,
    discount_percentage numeric(5,2) NOT NULL,
    rule_name character varying(100),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone,
    CONSTRAINT chk_discount_rules_discount_percentage CHECK (((discount_percentage >= (0)::numeric) AND (discount_percentage <= (100)::numeric)))
);


ALTER TABLE supermarket.discount_rules OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 36800)
-- Name: discount_rules_rule_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.discount_rules_rule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.discount_rules_rule_id_seq OWNER TO postgres;

--
-- TOC entry 5375 (class 0 OID 0)
-- Dependencies: 230
-- Name: discount_rules_rule_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.discount_rules_rule_id_seq OWNED BY supermarket.discount_rules.rule_id;


--
-- TOC entry 233 (class 1259 OID 36810)
-- Name: display_shelves; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.display_shelves (
    shelf_id bigint NOT NULL,
    shelf_code character varying(20) NOT NULL,
    shelf_name character varying(100) NOT NULL,
    category_id bigint NOT NULL,
    location character varying(100),
    max_capacity bigint,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone
);


ALTER TABLE supermarket.display_shelves OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 36809)
-- Name: display_shelves_shelf_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.display_shelves_shelf_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.display_shelves_shelf_id_seq OWNER TO postgres;

--
-- TOC entry 5377 (class 0 OID 0)
-- Dependencies: 232
-- Name: display_shelves_shelf_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.display_shelves_shelf_id_seq OWNED BY supermarket.display_shelves.shelf_id;


--
-- TOC entry 247 (class 1259 OID 36905)
-- Name: employee_work_hours; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.employee_work_hours (
    work_hour_id bigint NOT NULL,
    employee_id bigint NOT NULL,
    work_date date NOT NULL,
    check_in_time timestamp with time zone,
    check_out_time timestamp with time zone,
    total_hours numeric(5,2),
    created_at timestamp with time zone
);


ALTER TABLE supermarket.employee_work_hours OWNER TO postgres;

--
-- TOC entry 246 (class 1259 OID 36904)
-- Name: employee_work_hours_work_hour_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.employee_work_hours_work_hour_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.employee_work_hours_work_hour_id_seq OWNER TO postgres;

--
-- TOC entry 5379 (class 0 OID 0)
-- Dependencies: 246
-- Name: employee_work_hours_work_hour_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.employee_work_hours_work_hour_id_seq OWNED BY supermarket.employee_work_hours.work_hour_id;


--
-- TOC entry 235 (class 1259 OID 36820)
-- Name: employees; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.employees (
    employee_id bigint NOT NULL,
    employee_code character varying(20) NOT NULL,
    full_name character varying(100) NOT NULL,
    position_id bigint NOT NULL,
    phone character varying(20),
    email character varying(100),
    address text,
    hire_date date DEFAULT CURRENT_DATE NOT NULL,
    id_card character varying(20),
    bank_account character varying(50),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


ALTER TABLE supermarket.employees OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 36819)
-- Name: employees_employee_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.employees_employee_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.employees_employee_id_seq OWNER TO postgres;

--
-- TOC entry 5381 (class 0 OID 0)
-- Dependencies: 234
-- Name: employees_employee_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.employees_employee_id_seq OWNED BY supermarket.employees.employee_id;


--
-- TOC entry 227 (class 1259 OID 36773)
-- Name: membership_levels; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.membership_levels (
    level_id bigint NOT NULL,
    level_name character varying(50) NOT NULL,
    min_spending numeric(12,2) DEFAULT 0 NOT NULL,
    discount_percentage numeric(5,2) DEFAULT 0,
    points_multiplier numeric(3,2) DEFAULT 1,
    created_at timestamp with time zone
);


ALTER TABLE supermarket.membership_levels OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 36772)
-- Name: membership_levels_level_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.membership_levels_level_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.membership_levels_level_id_seq OWNER TO postgres;

--
-- TOC entry 5383 (class 0 OID 0)
-- Dependencies: 226
-- Name: membership_levels_level_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.membership_levels_level_id_seq OWNED BY supermarket.membership_levels.level_id;


--
-- TOC entry 225 (class 1259 OID 36762)
-- Name: positions; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.positions (
    position_id bigint NOT NULL,
    position_code character varying(20) NOT NULL,
    position_name character varying(100) NOT NULL,
    base_salary numeric(12,2) NOT NULL,
    hourly_rate numeric(10,2) NOT NULL,
    created_at timestamp with time zone,
    CONSTRAINT chk_positions_base_salary CHECK ((base_salary >= (0)::numeric)),
    CONSTRAINT chk_positions_hourly_rate CHECK ((hourly_rate >= (0)::numeric))
);


ALTER TABLE supermarket.positions OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 36761)
-- Name: positions_position_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.positions_position_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.positions_position_id_seq OWNER TO postgres;

--
-- TOC entry 5385 (class 0 OID 0)
-- Dependencies: 224
-- Name: positions_position_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.positions_position_id_seq OWNED BY supermarket.positions.position_id;


--
-- TOC entry 219 (class 1259 OID 36730)
-- Name: product_categories; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.product_categories (
    category_id bigint NOT NULL,
    category_name character varying(100) NOT NULL,
    description text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


ALTER TABLE supermarket.product_categories OWNER TO postgres;

--
-- TOC entry 218 (class 1259 OID 36729)
-- Name: product_categories_category_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.product_categories_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.product_categories_category_id_seq OWNER TO postgres;

--
-- TOC entry 5387 (class 0 OID 0)
-- Dependencies: 218
-- Name: product_categories_category_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.product_categories_category_id_seq OWNED BY supermarket.product_categories.category_id;


--
-- TOC entry 229 (class 1259 OID 36785)
-- Name: products; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.products (
    product_id bigint NOT NULL,
    product_code character varying(50) NOT NULL,
    product_name character varying(200) NOT NULL,
    category_id bigint NOT NULL,
    supplier_id bigint NOT NULL,
    unit character varying(20) NOT NULL,
    import_price numeric(12,2) NOT NULL,
    selling_price numeric(12,2) NOT NULL,
    shelf_life_days bigint,
    low_stock_threshold bigint DEFAULT 10,
    barcode character varying(50),
    description text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT check_price CHECK ((selling_price > import_price)),
    CONSTRAINT chk_products_import_price CHECK ((import_price > (0)::numeric))
);


ALTER TABLE supermarket.products OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 36784)
-- Name: products_product_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.products_product_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.products_product_id_seq OWNER TO postgres;

--
-- TOC entry 5389 (class 0 OID 0)
-- Dependencies: 228
-- Name: products_product_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.products_product_id_seq OWNED BY supermarket.products.product_id;


--
-- TOC entry 255 (class 1259 OID 36954)
-- Name: purchase_order_details; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.purchase_order_details (
    detail_id bigint NOT NULL,
    order_id bigint NOT NULL,
    product_id bigint NOT NULL,
    quantity bigint NOT NULL,
    unit_price numeric(12,2) NOT NULL,
    subtotal numeric(12,2) NOT NULL,
    created_at timestamp with time zone,
    CONSTRAINT chk_purchase_order_details_quantity CHECK ((quantity > 0))
);


ALTER TABLE supermarket.purchase_order_details OWNER TO postgres;

--
-- TOC entry 254 (class 1259 OID 36953)
-- Name: purchase_order_details_detail_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.purchase_order_details_detail_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.purchase_order_details_detail_id_seq OWNER TO postgres;

--
-- TOC entry 5391 (class 0 OID 0)
-- Dependencies: 254
-- Name: purchase_order_details_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.purchase_order_details_detail_id_seq OWNED BY supermarket.purchase_order_details.detail_id;


--
-- TOC entry 251 (class 1259 OID 36930)
-- Name: purchase_orders; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.purchase_orders (
    order_id bigint NOT NULL,
    order_no character varying(30) NOT NULL,
    supplier_id bigint NOT NULL,
    employee_id bigint NOT NULL,
    order_date date DEFAULT CURRENT_DATE NOT NULL,
    delivery_date date,
    total_amount numeric(12,2) DEFAULT 0 NOT NULL,
    status character varying(20) DEFAULT 'PENDING'::character varying,
    notes text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


ALTER TABLE supermarket.purchase_orders OWNER TO postgres;

--
-- TOC entry 250 (class 1259 OID 36929)
-- Name: purchase_orders_order_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.purchase_orders_order_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.purchase_orders_order_id_seq OWNER TO postgres;

--
-- TOC entry 5393 (class 0 OID 0)
-- Dependencies: 250
-- Name: purchase_orders_order_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.purchase_orders_order_id_seq OWNED BY supermarket.purchase_orders.order_id;


--
-- TOC entry 253 (class 1259 OID 36944)
-- Name: sales_invoice_details; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.sales_invoice_details (
    detail_id bigint NOT NULL,
    invoice_id bigint NOT NULL,
    product_id bigint NOT NULL,
    quantity bigint NOT NULL,
    unit_price numeric(12,2) NOT NULL,
    discount_percentage numeric(5,2) DEFAULT 0,
    discount_amount numeric(12,2) DEFAULT 0,
    subtotal numeric(12,2) NOT NULL,
    created_at timestamp with time zone,
    CONSTRAINT chk_sales_invoice_details_quantity CHECK ((quantity > 0))
);


ALTER TABLE supermarket.sales_invoice_details OWNER TO postgres;

--
-- TOC entry 252 (class 1259 OID 36943)
-- Name: sales_invoice_details_detail_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.sales_invoice_details_detail_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.sales_invoice_details_detail_id_seq OWNER TO postgres;

--
-- TOC entry 5395 (class 0 OID 0)
-- Dependencies: 252
-- Name: sales_invoice_details_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.sales_invoice_details_detail_id_seq OWNED BY supermarket.sales_invoice_details.detail_id;


--
-- TOC entry 249 (class 1259 OID 36912)
-- Name: sales_invoices; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.sales_invoices (
    invoice_id bigint NOT NULL,
    invoice_no character varying(30) NOT NULL,
    customer_id bigint,
    employee_id bigint NOT NULL,
    invoice_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    subtotal numeric(12,2) DEFAULT 0 NOT NULL,
    discount_amount numeric(12,2) DEFAULT 0,
    tax_amount numeric(12,2) DEFAULT 0,
    total_amount numeric(12,2) DEFAULT 0 NOT NULL,
    payment_method character varying(20),
    points_earned bigint DEFAULT 0,
    points_used bigint DEFAULT 0,
    notes text,
    created_at timestamp with time zone
);


ALTER TABLE supermarket.sales_invoices OWNER TO postgres;

--
-- TOC entry 248 (class 1259 OID 36911)
-- Name: sales_invoices_invoice_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.sales_invoices_invoice_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.sales_invoices_invoice_id_seq OWNER TO postgres;

--
-- TOC entry 5397 (class 0 OID 0)
-- Dependencies: 248
-- Name: sales_invoices_invoice_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.sales_invoices_invoice_id_seq OWNED BY supermarket.sales_invoices.invoice_id;


--
-- TOC entry 245 (class 1259 OID 36894)
-- Name: shelf_batch_inventory; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.shelf_batch_inventory (
    shelf_batch_id bigint NOT NULL,
    shelf_id bigint NOT NULL,
    product_id bigint NOT NULL,
    batch_code character varying(50) NOT NULL,
    quantity bigint NOT NULL,
    expiry_date date,
    stocked_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    import_price numeric(12,2) NOT NULL,
    current_price numeric(12,2) NOT NULL,
    discount_percent numeric(5,2) DEFAULT 0,
    is_near_expiry boolean DEFAULT false,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT shelf_batch_inventory_quantity_check CHECK ((quantity >= 0))
);


ALTER TABLE supermarket.shelf_batch_inventory OWNER TO postgres;

--
-- TOC entry 244 (class 1259 OID 36893)
-- Name: shelf_batch_inventory_shelf_batch_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.shelf_batch_inventory_shelf_batch_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.shelf_batch_inventory_shelf_batch_id_seq OWNER TO postgres;

--
-- TOC entry 5399 (class 0 OID 0)
-- Dependencies: 244
-- Name: shelf_batch_inventory_shelf_batch_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.shelf_batch_inventory_shelf_batch_id_seq OWNED BY supermarket.shelf_batch_inventory.shelf_batch_id;


--
-- TOC entry 243 (class 1259 OID 36880)
-- Name: shelf_inventory; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.shelf_inventory (
    shelf_inventory_id bigint NOT NULL,
    shelf_id bigint NOT NULL,
    product_id bigint NOT NULL,
    current_quantity bigint DEFAULT 0 NOT NULL,
    near_expiry_quantity bigint DEFAULT 0,
    expired_quantity bigint DEFAULT 0,
    earliest_expiry_date date,
    latest_expiry_date date,
    last_restocked timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    CONSTRAINT chk_shelf_inventory_current_quantity CHECK ((current_quantity >= 0)),
    CONSTRAINT chk_shelf_inventory_expired_quantity CHECK ((expired_quantity >= 0)),
    CONSTRAINT chk_shelf_inventory_near_expiry_quantity CHECK ((near_expiry_quantity >= 0))
);


ALTER TABLE supermarket.shelf_inventory OWNER TO postgres;

--
-- TOC entry 242 (class 1259 OID 36879)
-- Name: shelf_inventory_shelf_inventory_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.shelf_inventory_shelf_inventory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.shelf_inventory_shelf_inventory_id_seq OWNER TO postgres;

--
-- TOC entry 5401 (class 0 OID 0)
-- Dependencies: 242
-- Name: shelf_inventory_shelf_inventory_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.shelf_inventory_shelf_inventory_id_seq OWNED BY supermarket.shelf_inventory.shelf_inventory_id;


--
-- TOC entry 241 (class 1259 OID 36872)
-- Name: shelf_layout; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.shelf_layout (
    layout_id bigint NOT NULL,
    shelf_id bigint NOT NULL,
    product_id bigint NOT NULL,
    position_code character varying(20) NOT NULL,
    max_quantity bigint NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT chk_shelf_layout_max_quantity CHECK ((max_quantity > 0))
);


ALTER TABLE supermarket.shelf_layout OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 36871)
-- Name: shelf_layout_layout_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.shelf_layout_layout_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.shelf_layout_layout_id_seq OWNER TO postgres;

--
-- TOC entry 5403 (class 0 OID 0)
-- Dependencies: 240
-- Name: shelf_layout_layout_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.shelf_layout_layout_id_seq OWNED BY supermarket.shelf_layout.layout_id;


--
-- TOC entry 257 (class 1259 OID 36962)
-- Name: stock_transfers; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.stock_transfers (
    transfer_id bigint NOT NULL,
    transfer_code character varying(30) NOT NULL,
    product_id bigint NOT NULL,
    from_warehouse_id bigint NOT NULL,
    to_shelf_id bigint NOT NULL,
    quantity bigint NOT NULL,
    transfer_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    employee_id bigint NOT NULL,
    batch_code character varying(50) NOT NULL,
    expiry_date date,
    import_price numeric(12,2) NOT NULL,
    selling_price numeric(12,2) NOT NULL,
    notes text,
    created_at timestamp with time zone,
    CONSTRAINT chk_stock_transfers_quantity CHECK ((quantity > 0))
);


ALTER TABLE supermarket.stock_transfers OWNER TO postgres;

--
-- TOC entry 256 (class 1259 OID 36961)
-- Name: stock_transfers_transfer_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.stock_transfers_transfer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.stock_transfers_transfer_id_seq OWNER TO postgres;

--
-- TOC entry 5405 (class 0 OID 0)
-- Dependencies: 256
-- Name: stock_transfers_transfer_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.stock_transfers_transfer_id_seq OWNED BY supermarket.stock_transfers.transfer_id;


--
-- TOC entry 221 (class 1259 OID 36741)
-- Name: suppliers; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.suppliers (
    supplier_id bigint NOT NULL,
    supplier_code character varying(20) NOT NULL,
    supplier_name character varying(200) NOT NULL,
    contact_person character varying(100),
    phone character varying(20),
    email character varying(100),
    address text,
    tax_code character varying(20),
    bank_account character varying(50),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


ALTER TABLE supermarket.suppliers OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 36740)
-- Name: suppliers_supplier_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.suppliers_supplier_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.suppliers_supplier_id_seq OWNER TO postgres;

--
-- TOC entry 5407 (class 0 OID 0)
-- Dependencies: 220
-- Name: suppliers_supplier_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.suppliers_supplier_id_seq OWNED BY supermarket.suppliers.supplier_id;


--
-- TOC entry 264 (class 1259 OID 37219)
-- Name: v_expiring_products; Type: VIEW; Schema: supermarket; Owner: postgres
--

CREATE VIEW supermarket.v_expiring_products AS
 SELECT p.product_id,
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
    (sbi.expiry_date - CURRENT_DATE) AS days_remaining
   FROM (((supermarket.shelf_batch_inventory sbi
     JOIN supermarket.products p ON ((sbi.product_id = p.product_id)))
     JOIN supermarket.product_categories c ON ((p.category_id = c.category_id)))
     JOIN supermarket.display_shelves ds ON ((sbi.shelf_id = ds.shelf_id)))
  WHERE ((sbi.expiry_date <= (CURRENT_DATE + '7 days'::interval)) AND (sbi.quantity > 0))
  ORDER BY sbi.expiry_date;


ALTER VIEW supermarket.v_expiring_products OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 36861)
-- Name: warehouse_inventory; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.warehouse_inventory (
    inventory_id bigint NOT NULL,
    warehouse_id bigint DEFAULT 1 NOT NULL,
    product_id bigint NOT NULL,
    batch_code character varying(50) NOT NULL,
    quantity bigint DEFAULT 0 NOT NULL,
    import_date date DEFAULT CURRENT_DATE NOT NULL,
    expiry_date date,
    import_price numeric(12,2) NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT chk_warehouse_inventory_quantity CHECK ((quantity >= 0))
);


ALTER TABLE supermarket.warehouse_inventory OWNER TO postgres;

--
-- TOC entry 262 (class 1259 OID 37209)
-- Name: v_low_shelf_products; Type: VIEW; Schema: supermarket; Owner: postgres
--

CREATE VIEW supermarket.v_low_shelf_products AS
 SELECT p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    p.low_stock_threshold,
    COALESCE(wi.total_warehouse, (0)::numeric) AS warehouse_quantity,
    COALESCE(si.total_shelf, (0)::numeric) AS shelf_quantity,
    (COALESCE(wi.total_warehouse, (0)::numeric) + COALESCE(si.total_shelf, (0)::numeric)) AS total_quantity,
        CASE
            WHEN (p.low_stock_threshold > 0) THEN round(((100.0 * COALESCE(si.total_shelf, (0)::numeric)) / (p.low_stock_threshold)::numeric), 2)
            ELSE (0)::numeric
        END AS shelf_fill_percentage
   FROM (((supermarket.products p
     LEFT JOIN supermarket.product_categories c ON ((p.category_id = c.category_id)))
     LEFT JOIN ( SELECT warehouse_inventory.product_id,
            sum(warehouse_inventory.quantity) AS total_warehouse
           FROM supermarket.warehouse_inventory
          GROUP BY warehouse_inventory.product_id) wi ON ((p.product_id = wi.product_id)))
     LEFT JOIN ( SELECT shelf_inventory.product_id,
            sum(shelf_inventory.current_quantity) AS total_shelf
           FROM supermarket.shelf_inventory
          GROUP BY shelf_inventory.product_id) si ON ((p.product_id = si.product_id)))
  WHERE ((COALESCE(si.total_shelf, (0)::numeric) < (p.low_stock_threshold)::numeric) AND (COALESCE(wi.total_warehouse, (0)::numeric) > (0)::numeric) AND (p.low_stock_threshold > 0))
  ORDER BY
        CASE
            WHEN (p.low_stock_threshold > 0) THEN round(((100.0 * COALESCE(si.total_shelf, (0)::numeric)) / (p.low_stock_threshold)::numeric), 2)
            ELSE (0)::numeric
        END, si.total_shelf;


ALTER VIEW supermarket.v_low_shelf_products OWNER TO postgres;

--
-- TOC entry 261 (class 1259 OID 37204)
-- Name: v_low_stock_products; Type: VIEW; Schema: supermarket; Owner: postgres
--

CREATE VIEW supermarket.v_low_stock_products AS
 SELECT p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    p.low_stock_threshold,
    COALESCE(wi.total_warehouse, (0)::numeric) AS warehouse_quantity,
    COALESCE(si.total_shelf, (0)::numeric) AS shelf_quantity,
    (COALESCE(wi.total_warehouse, (0)::numeric) + COALESCE(si.total_shelf, (0)::numeric)) AS total_quantity
   FROM (((supermarket.products p
     LEFT JOIN supermarket.product_categories c ON ((p.category_id = c.category_id)))
     LEFT JOIN ( SELECT warehouse_inventory.product_id,
            sum(warehouse_inventory.quantity) AS total_warehouse
           FROM supermarket.warehouse_inventory
          GROUP BY warehouse_inventory.product_id) wi ON ((p.product_id = wi.product_id)))
     LEFT JOIN ( SELECT shelf_inventory.product_id,
            sum(shelf_inventory.current_quantity) AS total_shelf
           FROM supermarket.shelf_inventory
          GROUP BY shelf_inventory.product_id) si ON ((p.product_id = si.product_id)))
  WHERE ((COALESCE(wi.total_warehouse, (0)::numeric) + COALESCE(si.total_shelf, (0)::numeric)) < (p.low_stock_threshold)::numeric);


ALTER VIEW supermarket.v_low_stock_products OWNER TO postgres;

--
-- TOC entry 260 (class 1259 OID 37199)
-- Name: v_product_overview; Type: VIEW; Schema: supermarket; Owner: postgres
--

CREATE VIEW supermarket.v_product_overview AS
 SELECT p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    s.supplier_name,
    p.selling_price,
    p.import_price,
    COALESCE(wi.total_warehouse, (0)::numeric) AS warehouse_quantity,
    COALESCE(si.total_shelf, (0)::numeric) AS shelf_quantity,
    (COALESCE(wi.total_warehouse, (0)::numeric) + COALESCE(si.total_shelf, (0)::numeric)) AS total_quantity
   FROM ((((supermarket.products p
     LEFT JOIN supermarket.product_categories c ON ((p.category_id = c.category_id)))
     LEFT JOIN supermarket.suppliers s ON ((p.supplier_id = s.supplier_id)))
     LEFT JOIN ( SELECT warehouse_inventory.product_id,
            sum(warehouse_inventory.quantity) AS total_warehouse
           FROM supermarket.warehouse_inventory
          GROUP BY warehouse_inventory.product_id) wi ON ((p.product_id = wi.product_id)))
     LEFT JOIN ( SELECT shelf_inventory.product_id,
            sum(shelf_inventory.current_quantity) AS total_shelf
           FROM supermarket.shelf_inventory
          GROUP BY shelf_inventory.product_id) si ON ((p.product_id = si.product_id)));


ALTER VIEW supermarket.v_product_overview OWNER TO postgres;

--
-- TOC entry 265 (class 1259 OID 37224)
-- Name: v_product_revenue; Type: VIEW; Schema: supermarket; Owner: postgres
--

CREATE VIEW supermarket.v_product_revenue AS
 SELECT p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    sum(sid.quantity) AS total_sold,
    sum(sid.subtotal) AS total_revenue,
    count(DISTINCT si.invoice_id) AS transaction_count
   FROM (((supermarket.sales_invoice_details sid
     JOIN supermarket.products p ON ((sid.product_id = p.product_id)))
     JOIN supermarket.product_categories c ON ((p.category_id = c.category_id)))
     JOIN supermarket.sales_invoices si ON ((sid.invoice_id = si.invoice_id)))
  GROUP BY p.product_id, p.product_code, p.product_name, c.category_name;


ALTER VIEW supermarket.v_product_revenue OWNER TO postgres;

--
-- TOC entry 268 (class 1259 OID 37239)
-- Name: v_shelf_status; Type: VIEW; Schema: supermarket; Owner: postgres
--

CREATE VIEW supermarket.v_shelf_status AS
 SELECT ds.shelf_id,
    ds.shelf_name,
    pc.category_name,
    ds.location,
    count(si.product_id) AS product_count,
    sum(si.current_quantity) AS total_items,
    sum(sl.max_quantity) AS total_capacity,
        CASE
            WHEN (sum(sl.max_quantity) > (0)::numeric) THEN round(((100.0 * sum(si.current_quantity)) / sum(sl.max_quantity)), 2)
            ELSE (0)::numeric
        END AS fill_percentage
   FROM (((supermarket.display_shelves ds
     JOIN supermarket.product_categories pc ON ((ds.category_id = pc.category_id)))
     LEFT JOIN supermarket.shelf_inventory si ON ((ds.shelf_id = si.shelf_id)))
     LEFT JOIN supermarket.shelf_layout sl ON ((ds.shelf_id = sl.shelf_id)))
  GROUP BY ds.shelf_id, ds.shelf_name, pc.category_name, ds.location;


ALTER VIEW supermarket.v_shelf_status OWNER TO postgres;

--
-- TOC entry 266 (class 1259 OID 37229)
-- Name: v_supplier_revenue; Type: VIEW; Schema: supermarket; Owner: postgres
--

CREATE VIEW supermarket.v_supplier_revenue AS
 SELECT s.supplier_id,
    s.supplier_name,
    s.contact_person,
    count(DISTINCT p.product_id) AS product_count,
    sum(pr.total_sold) AS total_units_sold,
    sum(pr.total_revenue) AS total_revenue
   FROM ((supermarket.suppliers s
     JOIN supermarket.products p ON ((s.supplier_id = p.supplier_id)))
     LEFT JOIN supermarket.v_product_revenue pr ON ((p.product_id = pr.product_id)))
  GROUP BY s.supplier_id, s.supplier_name, s.contact_person
  ORDER BY (sum(pr.total_revenue)) DESC NULLS LAST;


ALTER VIEW supermarket.v_supplier_revenue OWNER TO postgres;

--
-- TOC entry 267 (class 1259 OID 37234)
-- Name: v_vip_customers; Type: VIEW; Schema: supermarket; Owner: postgres
--

CREATE VIEW supermarket.v_vip_customers AS
 SELECT c.customer_id,
    c.full_name,
    c.phone,
    c.email,
    ml.level_name AS membership_level,
    c.total_spending,
    c.loyalty_points,
    count(si.invoice_id) AS purchase_count,
    max(si.invoice_date) AS last_purchase
   FROM ((supermarket.customers c
     LEFT JOIN supermarket.membership_levels ml ON ((c.membership_level_id = ml.level_id)))
     LEFT JOIN supermarket.sales_invoices si ON ((c.customer_id = si.customer_id)))
  GROUP BY c.customer_id, c.full_name, c.phone, c.email, ml.level_name, c.total_spending, c.loyalty_points
  ORDER BY c.total_spending DESC;


ALTER VIEW supermarket.v_vip_customers OWNER TO postgres;

--
-- TOC entry 263 (class 1259 OID 37214)
-- Name: v_warehouse_empty_products; Type: VIEW; Schema: supermarket; Owner: postgres
--

CREATE VIEW supermarket.v_warehouse_empty_products AS
 SELECT p.product_id,
    p.product_code,
    p.product_name,
    c.category_name,
    p.low_stock_threshold,
    COALESCE(wi.total_warehouse, (0)::numeric) AS warehouse_quantity,
    COALESCE(si.total_shelf, (0)::numeric) AS shelf_quantity,
    (COALESCE(wi.total_warehouse, (0)::numeric) + COALESCE(si.total_shelf, (0)::numeric)) AS total_quantity,
        CASE
            WHEN (p.low_stock_threshold > 0) THEN round(((100.0 * COALESCE(si.total_shelf, (0)::numeric)) / (p.low_stock_threshold)::numeric), 2)
            ELSE (0)::numeric
        END AS shelf_fill_percentage
   FROM (((supermarket.products p
     LEFT JOIN supermarket.product_categories c ON ((p.category_id = c.category_id)))
     LEFT JOIN ( SELECT warehouse_inventory.product_id,
            sum(warehouse_inventory.quantity) AS total_warehouse
           FROM supermarket.warehouse_inventory
          GROUP BY warehouse_inventory.product_id) wi ON ((p.product_id = wi.product_id)))
     LEFT JOIN ( SELECT shelf_inventory.product_id,
            sum(shelf_inventory.current_quantity) AS total_shelf
           FROM supermarket.shelf_inventory
          GROUP BY shelf_inventory.product_id) si ON ((p.product_id = si.product_id)))
  WHERE ((COALESCE(wi.total_warehouse, (0)::numeric) = (0)::numeric) AND (COALESCE(si.total_shelf, (0)::numeric) > (0)::numeric))
  ORDER BY si.total_shelf DESC;


ALTER VIEW supermarket.v_warehouse_empty_products OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 36753)
-- Name: warehouse; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.warehouse (
    warehouse_id bigint NOT NULL,
    warehouse_code character varying(20) NOT NULL,
    warehouse_name character varying(100) NOT NULL,
    location character varying(200),
    manager_name character varying(100),
    capacity bigint,
    created_at timestamp with time zone
);


ALTER TABLE supermarket.warehouse OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 36860)
-- Name: warehouse_inventory_inventory_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.warehouse_inventory_inventory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.warehouse_inventory_inventory_id_seq OWNER TO postgres;

--
-- TOC entry 5419 (class 0 OID 0)
-- Dependencies: 238
-- Name: warehouse_inventory_inventory_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.warehouse_inventory_inventory_id_seq OWNED BY supermarket.warehouse_inventory.inventory_id;


--
-- TOC entry 222 (class 1259 OID 36752)
-- Name: warehouse_warehouse_id_seq; Type: SEQUENCE; Schema: supermarket; Owner: postgres
--

CREATE SEQUENCE supermarket.warehouse_warehouse_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE supermarket.warehouse_warehouse_id_seq OWNER TO postgres;

--
-- TOC entry 5420 (class 0 OID 0)
-- Dependencies: 222
-- Name: warehouse_warehouse_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.warehouse_warehouse_id_seq OWNED BY supermarket.warehouse.warehouse_id;


--
-- TOC entry 4967 (class 2604 OID 36989)
-- Name: activity_logs log_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.activity_logs ALTER COLUMN log_id SET DEFAULT nextval('supermarket.activity_logs_log_id_seq'::regclass);


--
-- TOC entry 4929 (class 2604 OID 36840)
-- Name: customers customer_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.customers ALTER COLUMN customer_id SET DEFAULT nextval('supermarket.customers_customer_id_seq'::regclass);


--
-- TOC entry 4922 (class 2604 OID 36804)
-- Name: discount_rules rule_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.discount_rules ALTER COLUMN rule_id SET DEFAULT nextval('supermarket.discount_rules_rule_id_seq'::regclass);


--
-- TOC entry 4924 (class 2604 OID 36813)
-- Name: display_shelves shelf_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.display_shelves ALTER COLUMN shelf_id SET DEFAULT nextval('supermarket.display_shelves_shelf_id_seq'::regclass);


--
-- TOC entry 4948 (class 2604 OID 36908)
-- Name: employee_work_hours work_hour_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employee_work_hours ALTER COLUMN work_hour_id SET DEFAULT nextval('supermarket.employee_work_hours_work_hour_id_seq'::regclass);


--
-- TOC entry 4926 (class 2604 OID 36823)
-- Name: employees employee_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employees ALTER COLUMN employee_id SET DEFAULT nextval('supermarket.employees_employee_id_seq'::regclass);


--
-- TOC entry 4915 (class 2604 OID 36776)
-- Name: membership_levels level_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.membership_levels ALTER COLUMN level_id SET DEFAULT nextval('supermarket.membership_levels_level_id_seq'::regclass);


--
-- TOC entry 4914 (class 2604 OID 36765)
-- Name: positions position_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.positions ALTER COLUMN position_id SET DEFAULT nextval('supermarket.positions_position_id_seq'::regclass);


--
-- TOC entry 4910 (class 2604 OID 36733)
-- Name: product_categories category_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.product_categories ALTER COLUMN category_id SET DEFAULT nextval('supermarket.product_categories_category_id_seq'::regclass);


--
-- TOC entry 4919 (class 2604 OID 36788)
-- Name: products product_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.products ALTER COLUMN product_id SET DEFAULT nextval('supermarket.products_product_id_seq'::regclass);


--
-- TOC entry 4964 (class 2604 OID 36957)
-- Name: purchase_order_details detail_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_order_details ALTER COLUMN detail_id SET DEFAULT nextval('supermarket.purchase_order_details_detail_id_seq'::regclass);


--
-- TOC entry 4957 (class 2604 OID 36933)
-- Name: purchase_orders order_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_orders ALTER COLUMN order_id SET DEFAULT nextval('supermarket.purchase_orders_order_id_seq'::regclass);


--
-- TOC entry 4961 (class 2604 OID 36947)
-- Name: sales_invoice_details detail_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoice_details ALTER COLUMN detail_id SET DEFAULT nextval('supermarket.sales_invoice_details_detail_id_seq'::regclass);


--
-- TOC entry 4949 (class 2604 OID 36915)
-- Name: sales_invoices invoice_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoices ALTER COLUMN invoice_id SET DEFAULT nextval('supermarket.sales_invoices_invoice_id_seq'::regclass);


--
-- TOC entry 4944 (class 2604 OID 36897)
-- Name: shelf_batch_inventory shelf_batch_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_batch_inventory ALTER COLUMN shelf_batch_id SET DEFAULT nextval('supermarket.shelf_batch_inventory_shelf_batch_id_seq'::regclass);


--
-- TOC entry 4939 (class 2604 OID 36883)
-- Name: shelf_inventory shelf_inventory_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_inventory ALTER COLUMN shelf_inventory_id SET DEFAULT nextval('supermarket.shelf_inventory_shelf_inventory_id_seq'::regclass);


--
-- TOC entry 4938 (class 2604 OID 36875)
-- Name: shelf_layout layout_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_layout ALTER COLUMN layout_id SET DEFAULT nextval('supermarket.shelf_layout_layout_id_seq'::regclass);


--
-- TOC entry 4965 (class 2604 OID 36965)
-- Name: stock_transfers transfer_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers ALTER COLUMN transfer_id SET DEFAULT nextval('supermarket.stock_transfers_transfer_id_seq'::regclass);


--
-- TOC entry 4911 (class 2604 OID 36744)
-- Name: suppliers supplier_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.suppliers ALTER COLUMN supplier_id SET DEFAULT nextval('supermarket.suppliers_supplier_id_seq'::regclass);


--
-- TOC entry 4913 (class 2604 OID 36756)
-- Name: warehouse warehouse_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse ALTER COLUMN warehouse_id SET DEFAULT nextval('supermarket.warehouse_warehouse_id_seq'::regclass);


--
-- TOC entry 4934 (class 2604 OID 36864)
-- Name: warehouse_inventory inventory_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse_inventory ALTER COLUMN inventory_id SET DEFAULT nextval('supermarket.warehouse_inventory_inventory_id_seq'::regclass);


--
-- TOC entry 5364 (class 0 OID 36986)
-- Dependencies: 259
-- Data for Name: activity_logs; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.activity_logs (log_id, activity_type, description, table_name, record_id, user_id, user_name, ip_address, created_at) FROM stdin;
1	PRODUCT_CREATED	Sản phẩm mới được tạo: Bút bi Thiên Long (Mã: VPP001)	products	1	\N	\N	\N	2025-09-28 03:46:20.781594+07
2	PRODUCT_CREATED	Sản phẩm mới được tạo: Vở học sinh 96 trang (Mã: VPP002)	products	2	\N	\N	\N	2025-09-28 03:46:20.781594+07
3	PRODUCT_CREATED	Sản phẩm mới được tạo: Bút chì 2B (Mã: VPP003)	products	3	\N	\N	\N	2025-09-28 03:46:20.781594+07
4	PRODUCT_CREATED	Sản phẩm mới được tạo: Thước kẻ nhựa 30cm (Mã: VPP004)	products	4	\N	\N	\N	2025-09-28 03:46:20.781594+07
5	PRODUCT_CREATED	Sản phẩm mới được tạo: Gôm tẩy Hồng Hà (Mã: VPP005)	products	5	\N	\N	\N	2025-09-28 03:46:20.781594+07
6	PRODUCT_CREATED	Sản phẩm mới được tạo: Bút máy học sinh (Mã: VPP006)	products	6	\N	\N	\N	2025-09-28 03:46:20.781594+07
7	PRODUCT_CREATED	Sản phẩm mới được tạo: Giấy A4 Double A (Mã: VPP007)	products	7	\N	\N	\N	2025-09-28 03:46:20.781594+07
8	PRODUCT_CREATED	Sản phẩm mới được tạo: Keo dán UHU (Mã: VPP008)	products	8	\N	\N	\N	2025-09-28 03:46:20.781594+07
9	PRODUCT_CREATED	Sản phẩm mới được tạo: Bìa hồ sơ (Mã: VPP009)	products	9	\N	\N	\N	2025-09-28 03:46:20.781594+07
10	PRODUCT_CREATED	Sản phẩm mới được tạo: Kẹp giấy (Mã: VPP010)	products	10	\N	\N	\N	2025-09-28 03:46:20.781594+07
11	PRODUCT_CREATED	Sản phẩm mới được tạo: Bút dạ quang (Mã: VPP011)	products	11	\N	\N	\N	2025-09-28 03:46:20.781594+07
12	PRODUCT_CREATED	Sản phẩm mới được tạo: Stapler kim bấm (Mã: VPP012)	products	12	\N	\N	\N	2025-09-28 03:46:20.781594+07
13	PRODUCT_CREATED	Sản phẩm mới được tạo: Kim bấm số 10 (Mã: VPP013)	products	13	\N	\N	\N	2025-09-28 03:46:20.781594+07
14	PRODUCT_CREATED	Sản phẩm mới được tạo: Bảng viết bút lông (Mã: VPP014)	products	14	\N	\N	\N	2025-09-28 03:46:20.781594+07
15	PRODUCT_CREATED	Sản phẩm mới được tạo: Máy tính Casio FX-580 (Mã: VPP015)	products	15	\N	\N	\N	2025-09-28 03:46:20.781594+07
16	PRODUCT_CREATED	Sản phẩm mới được tạo: Chảo chống dính 26cm (Mã: GD001)	products	16	\N	\N	\N	2025-09-28 03:46:20.781594+07
17	PRODUCT_CREATED	Sản phẩm mới được tạo: Bộ nồi inox 3 món (Mã: GD002)	products	17	\N	\N	\N	2025-09-28 03:46:20.781594+07
18	PRODUCT_CREATED	Sản phẩm mới được tạo: Khăn tắm cotton (Mã: GD003)	products	18	\N	\N	\N	2025-09-28 03:46:20.781594+07
19	PRODUCT_CREATED	Sản phẩm mới được tạo: Bộ dao inox 6 món (Mã: GD004)	products	19	\N	\N	\N	2025-09-28 03:46:20.781594+07
20	PRODUCT_CREATED	Sản phẩm mới được tạo: Thớt gỗ cao su (Mã: GD005)	products	20	\N	\N	\N	2025-09-28 03:46:20.781594+07
21	PRODUCT_CREATED	Sản phẩm mới được tạo: Bộ chén đĩa sứ (Mã: GD006)	products	21	\N	\N	\N	2025-09-28 03:46:20.781594+07
22	PRODUCT_CREATED	Sản phẩm mới được tạo: Gương soi trang điểm (Mã: GD007)	products	22	\N	\N	\N	2025-09-28 03:46:20.781594+07
23	PRODUCT_CREATED	Sản phẩm mới được tạo: Thùng rác có nắp (Mã: GD008)	products	23	\N	\N	\N	2025-09-28 03:46:20.781594+07
24	PRODUCT_CREATED	Sản phẩm mới được tạo: Dây phơi quần áo (Mã: GD009)	products	24	\N	\N	\N	2025-09-28 03:46:20.781594+07
25	PRODUCT_CREATED	Sản phẩm mới được tạo: Bộ ly thủy tinh (Mã: GD010)	products	25	\N	\N	\N	2025-09-28 03:46:20.781594+07
26	PRODUCT_CREATED	Sản phẩm mới được tạo: Giá để giày dép (Mã: GD011)	products	26	\N	\N	\N	2025-09-28 03:46:20.781594+07
27	PRODUCT_CREATED	Sản phẩm mới được tạo: Rổ đựng đồ đa năng (Mã: GD012)	products	27	\N	\N	\N	2025-09-28 03:46:20.781594+07
28	PRODUCT_CREATED	Sản phẩm mới được tạo: Kệ gia vị 3 tầng (Mã: GD013)	products	28	\N	\N	\N	2025-09-28 03:46:20.781594+07
29	PRODUCT_CREATED	Sản phẩm mới được tạo: Bàn ủi hơi nước (Mã: GD014)	products	29	\N	\N	\N	2025-09-28 03:46:20.781594+07
30	PRODUCT_CREATED	Sản phẩm mới được tạo: Tủ nhựa 5 ngăn (Mã: GD015)	products	30	\N	\N	\N	2025-09-28 03:46:20.781594+07
31	PRODUCT_CREATED	Sản phẩm mới được tạo: Tai nghe Bluetooth (Mã: DT001)	products	31	\N	\N	\N	2025-09-28 03:46:20.781594+07
32	PRODUCT_CREATED	Sản phẩm mới được tạo: Sạc dự phòng 10000mAh (Mã: DT002)	products	32	\N	\N	\N	2025-09-28 03:46:20.781594+07
33	PRODUCT_CREATED	Sản phẩm mới được tạo: Cáp USB Type-C (Mã: DT003)	products	33	\N	\N	\N	2025-09-28 03:46:20.781594+07
34	PRODUCT_CREATED	Sản phẩm mới được tạo: Loa Bluetooth mini (Mã: DT004)	products	34	\N	\N	\N	2025-09-28 03:46:20.781594+07
35	PRODUCT_CREATED	Sản phẩm mới được tạo: Chuột không dây (Mã: DT005)	products	35	\N	\N	\N	2025-09-28 03:46:20.781594+07
36	PRODUCT_CREATED	Sản phẩm mới được tạo: Bàn phím gaming (Mã: DT006)	products	36	\N	\N	\N	2025-09-28 03:46:20.781594+07
37	PRODUCT_CREATED	Sản phẩm mới được tạo: Webcam HD 720p (Mã: DT007)	products	37	\N	\N	\N	2025-09-28 03:46:20.781594+07
38	PRODUCT_CREATED	Sản phẩm mới được tạo: Đèn LED USB (Mã: DT008)	products	38	\N	\N	\N	2025-09-28 03:46:20.781594+07
39	PRODUCT_CREATED	Sản phẩm mới được tạo: Hub USB 4 cổng (Mã: DT009)	products	39	\N	\N	\N	2025-09-28 03:46:20.781594+07
40	PRODUCT_CREATED	Sản phẩm mới được tạo: Thẻ nhớ MicroSD 32GB (Mã: DT010)	products	40	\N	\N	\N	2025-09-28 03:46:20.781594+07
41	PRODUCT_CREATED	Sản phẩm mới được tạo: Giá đỡ điện thoại (Mã: DT011)	products	41	\N	\N	\N	2025-09-28 03:46:20.781594+07
42	PRODUCT_CREATED	Sản phẩm mới được tạo: Ốp lưng iPhone (Mã: DT012)	products	42	\N	\N	\N	2025-09-28 03:46:20.781594+07
43	PRODUCT_CREATED	Sản phẩm mới được tạo: Miếng dán màn hình (Mã: DT013)	products	43	\N	\N	\N	2025-09-28 03:46:20.781594+07
44	PRODUCT_CREATED	Sản phẩm mới được tạo: Pin AA Panasonic (Mã: DT014)	products	44	\N	\N	\N	2025-09-28 03:46:20.781594+07
45	PRODUCT_CREATED	Sản phẩm mới được tạo: Đồng hồ thông minh (Mã: DT015)	products	45	\N	\N	\N	2025-09-28 03:46:20.781594+07
46	PRODUCT_CREATED	Sản phẩm mới được tạo: Nồi cơm điện 1.8L (Mã: DB001)	products	46	\N	\N	\N	2025-09-28 03:46:20.781594+07
47	PRODUCT_CREATED	Sản phẩm mới được tạo: Máy xay sinh tố (Mã: DB002)	products	47	\N	\N	\N	2025-09-28 03:46:20.781594+07
48	PRODUCT_CREATED	Sản phẩm mới được tạo: Ấm đun nước siêu tốc (Mã: DB003)	products	48	\N	\N	\N	2025-09-28 03:46:20.781594+07
49	PRODUCT_CREATED	Sản phẩm mới được tạo: Bếp gas hồng ngoại (Mã: DB004)	products	49	\N	\N	\N	2025-09-28 03:46:20.781594+07
50	PRODUCT_CREATED	Sản phẩm mới được tạo: Lò vi sóng 20L (Mã: DB005)	products	50	\N	\N	\N	2025-09-28 03:46:20.781594+07
51	PRODUCT_CREATED	Sản phẩm mới được tạo: Máy pha cà phê (Mã: DB006)	products	51	\N	\N	\N	2025-09-28 03:46:20.781594+07
52	PRODUCT_CREATED	Sản phẩm mới được tạo: Nồi áp suất 5L (Mã: DB007)	products	52	\N	\N	\N	2025-09-28 03:46:20.781594+07
53	PRODUCT_CREATED	Sản phẩm mới được tạo: Máy nướng bánh mì (Mã: DB008)	products	53	\N	\N	\N	2025-09-28 03:46:20.781594+07
54	PRODUCT_CREATED	Sản phẩm mới được tạo: Bộ dao thớt inox (Mã: DB009)	products	54	\N	\N	\N	2025-09-28 03:46:20.781594+07
55	PRODUCT_CREATED	Sản phẩm mới được tạo: Máy đánh trứng cầm tay (Mã: DB010)	products	55	\N	\N	\N	2025-09-28 03:46:20.781594+07
56	PRODUCT_CREATED	Sản phẩm mới được tạo: Gạo ST25 5kg (Mã: TP001)	products	56	\N	\N	\N	2025-09-28 03:46:20.781594+07
57	PRODUCT_CREATED	Sản phẩm mới được tạo: Mì gói Hảo Hảo (Mã: TP002)	products	57	\N	\N	\N	2025-09-28 03:46:20.781594+07
58	PRODUCT_CREATED	Sản phẩm mới được tạo: Dầu ăn Tường An 1L (Mã: TP003)	products	58	\N	\N	\N	2025-09-28 03:46:20.781594+07
59	PRODUCT_CREATED	Sản phẩm mới được tạo: Muối I-ốt 500g (Mã: TP004)	products	59	\N	\N	\N	2025-09-28 03:46:20.781594+07
60	PRODUCT_CREATED	Sản phẩm mới được tạo: Đường cát trắng 1kg (Mã: TP005)	products	60	\N	\N	\N	2025-09-28 03:46:20.781594+07
61	PRODUCT_CREATED	Sản phẩm mới được tạo: Nước mắm Phú Quốc (Mã: TP006)	products	61	\N	\N	\N	2025-09-28 03:46:20.781594+07
62	PRODUCT_CREATED	Sản phẩm mới được tạo: Bột mì đa dụng 1kg (Mã: TP007)	products	62	\N	\N	\N	2025-09-28 03:46:20.781594+07
63	PRODUCT_CREATED	Sản phẩm mới được tạo: Bánh quy Oreo (Mã: TP008)	products	63	\N	\N	\N	2025-09-28 03:46:20.781594+07
64	PRODUCT_CREATED	Sản phẩm mới được tạo: Cà rốt 1kg (Mã: TP009)	products	64	\N	\N	\N	2025-09-28 03:46:20.781594+07
65	PRODUCT_CREATED	Sản phẩm mới được tạo: Khoai tây 1kg (Mã: TP010)	products	65	\N	\N	\N	2025-09-28 03:46:20.781594+07
66	PRODUCT_CREATED	Sản phẩm mới được tạo: Bắp cải 1kg (Mã: TP011)	products	66	\N	\N	\N	2025-09-28 03:46:20.781594+07
67	PRODUCT_CREATED	Sản phẩm mới được tạo: Táo Fuji 1kg (Mã: TP012)	products	67	\N	\N	\N	2025-09-28 03:46:20.781594+07
68	PRODUCT_CREATED	Sản phẩm mới được tạo: Chuối tiêu 1kg (Mã: TP013)	products	68	\N	\N	\N	2025-09-28 03:46:20.781594+07
69	PRODUCT_CREATED	Sản phẩm mới được tạo: Thịt heo ba chỉ 500g (Mã: TP014)	products	69	\N	\N	\N	2025-09-28 03:46:20.781594+07
70	PRODUCT_CREATED	Sản phẩm mới được tạo: Cá thu đông lạnh (Mã: TP015)	products	70	\N	\N	\N	2025-09-28 03:46:20.781594+07
71	PRODUCT_CREATED	Sản phẩm mới được tạo: Tôm đông lạnh 500g (Mã: TP016)	products	71	\N	\N	\N	2025-09-28 03:46:20.781594+07
72	PRODUCT_CREATED	Sản phẩm mới được tạo: Xúc xích Đức Việt (Mã: TP017)	products	72	\N	\N	\N	2025-09-28 03:46:20.781594+07
73	PRODUCT_CREATED	Sản phẩm mới được tạo: Trứng gà hộp 10 quả (Mã: TP018)	products	73	\N	\N	\N	2025-09-28 03:46:20.781594+07
74	PRODUCT_CREATED	Sản phẩm mới được tạo: Sữa tươi Vinamilk 1L (Mã: TP019)	products	74	\N	\N	\N	2025-09-28 03:46:20.781594+07
75	PRODUCT_CREATED	Sản phẩm mới được tạo: Phô mai lát Laughing Cow (Mã: TP020)	products	75	\N	\N	\N	2025-09-28 03:46:20.781594+07
76	PRODUCT_CREATED	Sản phẩm mới được tạo: Bia Saigon lon 330ml (Mã: DU001)	products	76	\N	\N	\N	2025-09-28 03:46:20.781594+07
77	PRODUCT_CREATED	Sản phẩm mới được tạo: Bia Heineken lon 330ml (Mã: DU002)	products	77	\N	\N	\N	2025-09-28 03:46:20.781594+07
78	PRODUCT_CREATED	Sản phẩm mới được tạo: Rượu vang Đà Lạt (Mã: DU003)	products	78	\N	\N	\N	2025-09-28 03:46:20.781594+07
79	PRODUCT_CREATED	Sản phẩm mới được tạo: Nước suối Aquafina 500ml (Mã: DU004)	products	79	\N	\N	\N	2025-09-28 03:46:20.781594+07
80	PRODUCT_CREATED	Sản phẩm mới được tạo: Coca Cola 330ml (Mã: DU005)	products	80	\N	\N	\N	2025-09-28 03:46:20.781594+07
81	PRODUCT_CREATED	Sản phẩm mới được tạo: Pepsi lon 330ml (Mã: DU006)	products	81	\N	\N	\N	2025-09-28 03:46:20.781594+07
82	PRODUCT_CREATED	Sản phẩm mới được tạo: Nước cam Tropicana (Mã: DU007)	products	82	\N	\N	\N	2025-09-28 03:46:20.781594+07
83	PRODUCT_CREATED	Sản phẩm mới được tạo: Nước dừa Cocoxim (Mã: DU008)	products	83	\N	\N	\N	2025-09-28 03:46:20.781594+07
84	PRODUCT_CREATED	Sản phẩm mới được tạo: Nước tăng lực RedBull (Mã: DU009)	products	84	\N	\N	\N	2025-09-28 03:46:20.781594+07
85	PRODUCT_CREATED	Sản phẩm mới được tạo: Sữa chua uống TH (Mã: DU010)	products	85	\N	\N	\N	2025-09-28 03:46:20.781594+07
86	PRODUCT_CREATED	Sản phẩm mới được tạo: Nước khoáng LaVie (Mã: DU011)	products	86	\N	\N	\N	2025-09-28 03:46:20.781594+07
87	PRODUCT_CREATED	Sản phẩm mới được tạo: Cà phê Nescafe Gold (Mã: DU012)	products	87	\N	\N	\N	2025-09-28 03:46:20.781594+07
88	PRODUCT_CREATED	Sản phẩm mới được tạo: Trà xanh không độ (Mã: DU013)	products	88	\N	\N	\N	2025-09-28 03:46:20.781594+07
89	PRODUCT_CREATED	Sản phẩm mới được tạo: Trà đá Lipton chai (Mã: DU014)	products	89	\N	\N	\N	2025-09-28 03:46:20.781594+07
90	PRODUCT_CREATED	Sản phẩm mới được tạo: Trà sữa Lipton (Mã: DU015)	products	90	\N	\N	\N	2025-09-28 03:46:20.781594+07
91	PRODUCT_CREATED	Sản phẩm mới được tạo: Kem chống nắng Nivea (Mã: MP001)	products	91	\N	\N	\N	2025-09-28 03:46:20.781594+07
92	PRODUCT_CREATED	Sản phẩm mới được tạo: Sữa rửa mặt Cetaphil (Mã: MP002)	products	92	\N	\N	\N	2025-09-28 03:46:20.781594+07
93	PRODUCT_CREATED	Sản phẩm mới được tạo: Nước hoa hồng Mamonde (Mã: MP003)	products	93	\N	\N	\N	2025-09-28 03:46:20.781594+07
94	PRODUCT_CREATED	Sản phẩm mới được tạo: Kem dưỡng da Olay (Mã: MP004)	products	94	\N	\N	\N	2025-09-28 03:46:20.781594+07
95	PRODUCT_CREATED	Sản phẩm mới được tạo: Son dưỡng môi Vaseline (Mã: MP005)	products	95	\N	\N	\N	2025-09-28 03:46:20.781594+07
96	PRODUCT_CREATED	Sản phẩm mới được tạo: Mascara Maybelline (Mã: MP006)	products	96	\N	\N	\N	2025-09-28 03:46:20.781594+07
97	PRODUCT_CREATED	Sản phẩm mới được tạo: Phấn phủ L'Oreal (Mã: MP007)	products	97	\N	\N	\N	2025-09-28 03:46:20.781594+07
98	PRODUCT_CREATED	Sản phẩm mới được tạo: Dầu gội Head & Shoulders (Mã: MP008)	products	98	\N	\N	\N	2025-09-28 03:46:20.781594+07
99	PRODUCT_CREATED	Sản phẩm mới được tạo: Kem đánh răng Colgate (Mã: MP009)	products	99	\N	\N	\N	2025-09-28 03:46:20.781594+07
100	PRODUCT_CREATED	Sản phẩm mới được tạo: Xịt khử mùi Rexona (Mã: MP010)	products	100	\N	\N	\N	2025-09-28 03:46:20.781594+07
101	PRODUCT_CREATED	Sản phẩm mới được tạo: Quần jean nam (Mã: TT001)	products	101	\N	\N	\N	2025-09-28 03:46:20.781594+07
102	PRODUCT_CREATED	Sản phẩm mới được tạo: Áo polo nam (Mã: TT002)	products	102	\N	\N	\N	2025-09-28 03:46:20.781594+07
103	PRODUCT_CREATED	Sản phẩm mới được tạo: Váy maxi nữ (Mã: TT003)	products	103	\N	\N	\N	2025-09-28 03:46:20.781594+07
104	PRODUCT_CREATED	Sản phẩm mới được tạo: Túi xách nữ (Mã: TT004)	products	104	\N	\N	\N	2025-09-28 03:46:20.781594+07
105	PRODUCT_CREATED	Sản phẩm mới được tạo: Áo thun cotton unisex (Mã: TT005)	products	105	\N	\N	\N	2025-09-28 03:46:20.781594+07
106	PRODUCT_CREATED	Sản phẩm mới được tạo: Dép tông nam nữ (Mã: TT006)	products	106	\N	\N	\N	2025-09-28 03:46:20.781594+07
107	PRODUCT_CREATED	Sản phẩm mới được tạo: Đồng hồ đeo tay (Mã: TT007)	products	107	\N	\N	\N	2025-09-28 03:46:20.781594+07
108	STOCK_TRANSFER	Chuyển hàng: Bếp gas hồng ngoại từ kho Kho chính lên quầy Quầy đồ bếp (SL: 47)	stock_transfers	1	\N	\N	\N	2025-09-28 03:46:20.921424+07
109	STOCK_TRANSFER	Chuyển hàng: Tai nghe Bluetooth từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 186)	stock_transfers	2	\N	\N	\N	2025-09-28 03:46:20.92822+07
110	STOCK_TRANSFER	Chuyển hàng: Loa Bluetooth mini từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 193)	stock_transfers	3	\N	\N	\N	2025-09-28 03:46:20.929647+07
111	STOCK_TRANSFER	Chuyển hàng: Bánh quy Oreo từ kho Kho chính lên quầy Quầy thực phẩm khô (SL: 137)	stock_transfers	4	\N	\N	\N	2025-09-28 03:46:20.931203+07
112	STOCK_TRANSFER	Chuyển hàng: Sữa chua uống TH từ kho Kho chính lên quầy Quầy đồ uống không cồn (SL: 96)	stock_transfers	5	\N	\N	\N	2025-09-28 03:46:20.932673+07
113	STOCK_TRANSFER	Chuyển hàng: Lò vi sóng 20L từ kho Kho chính lên quầy Quầy đồ bếp (SL: 178)	stock_transfers	6	\N	\N	\N	2025-09-28 03:46:20.934062+07
114	STOCK_TRANSFER	Chuyển hàng: Nước hoa hồng Mamonde từ kho Kho chính lên quầy Quầy mỹ phẩm (SL: 192)	stock_transfers	7	\N	\N	\N	2025-09-28 03:46:20.935385+07
115	STOCK_TRANSFER	Chuyển hàng: Bắp cải 1kg từ kho Kho chính lên quầy Quầy rau quả tươi (SL: 114)	stock_transfers	8	\N	\N	\N	2025-09-28 03:46:20.936468+07
116	STOCK_TRANSFER	Chuyển hàng: Dép tông nam nữ từ kho Kho chính lên quầy Quầy thời trang (SL: 111)	stock_transfers	9	\N	\N	\N	2025-09-28 03:46:20.937975+07
118	STOCK_TRANSFER	Chuyển hàng: Ốp lưng iPhone từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 128)	stock_transfers	11	\N	\N	\N	2025-09-28 03:46:20.939655+07
119	STOCK_TRANSFER	Chuyển hàng: Cà rốt 1kg từ kho Kho chính lên quầy Quầy rau quả tươi (SL: 71)	stock_transfers	12	\N	\N	\N	2025-09-28 03:46:20.940546+07
120	STOCK_TRANSFER	Chuyển hàng: Ấm đun nước siêu tốc từ kho Kho chính lên quầy Quầy đồ bếp (SL: 41)	stock_transfers	13	\N	\N	\N	2025-09-28 03:46:20.942094+07
121	STOCK_TRANSFER	Chuyển hàng: Bàn phím gaming từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 70)	stock_transfers	14	\N	\N	\N	2025-09-28 03:46:20.943078+07
123	STOCK_TRANSFER	Chuyển hàng: Kem chống nắng Nivea từ kho Kho chính lên quầy Quầy mỹ phẩm (SL: 166)	stock_transfers	16	\N	\N	\N	2025-09-28 03:46:20.944613+07
124	STOCK_TRANSFER	Chuyển hàng: Pepsi lon 330ml từ kho Kho chính lên quầy Quầy đồ uống không cồn (SL: 148)	stock_transfers	17	\N	\N	\N	2025-09-28 03:46:20.945738+07
125	STOCK_TRANSFER	Chuyển hàng: Bảng viết bút lông từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 151)	stock_transfers	18	\N	\N	\N	2025-09-28 03:46:20.946604+07
126	STOCK_TRANSFER	Chuyển hàng: Thùng rác có nắp từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 156)	stock_transfers	19	\N	\N	\N	2025-09-28 03:46:20.947773+07
127	STOCK_TRANSFER	Chuyển hàng: Bàn ủi hơi nước từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 34)	stock_transfers	20	\N	\N	\N	2025-09-28 03:46:20.948789+07
128	STOCK_TRANSFER	Chuyển hàng: Chuột không dây từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 65)	stock_transfers	21	\N	\N	\N	2025-09-28 03:46:20.949686+07
129	STOCK_TRANSFER	Chuyển hàng: Miếng dán màn hình từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 52)	stock_transfers	22	\N	\N	\N	2025-09-28 03:46:20.950573+07
130	STOCK_TRANSFER	Chuyển hàng: Mì gói Hảo Hảo từ kho Kho chính lên quầy Quầy thực phẩm khô (SL: 130)	stock_transfers	23	\N	\N	\N	2025-09-28 03:46:20.951362+07
131	STOCK_TRANSFER	Chuyển hàng: Chuối tiêu 1kg từ kho Kho chính lên quầy Quầy rau quả tươi (SL: 47)	stock_transfers	24	\N	\N	\N	2025-09-28 03:46:20.952165+07
132	STOCK_TRANSFER	Chuyển hàng: Dây phơi quần áo từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 187)	stock_transfers	25	\N	\N	\N	2025-09-28 03:46:20.953313+07
133	STOCK_TRANSFER	Chuyển hàng: Giá để giày dép từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 117)	stock_transfers	26	\N	\N	\N	2025-09-28 03:46:20.954375+07
134	STOCK_TRANSFER	Chuyển hàng: Thẻ nhớ MicroSD 32GB từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 117)	stock_transfers	27	\N	\N	\N	2025-09-28 03:46:20.955228+07
135	STOCK_TRANSFER	Chuyển hàng: Đồng hồ thông minh từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 111)	stock_transfers	28	\N	\N	\N	2025-09-28 03:46:20.956007+07
136	STOCK_TRANSFER	Chuyển hàng: Bột mì đa dụng 1kg từ kho Kho chính lên quầy Quầy thực phẩm khô (SL: 128)	stock_transfers	29	\N	\N	\N	2025-09-28 03:46:20.956784+07
137	STOCK_TRANSFER	Chuyển hàng: Kẹp giấy từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 73)	stock_transfers	30	\N	\N	\N	2025-09-28 03:46:20.958004+07
138	STOCK_TRANSFER	Chuyển hàng: Bộ nồi inox 3 món từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 49)	stock_transfers	31	\N	\N	\N	2025-09-28 03:46:20.958961+07
139	STOCK_TRANSFER	Chuyển hàng: Rổ đựng đồ đa năng từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 131)	stock_transfers	32	\N	\N	\N	2025-09-28 03:46:20.960105+07
140	STOCK_TRANSFER	Chuyển hàng: Muối I-ốt 500g từ kho Kho chính lên quầy Quầy thực phẩm khô (SL: 156)	stock_transfers	33	\N	\N	\N	2025-09-28 03:46:20.960903+07
142	STOCK_TRANSFER	Chuyển hàng: Nước mắm Phú Quốc từ kho Kho chính lên quầy Quầy thực phẩm khô (SL: 198)	stock_transfers	35	\N	\N	\N	2025-09-28 03:46:20.962356+07
143	STOCK_TRANSFER	Chuyển hàng: Giấy A4 Double A từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 55)	stock_transfers	36	\N	\N	\N	2025-09-28 03:46:20.963232+07
144	STOCK_TRANSFER	Chuyển hàng: Bút dạ quang từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 33)	stock_transfers	37	\N	\N	\N	2025-09-28 03:46:20.964501+07
145	STOCK_TRANSFER	Chuyển hàng: Áo thun cotton unisex từ kho Kho chính lên quầy Quầy thời trang (SL: 193)	stock_transfers	38	\N	\N	\N	2025-09-28 03:46:20.965662+07
146	STOCK_TRANSFER	Chuyển hàng: Nước khoáng LaVie từ kho Kho chính lên quầy Quầy đồ uống không cồn (SL: 99)	stock_transfers	39	\N	\N	\N	2025-09-28 03:46:20.966811+07
147	STOCK_TRANSFER	Chuyển hàng: Thước kẻ nhựa 30cm từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 87)	stock_transfers	40	\N	\N	\N	2025-09-28 03:46:20.967683+07
148	STOCK_TRANSFER	Chuyển hàng: Stapler kim bấm từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 114)	stock_transfers	41	\N	\N	\N	2025-09-28 03:46:20.968598+07
150	STOCK_TRANSFER	Chuyển hàng: Thớt gỗ cao su từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 48)	stock_transfers	43	\N	\N	\N	2025-09-28 03:46:20.970566+07
151	STOCK_TRANSFER	Chuyển hàng: Máy pha cà phê từ kho Kho chính lên quầy Quầy đồ bếp (SL: 132)	stock_transfers	44	\N	\N	\N	2025-09-28 03:46:20.971574+07
152	STOCK_TRANSFER	Chuyển hàng: Cáp USB Type-C từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 163)	stock_transfers	45	\N	\N	\N	2025-09-28 03:46:20.972432+07
153	STOCK_TRANSFER	Chuyển hàng: Gạo ST25 5kg từ kho Kho chính lên quầy Quầy thực phẩm khô (SL: 64)	stock_transfers	46	\N	\N	\N	2025-09-28 03:46:20.973247+07
154	STOCK_TRANSFER	Chuyển hàng: Gôm tẩy Hồng Hà từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 130)	stock_transfers	47	\N	\N	\N	2025-09-28 03:46:20.974251+07
155	STOCK_TRANSFER	Chuyển hàng: Đèn LED USB từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 134)	stock_transfers	48	\N	\N	\N	2025-09-28 03:46:20.975588+07
156	STOCK_TRANSFER	Chuyển hàng: Dầu ăn Tường An 1L từ kho Kho chính lên quầy Quầy thực phẩm khô (SL: 160)	stock_transfers	49	\N	\N	\N	2025-09-28 03:46:20.97654+07
157	STOCK_TRANSFER	Chuyển hàng: Bút chì 2B từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 185)	stock_transfers	50	\N	\N	\N	2025-09-28 03:46:20.977554+07
158	STOCK_TRANSFER	Chuyển hàng: Giá đỡ điện thoại từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 74)	stock_transfers	51	\N	\N	\N	2025-09-28 03:46:20.978702+07
159	STOCK_TRANSFER	Chuyển hàng: Táo Fuji 1kg từ kho Kho chính lên quầy Quầy rau quả tươi (SL: 166)	stock_transfers	52	\N	\N	\N	2025-09-28 03:46:20.979842+07
160	STOCK_TRANSFER	Chuyển hàng: Bộ ly thủy tinh từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 91)	stock_transfers	53	\N	\N	\N	2025-09-28 03:46:20.981653+07
161	STOCK_TRANSFER	Chuyển hàng: Kệ gia vị 3 tầng từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 52)	stock_transfers	54	\N	\N	\N	2025-09-28 03:46:20.982934+07
162	STOCK_TRANSFER	Chuyển hàng: Nồi áp suất 5L từ kho Kho chính lên quầy Quầy đồ bếp (SL: 56)	stock_transfers	55	\N	\N	\N	2025-09-28 03:46:20.983798+07
163	STOCK_TRANSFER	Chuyển hàng: Bộ dao thớt inox từ kho Kho chính lên quầy Quầy đồ bếp (SL: 156)	stock_transfers	56	\N	\N	\N	2025-09-28 03:46:20.984918+07
164	STOCK_TRANSFER	Chuyển hàng: Máy đánh trứng cầm tay từ kho Kho chính lên quầy Quầy đồ bếp (SL: 153)	stock_transfers	57	\N	\N	\N	2025-09-28 03:46:20.986439+07
167	STOCK_TRANSFER	Chuyển hàng: Nước tăng lực RedBull từ kho Kho chính lên quầy Quầy đồ uống không cồn (SL: 45)	stock_transfers	60	\N	\N	\N	2025-09-28 03:46:20.989199+07
168	STOCK_TRANSFER	Chuyển hàng: Sạc dự phòng 10000mAh từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 166)	stock_transfers	61	\N	\N	\N	2025-09-28 03:46:20.99003+07
169	STOCK_TRANSFER	Chuyển hàng: Pin AA Panasonic từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 190)	stock_transfers	62	\N	\N	\N	2025-09-28 03:46:20.990773+07
170	STOCK_TRANSFER	Chuyển hàng: Khoai tây 1kg từ kho Kho chính lên quầy Quầy rau quả tươi (SL: 141)	stock_transfers	63	\N	\N	\N	2025-09-28 03:46:20.991701+07
171	STOCK_TRANSFER	Chuyển hàng: Bút bi Thiên Long từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 174)	stock_transfers	64	\N	\N	\N	2025-09-28 03:46:20.993256+07
172	STOCK_TRANSFER	Chuyển hàng: Bút máy học sinh từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 155)	stock_transfers	65	\N	\N	\N	2025-09-28 03:46:20.994004+07
173	STOCK_TRANSFER	Chuyển hàng: Bìa hồ sơ từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 195)	stock_transfers	66	\N	\N	\N	2025-09-28 03:46:20.994726+07
174	STOCK_TRANSFER	Chuyển hàng: Bộ chén đĩa sứ từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 51)	stock_transfers	67	\N	\N	\N	2025-09-28 03:46:20.995381+07
175	STOCK_TRANSFER	Chuyển hàng: Nồi cơm điện 1.8L từ kho Kho chính lên quầy Quầy đồ bếp (SL: 123)	stock_transfers	68	\N	\N	\N	2025-09-28 03:46:20.996017+07
176	STOCK_TRANSFER	Chuyển hàng: Coca Cola 330ml từ kho Kho chính lên quầy Quầy đồ uống không cồn (SL: 96)	stock_transfers	69	\N	\N	\N	2025-09-28 03:46:20.997483+07
177	STOCK_TRANSFER	Chuyển hàng: Keo dán UHU từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 143)	stock_transfers	70	\N	\N	\N	2025-09-28 03:46:20.998528+07
178	STOCK_TRANSFER	Chuyển hàng: Đồng hồ đeo tay từ kho Kho chính lên quầy Quầy thời trang (SL: 187)	stock_transfers	71	\N	\N	\N	2025-09-28 03:46:20.999438+07
179	STOCK_TRANSFER	Chuyển hàng: Khăn tắm cotton từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 161)	stock_transfers	72	\N	\N	\N	2025-09-28 03:46:21.000157+07
180	STOCK_TRANSFER	Chuyển hàng: Bộ dao inox 6 món từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 41)	stock_transfers	73	\N	\N	\N	2025-09-28 03:46:21.001617+07
181	STOCK_TRANSFER	Chuyển hàng: Gương soi trang điểm từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 56)	stock_transfers	74	\N	\N	\N	2025-09-28 03:46:21.003449+07
182	STOCK_TRANSFER	Chuyển hàng: Máy xay sinh tố từ kho Kho chính lên quầy Quầy đồ bếp (SL: 38)	stock_transfers	75	\N	\N	\N	2025-09-28 03:46:21.005839+07
183	STOCK_TRANSFER	Chuyển hàng: Nước cam Tropicana từ kho Kho chính lên quầy Quầy đồ uống không cồn (SL: 64)	stock_transfers	76	\N	\N	\N	2025-09-28 03:46:21.008383+07
184	STOCK_TRANSFER	Chuyển hàng: Chảo chống dính 26cm từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 93)	stock_transfers	77	\N	\N	\N	2025-09-28 03:46:21.009692+07
185	STOCK_TRANSFER	Chuyển hàng: Máy nướng bánh mì từ kho Kho chính lên quầy Quầy đồ bếp (SL: 128)	stock_transfers	78	\N	\N	\N	2025-09-28 03:46:21.010731+07
186	STOCK_TRANSFER	Chuyển hàng: Sữa rửa mặt Cetaphil từ kho Kho chính lên quầy Quầy mỹ phẩm (SL: 130)	stock_transfers	79	\N	\N	\N	2025-09-28 03:46:21.011685+07
187	STOCK_TRANSFER	Chuyển hàng: Nước suối Aquafina 500ml từ kho Kho chính lên quầy Quầy đồ uống không cồn (SL: 181)	stock_transfers	80	\N	\N	\N	2025-09-28 03:46:21.012618+07
188	STOCK_TRANSFER	Chuyển hàng: Nước dừa Cocoxim từ kho Kho chính lên quầy Quầy đồ uống không cồn (SL: 59)	stock_transfers	81	\N	\N	\N	2025-09-28 03:46:21.013538+07
189	STOCK_TRANSFER	Chuyển hàng: Vở học sinh 96 trang từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 155)	stock_transfers	82	\N	\N	\N	2025-09-28 03:46:21.015025+07
190	STOCK_TRANSFER	Chuyển hàng: Máy tính Casio FX-580 từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 157)	stock_transfers	83	\N	\N	\N	2025-09-28 03:46:21.01609+07
191	SALE_COMPLETED	Hóa đơn bán hàng: Dương Khánh Mai - Tổng tiền: 0.00 VNĐ	sales_invoices	1	\N	\N	\N	2025-09-28 03:46:21.016783+07
192	SALE_COMPLETED	Hóa đơn bán hàng: Phạm Kim Khuê - Tổng tiền: 0.00 VNĐ	sales_invoices	2	\N	\N	\N	2025-09-28 03:46:21.030378+07
193	SALE_COMPLETED	Hóa đơn bán hàng: Phan Duy Phát - Tổng tiền: 0.00 VNĐ	sales_invoices	3	\N	\N	\N	2025-09-28 03:46:21.037779+07
194	SALE_COMPLETED	Hóa đơn bán hàng: Phan Duy Linh - Tổng tiền: 0.00 VNĐ	sales_invoices	4	\N	\N	\N	2025-09-28 03:46:21.040038+07
195	SALE_COMPLETED	Hóa đơn bán hàng: Lý Hoàng Long - Tổng tiền: 0.00 VNĐ	sales_invoices	5	\N	\N	\N	2025-09-28 03:46:21.045797+07
196	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	6	\N	\N	\N	2025-09-28 03:46:21.051377+07
197	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	7	\N	\N	\N	2025-09-28 03:46:21.057034+07
198	SALE_COMPLETED	Hóa đơn bán hàng: Vũ Hùng Loan - Tổng tiền: 0.00 VNĐ	sales_invoices	8	\N	\N	\N	2025-09-28 03:46:21.062376+07
199	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	9	\N	\N	\N	2025-09-28 03:46:21.0693+07
200	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	10	\N	\N	\N	2025-09-28 03:46:21.072439+07
201	SALE_COMPLETED	Hóa đơn bán hàng: Trần Minh Sáng - Tổng tiền: 0.00 VNĐ	sales_invoices	11	\N	\N	\N	2025-09-28 03:46:21.073825+07
202	SALE_COMPLETED	Hóa đơn bán hàng: Nguyễn Văn Khách - Tổng tiền: 0.00 VNĐ	sales_invoices	12	\N	\N	\N	2025-09-28 03:46:21.080742+07
203	SALE_COMPLETED	Hóa đơn bán hàng: Vũ Hùng Sơn - Tổng tiền: 0.00 VNĐ	sales_invoices	13	\N	\N	\N	2025-09-28 03:46:21.085831+07
204	SALE_COMPLETED	Hóa đơn bán hàng: Phạm Kim Mai - Tổng tiền: 0.00 VNĐ	sales_invoices	14	\N	\N	\N	2025-09-28 03:46:21.091295+07
205	SALE_COMPLETED	Hóa đơn bán hàng: Nguyễn Văn Quân - Tổng tiền: 0.00 VNĐ	sales_invoices	15	\N	\N	\N	2025-09-28 03:46:21.098676+07
206	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	16	\N	\N	\N	2025-09-28 03:46:21.10444+07
207	SALE_COMPLETED	Hóa đơn bán hàng: Lý Hoàng Long - Tổng tiền: 0.00 VNĐ	sales_invoices	17	\N	\N	\N	2025-09-28 03:46:21.106104+07
208	SALE_COMPLETED	Hóa đơn bán hàng: Vũ Hùng Sơn - Tổng tiền: 0.00 VNĐ	sales_invoices	18	\N	\N	\N	2025-09-28 03:46:21.111383+07
209	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Tuấn - Tổng tiền: 0.00 VNĐ	sales_invoices	19	\N	\N	\N	2025-09-28 03:46:21.117511+07
210	SALE_COMPLETED	Hóa đơn bán hàng: Vũ Hùng Loan - Tổng tiền: 0.00 VNĐ	sales_invoices	20	\N	\N	\N	2025-09-28 03:46:21.12512+07
211	SALE_COMPLETED	Hóa đơn bán hàng: Nguyễn Văn Khách - Tổng tiền: 0.00 VNĐ	sales_invoices	21	\N	\N	\N	2025-09-28 03:46:21.129032+07
212	SALE_COMPLETED	Hóa đơn bán hàng: Mai Quốc Yến - Tổng tiền: 0.00 VNĐ	sales_invoices	22	\N	\N	\N	2025-09-28 03:46:21.131687+07
213	SALE_COMPLETED	Hóa đơn bán hàng: Mai Quốc Linh - Tổng tiền: 0.00 VNĐ	sales_invoices	23	\N	\N	\N	2025-09-28 03:46:21.138423+07
214	SALE_COMPLETED	Hóa đơn bán hàng: Võ Thị Uyên - Tổng tiền: 0.00 VNĐ	sales_invoices	24	\N	\N	\N	2025-09-28 03:46:21.141517+07
215	SALE_COMPLETED	Hóa đơn bán hàng: Phạm Kim Mai - Tổng tiền: 0.00 VNĐ	sales_invoices	25	\N	\N	\N	2025-09-28 03:46:21.145105+07
216	SALE_COMPLETED	Hóa đơn bán hàng: Đặng Thúy Quỳnh - Tổng tiền: 0.00 VNĐ	sales_invoices	26	\N	\N	\N	2025-09-28 03:46:21.151089+07
217	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	27	\N	\N	\N	2025-09-28 03:46:21.157356+07
218	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	28	\N	\N	\N	2025-09-28 03:46:21.163184+07
219	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	29	\N	\N	\N	2025-09-28 03:46:21.169581+07
220	SALE_COMPLETED	Hóa đơn bán hàng: Nông Hà Hằng - Tổng tiền: 0.00 VNĐ	sales_invoices	30	\N	\N	\N	2025-09-28 03:46:21.172789+07
221	SALE_COMPLETED	Hóa đơn bán hàng: Lý Hoàng Long - Tổng tiền: 0.00 VNĐ	sales_invoices	31	\N	\N	\N	2025-09-28 03:46:21.178641+07
222	SALE_COMPLETED	Hóa đơn bán hàng: Đặng Thúy Quỳnh - Tổng tiền: 0.00 VNĐ	sales_invoices	32	\N	\N	\N	2025-09-28 03:46:21.181721+07
223	SALE_COMPLETED	Hóa đơn bán hàng: Đỗ Thu Hiếu - Tổng tiền: 0.00 VNĐ	sales_invoices	33	\N	\N	\N	2025-09-28 03:46:21.183125+07
224	SALE_COMPLETED	Hóa đơn bán hàng: Mai Quốc Yến - Tổng tiền: 0.00 VNĐ	sales_invoices	34	\N	\N	\N	2025-09-28 03:46:21.188449+07
225	SALE_COMPLETED	Hóa đơn bán hàng: Cao Thanh Nam - Tổng tiền: 0.00 VNĐ	sales_invoices	35	\N	\N	\N	2025-09-28 03:46:21.194251+07
226	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	36	\N	\N	\N	2025-09-28 03:46:21.199433+07
227	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	37	\N	\N	\N	2025-09-28 03:46:21.205387+07
228	SALE_COMPLETED	Hóa đơn bán hàng: Trần Minh Sáng - Tổng tiền: 0.00 VNĐ	sales_invoices	38	\N	\N	\N	2025-09-28 03:46:21.210723+07
229	SALE_COMPLETED	Hóa đơn bán hàng: Võ Thị Phương - Tổng tiền: 0.00 VNĐ	sales_invoices	39	\N	\N	\N	2025-09-28 03:46:21.217278+07
230	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	40	\N	\N	\N	2025-09-28 03:46:21.219923+07
231	SALE_COMPLETED	Hóa đơn bán hàng: Tôn Hải Phương - Tổng tiền: 0.00 VNĐ	sales_invoices	41	\N	\N	\N	2025-09-28 03:46:21.221966+07
232	SALE_COMPLETED	Hóa đơn bán hàng: Nông Hà Minh - Tổng tiền: 0.00 VNĐ	sales_invoices	42	\N	\N	\N	2025-09-28 03:46:21.225953+07
233	SALE_COMPLETED	Hóa đơn bán hàng: Trịnh Công Bình - Tổng tiền: 0.00 VNĐ	sales_invoices	43	\N	\N	\N	2025-09-28 03:46:21.23318+07
234	SALE_COMPLETED	Hóa đơn bán hàng: Dương Khánh Hương - Tổng tiền: 0.00 VNĐ	sales_invoices	44	\N	\N	\N	2025-09-28 03:46:21.237757+07
235	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	45	\N	\N	\N	2025-09-28 03:46:21.239754+07
236	SALE_COMPLETED	Hóa đơn bán hàng: Trịnh Công Quỳnh - Tổng tiền: 0.00 VNĐ	sales_invoices	46	\N	\N	\N	2025-09-28 03:46:21.241027+07
237	SALE_COMPLETED	Hóa đơn bán hàng: Hồ Bảo Sáng - Tổng tiền: 0.00 VNĐ	sales_invoices	47	\N	\N	\N	2025-09-28 03:46:21.242385+07
238	SALE_COMPLETED	Hóa đơn bán hàng: Lý Hoàng Dũng - Tổng tiền: 0.00 VNĐ	sales_invoices	48	\N	\N	\N	2025-09-28 03:46:21.247261+07
239	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	49	\N	\N	\N	2025-09-28 03:46:21.249812+07
240	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	50	\N	\N	\N	2025-09-28 03:46:21.25321+07
241	SALE_COMPLETED	Hóa đơn bán hàng: Trịnh Công Quỳnh - Tổng tiền: 0.00 VNĐ	sales_invoices	51	\N	\N	\N	2025-09-28 03:46:21.256039+07
242	SALE_COMPLETED	Hóa đơn bán hàng: Dương Khánh Khuê - Tổng tiền: 0.00 VNĐ	sales_invoices	52	\N	\N	\N	2025-09-28 03:46:21.257185+07
243	SALE_COMPLETED	Hóa đơn bán hàng: Lý Hoàng Dũng - Tổng tiền: 0.00 VNĐ	sales_invoices	53	\N	\N	\N	2025-09-28 03:46:21.261298+07
244	SALE_COMPLETED	Hóa đơn bán hàng: Cao Thanh Loan - Tổng tiền: 0.00 VNĐ	sales_invoices	54	\N	\N	\N	2025-09-28 03:46:21.265824+07
245	SALE_COMPLETED	Hóa đơn bán hàng: Trịnh Công Đức - Tổng tiền: 0.00 VNĐ	sales_invoices	55	\N	\N	\N	2025-09-28 03:46:21.268674+07
246	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	56	\N	\N	\N	2025-09-28 03:46:21.27374+07
247	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	57	\N	\N	\N	2025-09-28 03:46:21.277554+07
248	SALE_COMPLETED	Hóa đơn bán hàng: Bùi Đức Hằng - Tổng tiền: 0.00 VNĐ	sales_invoices	58	\N	\N	\N	2025-09-28 03:46:21.282713+07
249	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Vinh - Tổng tiền: 0.00 VNĐ	sales_invoices	59	\N	\N	\N	2025-09-28 03:46:21.285751+07
250	SALE_COMPLETED	Hóa đơn bán hàng: Đặng Thúy Bình - Tổng tiền: 0.00 VNĐ	sales_invoices	60	\N	\N	\N	2025-09-28 03:46:21.288029+07
251	SALE_COMPLETED	Hóa đơn bán hàng: Mai Quốc Linh - Tổng tiền: 0.00 VNĐ	sales_invoices	61	\N	\N	\N	2025-09-28 03:46:21.292571+07
252	SALE_COMPLETED	Hóa đơn bán hàng: Cao Thanh Nam - Tổng tiền: 0.00 VNĐ	sales_invoices	62	\N	\N	\N	2025-09-28 03:46:21.296407+07
253	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Vinh - Tổng tiền: 0.00 VNĐ	sales_invoices	63	\N	\N	\N	2025-09-28 03:46:21.301443+07
254	SALE_COMPLETED	Hóa đơn bán hàng: Trịnh Công Đức - Tổng tiền: 0.00 VNĐ	sales_invoices	64	\N	\N	\N	2025-09-28 03:46:21.307185+07
255	STOCK_TRANSFER	Chuyển hàng: Bộ nồi inox 3 món từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 50)	stock_transfers	84	\N	\N	\N	2025-09-28 03:46:21.310916+07
256	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	65	\N	\N	\N	2025-09-28 03:46:21.311695+07
257	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	66	\N	\N	\N	2025-09-28 03:46:21.318174+07
258	SALE_COMPLETED	Hóa đơn bán hàng: Hồ Bảo Châu - Tổng tiền: 0.00 VNĐ	sales_invoices	67	\N	\N	\N	2025-09-28 03:46:21.322378+07
259	SALE_COMPLETED	Hóa đơn bán hàng: Hoàng Anh Long - Tổng tiền: 0.00 VNĐ	sales_invoices	68	\N	\N	\N	2025-09-28 03:46:21.328074+07
260	SALE_COMPLETED	Hóa đơn bán hàng: Trần Minh Hoa - Tổng tiền: 0.00 VNĐ	sales_invoices	69	\N	\N	\N	2025-09-28 03:46:21.33486+07
261	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	70	\N	\N	\N	2025-09-28 03:46:21.34231+07
262	SALE_COMPLETED	Hóa đơn bán hàng: Tôn Hải Phương - Tổng tiền: 0.00 VNĐ	sales_invoices	71	\N	\N	\N	2025-09-28 03:46:21.344576+07
263	LOW_STOCK_ALERT	Cảnh báo hết hàng: Chuối tiêu 1kg - Số lượng hiện tại: 18	shelf_inventory	68	\N	\N	\N	2025-09-28 03:46:21.344576+07
264	LOW_STOCK_ALERT	Cảnh báo hết hàng: Bút dạ quang - Số lượng hiện tại: 18	shelf_inventory	11	\N	\N	\N	2025-09-28 03:46:21.344576+07
265	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	72	\N	\N	\N	2025-09-28 03:46:21.351255+07
266	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	73	\N	\N	\N	2025-09-28 03:46:21.356226+07
267	SALE_COMPLETED	Hóa đơn bán hàng: Dương Khánh Mai - Tổng tiền: 0.00 VNĐ	sales_invoices	74	\N	\N	\N	2025-09-28 03:46:21.362519+07
268	SALE_COMPLETED	Hóa đơn bán hàng: Hồ Bảo Hoa - Tổng tiền: 0.00 VNĐ	sales_invoices	75	\N	\N	\N	2025-09-28 03:46:21.364762+07
269	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	76	\N	\N	\N	2025-09-28 03:46:21.367257+07
270	SALE_COMPLETED	Hóa đơn bán hàng: Dương Khánh Mai - Tổng tiền: 0.00 VNĐ	sales_invoices	77	\N	\N	\N	2025-09-28 03:46:21.371917+07
271	SALE_COMPLETED	Hóa đơn bán hàng: Vũ Hùng Loan - Tổng tiền: 0.00 VNĐ	sales_invoices	78	\N	\N	\N	2025-09-28 03:46:21.37392+07
272	SALE_COMPLETED	Hóa đơn bán hàng: Vũ Hùng Loan - Tổng tiền: 0.00 VNĐ	sales_invoices	79	\N	\N	\N	2025-09-28 03:46:21.3807+07
273	SALE_COMPLETED	Hóa đơn bán hàng: Bùi Đức Minh - Tổng tiền: 0.00 VNĐ	sales_invoices	80	\N	\N	\N	2025-09-28 03:46:21.384919+07
274	SALE_COMPLETED	Hóa đơn bán hàng: Cao Thanh Loan - Tổng tiền: 0.00 VNĐ	sales_invoices	81	\N	\N	\N	2025-09-28 03:46:21.390265+07
275	SALE_COMPLETED	Hóa đơn bán hàng: Hoàng Anh Long - Tổng tiền: 0.00 VNĐ	sales_invoices	82	\N	\N	\N	2025-09-28 03:46:21.396471+07
276	SALE_COMPLETED	Hóa đơn bán hàng: Mai Quốc Linh - Tổng tiền: 0.00 VNĐ	sales_invoices	83	\N	\N	\N	2025-09-28 03:46:21.404045+07
277	SALE_COMPLETED	Hóa đơn bán hàng: Vũ Hùng Loan - Tổng tiền: 0.00 VNĐ	sales_invoices	84	\N	\N	\N	2025-09-28 03:46:21.407604+07
278	SALE_COMPLETED	Hóa đơn bán hàng: Hoàng Anh Dũng - Tổng tiền: 0.00 VNĐ	sales_invoices	85	\N	\N	\N	2025-09-28 03:46:21.409594+07
279	SALE_COMPLETED	Hóa đơn bán hàng: Hồ Bảo Hoa - Tổng tiền: 0.00 VNĐ	sales_invoices	86	\N	\N	\N	2025-09-28 03:46:21.417141+07
280	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	87	\N	\N	\N	2025-09-28 03:46:21.424412+07
281	SALE_COMPLETED	Hóa đơn bán hàng: Đỗ Thu Khách - Tổng tiền: 0.00 VNĐ	sales_invoices	88	\N	\N	\N	2025-09-28 03:46:21.426398+07
282	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	89	\N	\N	\N	2025-09-28 03:46:21.433772+07
283	SALE_COMPLETED	Hóa đơn bán hàng: Hồ Bảo Sáng - Tổng tiền: 0.00 VNĐ	sales_invoices	90	\N	\N	\N	2025-09-28 03:46:21.436151+07
284	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	91	\N	\N	\N	2025-09-28 03:46:21.437473+07
285	LOW_STOCK_ALERT	Cảnh báo hết hàng: Thớt gỗ cao su - Số lượng hiện tại: 13	shelf_inventory	20	\N	\N	\N	2025-09-28 03:46:21.437473+07
286	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	92	\N	\N	\N	2025-09-28 03:46:21.443249+07
287	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	93	\N	\N	\N	2025-09-28 03:46:21.44551+07
288	SALE_COMPLETED	Hóa đơn bán hàng: Đặng Thúy Quỳnh - Tổng tiền: 0.00 VNĐ	sales_invoices	94	\N	\N	\N	2025-09-28 03:46:21.446401+07
289	SALE_COMPLETED	Hóa đơn bán hàng: Trịnh Công Đức - Tổng tiền: 0.00 VNĐ	sales_invoices	95	\N	\N	\N	2025-09-28 03:46:21.454072+07
290	SALE_COMPLETED	Hóa đơn bán hàng: Tôn Hải Uyên - Tổng tiền: 0.00 VNĐ	sales_invoices	96	\N	\N	\N	2025-09-28 03:46:21.456491+07
291	SALE_COMPLETED	Hóa đơn bán hàng: Phan Duy Phát - Tổng tiền: 0.00 VNĐ	sales_invoices	97	\N	\N	\N	2025-09-28 03:46:21.458508+07
292	SALE_COMPLETED	Hóa đơn bán hàng: Lý Hoàng Long - Tổng tiền: 0.00 VNĐ	sales_invoices	98	\N	\N	\N	2025-09-28 03:46:21.461463+07
293	SALE_COMPLETED	Hóa đơn bán hàng: Trần Minh Sáng - Tổng tiền: 0.00 VNĐ	sales_invoices	99	\N	\N	\N	2025-09-28 03:46:21.467263+07
294	SALE_COMPLETED	Hóa đơn bán hàng: Trần Minh Hoa - Tổng tiền: 0.00 VNĐ	sales_invoices	100	\N	\N	\N	2025-09-28 03:46:21.472497+07
295	SALE_COMPLETED	Hóa đơn bán hàng: Đỗ Thu Khách - Tổng tiền: 0.00 VNĐ	sales_invoices	101	\N	\N	\N	2025-09-28 03:46:21.473653+07
296	SALE_COMPLETED	Hóa đơn bán hàng: Trần Minh Hoa - Tổng tiền: 0.00 VNĐ	sales_invoices	102	\N	\N	\N	2025-09-28 03:46:21.479868+07
297	SALE_COMPLETED	Hóa đơn bán hàng: Bùi Đức Minh - Tổng tiền: 0.00 VNĐ	sales_invoices	103	\N	\N	\N	2025-09-28 03:46:21.484577+07
298	SALE_COMPLETED	Hóa đơn bán hàng: Cao Thanh Loan - Tổng tiền: 0.00 VNĐ	sales_invoices	104	\N	\N	\N	2025-09-28 03:46:21.491522+07
299	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	105	\N	\N	\N	2025-09-28 03:46:21.4982+07
300	SALE_COMPLETED	Hóa đơn bán hàng: Phan Duy Phát - Tổng tiền: 0.00 VNĐ	sales_invoices	106	\N	\N	\N	2025-09-28 03:46:21.502024+07
301	SALE_COMPLETED	Hóa đơn bán hàng: Nông Hà Minh - Tổng tiền: 0.00 VNĐ	sales_invoices	107	\N	\N	\N	2025-09-28 03:46:21.503402+07
302	SALE_COMPLETED	Hóa đơn bán hàng: Ngô Gia Nga - Tổng tiền: 0.00 VNĐ	sales_invoices	108	\N	\N	\N	2025-09-28 03:46:21.51221+07
303	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	109	\N	\N	\N	2025-09-28 03:46:21.516568+07
304	SALE_COMPLETED	Hóa đơn bán hàng: Đặng Thúy Quỳnh - Tổng tiền: 0.00 VNĐ	sales_invoices	110	\N	\N	\N	2025-09-28 03:46:21.519495+07
305	SALE_COMPLETED	Hóa đơn bán hàng: Trịnh Công Bình - Tổng tiền: 0.00 VNĐ	sales_invoices	111	\N	\N	\N	2025-09-28 03:46:21.521713+07
306	SALE_COMPLETED	Hóa đơn bán hàng: Vũ Hùng Loan - Tổng tiền: 0.00 VNĐ	sales_invoices	112	\N	\N	\N	2025-09-28 03:46:21.527602+07
307	SALE_COMPLETED	Hóa đơn bán hàng: Lý Hoàng Long - Tổng tiền: 0.00 VNĐ	sales_invoices	113	\N	\N	\N	2025-09-28 03:46:21.530831+07
308	SALE_COMPLETED	Hóa đơn bán hàng: Phan Duy Yến - Tổng tiền: 0.00 VNĐ	sales_invoices	114	\N	\N	\N	2025-09-28 03:46:21.533614+07
309	SALE_COMPLETED	Hóa đơn bán hàng: Lý Hoàng Dũng - Tổng tiền: 0.00 VNĐ	sales_invoices	115	\N	\N	\N	2025-09-28 03:46:21.540112+07
310	SALE_COMPLETED	Hóa đơn bán hàng: Đỗ Thu Khách - Tổng tiền: 0.00 VNĐ	sales_invoices	116	\N	\N	\N	2025-09-28 03:46:21.546069+07
311	SALE_COMPLETED	Hóa đơn bán hàng: Đặng Thúy Quỳnh - Tổng tiền: 0.00 VNĐ	sales_invoices	117	\N	\N	\N	2025-09-28 03:46:21.547491+07
312	LOW_STOCK_ALERT	Cảnh báo hết hàng: Miếng dán màn hình - Số lượng hiện tại: 40	shelf_inventory	43	\N	\N	\N	2025-09-28 03:46:21.547491+07
313	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	118	\N	\N	\N	2025-09-28 03:46:21.554026+07
314	SALE_COMPLETED	Hóa đơn bán hàng: Nông Hà Thảo - Tổng tiền: 0.00 VNĐ	sales_invoices	119	\N	\N	\N	2025-09-28 03:46:21.559396+07
315	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Vinh - Tổng tiền: 0.00 VNĐ	sales_invoices	120	\N	\N	\N	2025-09-28 03:46:21.563635+07
316	SALE_COMPLETED	Hóa đơn bán hàng: Đặng Thúy Đức - Tổng tiền: 0.00 VNĐ	sales_invoices	121	\N	\N	\N	2025-09-28 03:46:21.568572+07
317	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	122	\N	\N	\N	2025-09-28 03:46:21.572215+07
318	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	123	\N	\N	\N	2025-09-28 03:46:21.573766+07
319	LOW_STOCK_ALERT	Cảnh báo hết hàng: Bộ dao inox 6 món - Số lượng hiện tại: 6	shelf_inventory	19	\N	\N	\N	2025-09-28 03:46:21.573766+07
320	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	124	\N	\N	\N	2025-09-28 03:46:21.580659+07
321	SALE_COMPLETED	Hóa đơn bán hàng: Trịnh Công Đức - Tổng tiền: 0.00 VNĐ	sales_invoices	125	\N	\N	\N	2025-09-28 03:46:21.587811+07
322	SALE_COMPLETED	Hóa đơn bán hàng: Đặng Thúy Quỳnh - Tổng tiền: 0.00 VNĐ	sales_invoices	126	\N	\N	\N	2025-09-28 03:46:21.59433+07
323	SALE_COMPLETED	Hóa đơn bán hàng: Ngô Gia Vinh - Tổng tiền: 0.00 VNĐ	sales_invoices	127	\N	\N	\N	2025-09-28 03:46:21.602128+07
324	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	128	\N	\N	\N	2025-09-28 03:46:21.608389+07
325	LOW_STOCK_ALERT	Cảnh báo hết hàng: Chuột không dây - Số lượng hiện tại: 19	shelf_inventory	35	\N	\N	\N	2025-09-28 03:46:21.608389+07
326	SALE_COMPLETED	Hóa đơn bán hàng: Phan Duy Linh - Tổng tiền: 0.00 VNĐ	sales_invoices	129	\N	\N	\N	2025-09-28 03:46:21.613698+07
327	SALE_COMPLETED	Hóa đơn bán hàng: Hồ Bảo Hoa - Tổng tiền: 0.00 VNĐ	sales_invoices	130	\N	\N	\N	2025-09-28 03:46:21.620792+07
328	SALE_COMPLETED	Hóa đơn bán hàng: Trịnh Công Đức - Tổng tiền: 0.00 VNĐ	sales_invoices	131	\N	\N	\N	2025-09-28 03:46:21.626479+07
329	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	132	\N	\N	\N	2025-09-28 03:46:21.631092+07
330	SALE_COMPLETED	Hóa đơn bán hàng: Ngô Gia Tuấn - Tổng tiền: 0.00 VNĐ	sales_invoices	133	\N	\N	\N	2025-09-28 03:46:21.634102+07
331	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	134	\N	\N	\N	2025-09-28 03:46:21.639091+07
332	STOCK_TRANSFER	Chuyển hàng: Nước tăng lực RedBull từ kho Kho chính lên quầy Quầy đồ uống không cồn (SL: 50)	stock_transfers	85	\N	\N	\N	2025-09-28 03:46:21.643107+07
333	STOCK_TRANSFER	Chuyển hàng: Bộ dao inox 6 món từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 50)	stock_transfers	86	\N	\N	\N	2025-09-28 03:46:21.64485+07
334	STOCK_TRANSFER	Chuyển hàng: Nước dừa Cocoxim từ kho Kho chính lên quầy Quầy đồ uống không cồn (SL: 50)	stock_transfers	87	\N	\N	\N	2025-09-28 03:46:21.645986+07
335	STOCK_TRANSFER	Chuyển hàng: Bàn ủi hơi nước từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 50)	stock_transfers	88	\N	\N	\N	2025-09-28 03:46:21.647257+07
336	STOCK_TRANSFER	Chuyển hàng: Thớt gỗ cao su từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 50)	stock_transfers	89	\N	\N	\N	2025-09-28 03:46:21.64845+07
337	STOCK_TRANSFER	Chuyển hàng: Chuối tiêu 1kg từ kho Kho chính lên quầy Quầy rau quả tươi (SL: 50)	stock_transfers	90	\N	\N	\N	2025-09-28 03:46:21.649709+07
338	STOCK_TRANSFER	Chuyển hàng: Bút dạ quang từ kho Kho chính lên quầy Quầy văn phòng phẩm 1 (SL: 50)	stock_transfers	91	\N	\N	\N	2025-09-28 03:46:21.650651+07
339	STOCK_TRANSFER	Chuyển hàng: Chuột không dây từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 50)	stock_transfers	92	\N	\N	\N	2025-09-28 03:46:21.651441+07
340	STOCK_TRANSFER	Chuyển hàng: Máy xay sinh tố từ kho Kho chính lên quầy Quầy đồ bếp (SL: 50)	stock_transfers	93	\N	\N	\N	2025-09-28 03:46:21.652249+07
341	SALE_COMPLETED	Hóa đơn bán hàng: Trịnh Công Bình - Tổng tiền: 0.00 VNĐ	sales_invoices	135	\N	\N	\N	2025-09-28 03:46:21.65306+07
342	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Tuấn - Tổng tiền: 0.00 VNĐ	sales_invoices	136	\N	\N	\N	2025-09-28 03:46:21.654679+07
343	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	137	\N	\N	\N	2025-09-28 03:46:21.662668+07
344	SALE_COMPLETED	Hóa đơn bán hàng: Phạm Kim Khuê - Tổng tiền: 0.00 VNĐ	sales_invoices	138	\N	\N	\N	2025-09-28 03:46:21.666006+07
345	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	139	\N	\N	\N	2025-09-28 03:46:21.668903+07
346	SALE_COMPLETED	Hóa đơn bán hàng: Hoàng Anh Long - Tổng tiền: 0.00 VNĐ	sales_invoices	140	\N	\N	\N	2025-09-28 03:46:21.673754+07
347	SALE_COMPLETED	Hóa đơn bán hàng: Dương Khánh Mai - Tổng tiền: 0.00 VNĐ	sales_invoices	141	\N	\N	\N	2025-09-28 03:46:21.678263+07
348	SALE_COMPLETED	Hóa đơn bán hàng: Hoàng Anh Tâm - Tổng tiền: 0.00 VNĐ	sales_invoices	142	\N	\N	\N	2025-09-28 03:46:21.682114+07
349	SALE_COMPLETED	Hóa đơn bán hàng: Mai Quốc Phát - Tổng tiền: 0.00 VNĐ	sales_invoices	143	\N	\N	\N	2025-09-28 03:46:21.687418+07
350	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	144	\N	\N	\N	2025-09-28 03:46:21.690353+07
351	SALE_COMPLETED	Hóa đơn bán hàng: Hồ Bảo Hoa - Tổng tiền: 0.00 VNĐ	sales_invoices	145	\N	\N	\N	2025-09-28 03:46:21.695772+07
352	SALE_COMPLETED	Hóa đơn bán hàng: Phan Duy Phát - Tổng tiền: 0.00 VNĐ	sales_invoices	146	\N	\N	\N	2025-09-28 03:46:21.698518+07
353	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	147	\N	\N	\N	2025-09-28 03:46:21.706096+07
354	SALE_COMPLETED	Hóa đơn bán hàng: Cao Thanh Loan - Tổng tiền: 0.00 VNĐ	sales_invoices	148	\N	\N	\N	2025-09-28 03:46:21.711866+07
355	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	149	\N	\N	\N	2025-09-28 03:46:21.714121+07
356	SALE_COMPLETED	Hóa đơn bán hàng: Trần Minh Sáng - Tổng tiền: 0.00 VNĐ	sales_invoices	150	\N	\N	\N	2025-09-28 03:46:21.72131+07
357	SALE_COMPLETED	Hóa đơn bán hàng: Võ Thị Phương - Tổng tiền: 0.00 VNĐ	sales_invoices	151	\N	\N	\N	2025-09-28 03:46:21.723981+07
358	SALE_COMPLETED	Hóa đơn bán hàng: Hồ Bảo Châu - Tổng tiền: 0.00 VNĐ	sales_invoices	152	\N	\N	\N	2025-09-28 03:46:21.727872+07
359	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	153	\N	\N	\N	2025-09-28 03:46:21.735702+07
360	SALE_COMPLETED	Hóa đơn bán hàng: Cao Thanh Nam - Tổng tiền: 0.00 VNĐ	sales_invoices	154	\N	\N	\N	2025-09-28 03:46:21.736847+07
361	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Tuấn - Tổng tiền: 0.00 VNĐ	sales_invoices	155	\N	\N	\N	2025-09-28 03:46:21.743608+07
362	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	156	\N	\N	\N	2025-09-28 03:46:21.747954+07
363	SALE_COMPLETED	Hóa đơn bán hàng: Hồ Bảo Hoa - Tổng tiền: 0.00 VNĐ	sales_invoices	157	\N	\N	\N	2025-09-28 03:46:21.750138+07
364	SALE_COMPLETED	Hóa đơn bán hàng: Đỗ Thu Quân - Tổng tiền: 0.00 VNĐ	sales_invoices	158	\N	\N	\N	2025-09-28 03:46:21.75648+07
365	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	159	\N	\N	\N	2025-09-28 03:46:21.761337+07
366	SALE_COMPLETED	Hóa đơn bán hàng: Đặng Thúy Quỳnh - Tổng tiền: 0.00 VNĐ	sales_invoices	160	\N	\N	\N	2025-09-28 03:46:21.762793+07
367	SALE_COMPLETED	Hóa đơn bán hàng: Trần Minh Sáng - Tổng tiền: 0.00 VNĐ	sales_invoices	161	\N	\N	\N	2025-09-28 03:46:21.764992+07
368	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Tuấn - Tổng tiền: 0.00 VNĐ	sales_invoices	162	\N	\N	\N	2025-09-28 03:46:21.771503+07
369	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	163	\N	\N	\N	2025-09-28 03:46:21.775464+07
370	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	164	\N	\N	\N	2025-09-28 03:46:21.780598+07
371	SALE_COMPLETED	Hóa đơn bán hàng: Nông Hà Hằng - Tổng tiền: 0.00 VNĐ	sales_invoices	165	\N	\N	\N	2025-09-28 03:46:21.782505+07
372	SALE_COMPLETED	Hóa đơn bán hàng: Vũ Hùng Loan - Tổng tiền: 0.00 VNĐ	sales_invoices	166	\N	\N	\N	2025-09-28 03:46:21.787475+07
373	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Tuấn - Tổng tiền: 0.00 VNĐ	sales_invoices	167	\N	\N	\N	2025-09-28 03:46:21.789534+07
374	SALE_COMPLETED	Hóa đơn bán hàng: Nguyễn Văn Khách - Tổng tiền: 0.00 VNĐ	sales_invoices	168	\N	\N	\N	2025-09-28 03:46:21.793934+07
375	SALE_COMPLETED	Hóa đơn bán hàng: Nguyễn Văn Quân - Tổng tiền: 0.00 VNĐ	sales_invoices	169	\N	\N	\N	2025-09-28 03:46:21.799592+07
376	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	170	\N	\N	\N	2025-09-28 03:46:21.801392+07
377	SALE_COMPLETED	Hóa đơn bán hàng: Võ Thị Uyên - Tổng tiền: 0.00 VNĐ	sales_invoices	171	\N	\N	\N	2025-09-28 03:46:21.807762+07
378	SALE_COMPLETED	Hóa đơn bán hàng: Vũ Hùng Sơn - Tổng tiền: 0.00 VNĐ	sales_invoices	172	\N	\N	\N	2025-09-28 03:46:21.812472+07
379	SALE_COMPLETED	Hóa đơn bán hàng: Bùi Đức Thảo - Tổng tiền: 0.00 VNĐ	sales_invoices	173	\N	\N	\N	2025-09-28 03:46:21.817642+07
380	SALE_COMPLETED	Hóa đơn bán hàng: Lý Hoàng Long - Tổng tiền: 0.00 VNĐ	sales_invoices	174	\N	\N	\N	2025-09-28 03:46:21.82139+07
381	SALE_COMPLETED	Hóa đơn bán hàng: Trần Minh Châu - Tổng tiền: 0.00 VNĐ	sales_invoices	175	\N	\N	\N	2025-09-28 03:46:21.825732+07
382	SALE_COMPLETED	Hóa đơn bán hàng: Tôn Hải Phương - Tổng tiền: 0.00 VNĐ	sales_invoices	176	\N	\N	\N	2025-09-28 03:46:21.831823+07
383	LOW_STOCK_ALERT	Cảnh báo hết hàng: Kệ gia vị 3 tầng - Số lượng hiện tại: 7	shelf_inventory	28	\N	\N	\N	2025-09-28 03:46:21.831823+07
384	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	177	\N	\N	\N	2025-09-28 03:46:21.834118+07
385	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	178	\N	\N	\N	2025-09-28 03:46:21.835642+07
386	SALE_COMPLETED	Hóa đơn bán hàng: Vũ Hùng Sơn - Tổng tiền: 0.00 VNĐ	sales_invoices	179	\N	\N	\N	2025-09-28 03:46:21.837872+07
387	SALE_COMPLETED	Hóa đơn bán hàng: Đỗ Thu Khách - Tổng tiền: 0.00 VNĐ	sales_invoices	180	\N	\N	\N	2025-09-28 03:46:21.843385+07
388	SALE_COMPLETED	Hóa đơn bán hàng: Phan Duy Phát - Tổng tiền: 0.00 VNĐ	sales_invoices	181	\N	\N	\N	2025-09-28 03:46:21.846448+07
389	SALE_COMPLETED	Hóa đơn bán hàng: Trịnh Công Quỳnh - Tổng tiền: 0.00 VNĐ	sales_invoices	182	\N	\N	\N	2025-09-28 03:46:21.850059+07
390	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	183	\N	\N	\N	2025-09-28 03:46:21.856902+07
391	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	184	\N	\N	\N	2025-09-28 03:46:21.861653+07
392	SALE_COMPLETED	Hóa đơn bán hàng: Cao Thanh Nam - Tổng tiền: 0.00 VNĐ	sales_invoices	185	\N	\N	\N	2025-09-28 03:46:21.864397+07
393	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	186	\N	\N	\N	2025-09-28 03:46:21.869991+07
394	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Nga - Tổng tiền: 0.00 VNĐ	sales_invoices	187	\N	\N	\N	2025-09-28 03:46:21.872868+07
395	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	188	\N	\N	\N	2025-09-28 03:46:21.880572+07
396	LOW_STOCK_ALERT	Cảnh báo hết hàng: Gương soi trang điểm - Số lượng hiện tại: 11	shelf_inventory	22	\N	\N	\N	2025-09-28 03:46:21.880572+07
397	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	189	\N	\N	\N	2025-09-28 03:46:21.885429+07
398	SALE_COMPLETED	Hóa đơn bán hàng: Phạm Kim Hương - Tổng tiền: 0.00 VNĐ	sales_invoices	190	\N	\N	\N	2025-09-28 03:46:21.892039+07
399	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Vinh - Tổng tiền: 0.00 VNĐ	sales_invoices	191	\N	\N	\N	2025-09-28 03:46:21.896946+07
400	STOCK_TRANSFER	Chuyển hàng: Nước cam Tropicana từ kho Kho chính lên quầy Quầy đồ uống không cồn (SL: 50)	stock_transfers	94	\N	\N	\N	2025-09-28 03:46:21.904809+07
401	STOCK_TRANSFER	Chuyển hàng: Bộ chén đĩa sứ từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 50)	stock_transfers	95	\N	\N	\N	2025-09-28 03:46:21.905986+07
402	STOCK_TRANSFER	Chuyển hàng: Gương soi trang điểm từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 50)	stock_transfers	96	\N	\N	\N	2025-09-28 03:46:21.906876+07
403	STOCK_TRANSFER	Chuyển hàng: Nồi áp suất 5L từ kho Kho chính lên quầy Quầy đồ bếp (SL: 50)	stock_transfers	97	\N	\N	\N	2025-09-28 03:46:21.907775+07
404	STOCK_TRANSFER	Chuyển hàng: Bàn phím gaming từ kho Kho chính lên quầy Quầy điện tử 1 (SL: 50)	stock_transfers	98	\N	\N	\N	2025-09-28 03:46:21.908932+07
405	STOCK_TRANSFER	Chuyển hàng: Bếp gas hồng ngoại từ kho Kho chính lên quầy Quầy đồ bếp (SL: 50)	stock_transfers	99	\N	\N	\N	2025-09-28 03:46:21.90999+07
406	STOCK_TRANSFER	Chuyển hàng: Kệ gia vị 3 tầng từ kho Kho chính lên quầy Quầy đồ gia dụng 1 (SL: 50)	stock_transfers	100	\N	\N	\N	2025-09-28 03:46:21.9109+07
407	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	192	\N	\N	\N	2025-09-28 03:46:21.911542+07
408	SALE_COMPLETED	Hóa đơn bán hàng: Đỗ Thu Hiếu - Tổng tiền: 0.00 VNĐ	sales_invoices	193	\N	\N	\N	2025-09-28 03:46:21.914487+07
409	SALE_COMPLETED	Hóa đơn bán hàng: Phan Duy Phát - Tổng tiền: 0.00 VNĐ	sales_invoices	194	\N	\N	\N	2025-09-28 03:46:21.917564+07
410	SALE_COMPLETED	Hóa đơn bán hàng: Nguyễn Văn Khách - Tổng tiền: 0.00 VNĐ	sales_invoices	195	\N	\N	\N	2025-09-28 03:46:21.920495+07
411	SALE_COMPLETED	Hóa đơn bán hàng: Trịnh Công Quỳnh - Tổng tiền: 0.00 VNĐ	sales_invoices	196	\N	\N	\N	2025-09-28 03:46:21.927034+07
412	SALE_COMPLETED	Hóa đơn bán hàng: Võ Thị Phương - Tổng tiền: 0.00 VNĐ	sales_invoices	197	\N	\N	\N	2025-09-28 03:46:21.928514+07
413	SALE_COMPLETED	Hóa đơn bán hàng: Đặng Thúy Quỳnh - Tổng tiền: 0.00 VNĐ	sales_invoices	198	\N	\N	\N	2025-09-28 03:46:21.934217+07
414	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Vinh - Tổng tiền: 0.00 VNĐ	sales_invoices	199	\N	\N	\N	2025-09-28 03:46:21.940349+07
415	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	200	\N	\N	\N	2025-09-28 03:46:21.947388+07
416	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Nga - Tổng tiền: 0.00 VNĐ	sales_invoices	201	\N	\N	\N	2025-09-28 03:46:21.950387+07
417	SALE_COMPLETED	Hóa đơn bán hàng: Phạm Kim Khuê - Tổng tiền: 0.00 VNĐ	sales_invoices	202	\N	\N	\N	2025-09-28 03:46:21.951791+07
418	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	203	\N	\N	\N	2025-09-28 03:46:21.956303+07
419	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Vinh - Tổng tiền: 0.00 VNĐ	sales_invoices	204	\N	\N	\N	2025-09-28 03:46:21.958288+07
420	SALE_COMPLETED	Hóa đơn bán hàng: Võ Thị Giang - Tổng tiền: 0.00 VNĐ	sales_invoices	205	\N	\N	\N	2025-09-28 03:46:21.966029+07
421	SALE_COMPLETED	Hóa đơn bán hàng: Trần Minh Hoa - Tổng tiền: 0.00 VNĐ	sales_invoices	206	\N	\N	\N	2025-09-28 03:46:21.969734+07
422	SALE_COMPLETED	Hóa đơn bán hàng: Lê Hữu Vinh - Tổng tiền: 0.00 VNĐ	sales_invoices	207	\N	\N	\N	2025-09-28 03:46:21.971134+07
423	SALE_COMPLETED	Hóa đơn bán hàng: Khách vãng lai - Tổng tiền: 0.00 VNĐ	sales_invoices	208	\N	\N	\N	2025-09-28 03:46:21.975328+07
\.


--
-- TOC entry 5342 (class 0 OID 36837)
-- Dependencies: 237
-- Data for Name: customers; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.customers (customer_id, customer_code, full_name, phone, email, address, membership_card_no, membership_level_id, registration_date, total_spending, loyalty_points, is_active, created_at, updated_at) FROM stdin;
2	CUST002	Lê Hữu Vinh	0921024690	customer002@hotmail.com	\N	MB002	1	2024-02-07	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
4	CUST004	Hoàng Anh Tâm	0941049380	customer004@gmail.com	\N	MB004	1	2024-04-13	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
5	CUST005	Phan Duy Linh	0951061725	customer005@yahoo.com	\N	MB005	2	2024-05-16	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
11	CUST011	Hồ Bảo Châu	0911135795	customer011@outlook.com	\N	MB011	5	2024-03-06	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
12	CUST012	Ngô Gia Nga	0921148140	customer012@gmail.com	\N	MB012	1	2024-04-09	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
15	CUST015	Mai Quốc Yến	0951185175	customer015@outlook.com	\N	MB015	1	2024-07-18	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
17	CUST017	Tôn Hải Uyên	0971209865	customer017@yahoo.com	\N	MB017	2	2024-01-24	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
20	CUST020	Nguyễn Văn Hiếu	0901246900	customer020@gmail.com	\N	MB020	3	2024-04-05	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
26	CUST026	Vũ Hùng Nam	0961320970	customer026@hotmail.com	\N	MB026	1	2024-02-23	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
28	CUST028	Đặng Thúy Bình	0981345660	customer028@gmail.com	\N	MB028	2	2024-04-01	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
32	CUST032	Ngô Gia Vinh	0921395040	customer032@gmail.com	\N	MB032	4	2024-08-13	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
34	CUST034	Lý Hoàng Tâm	0941419730	customer034@hotmail.com	\N	MB034	1	2024-02-19	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
36	CUST036	Cao Thanh Sơn	0961444420	customer036@gmail.com	\N	MB036	1	2024-04-25	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
37	CUST037	Tôn Hải Giang	0971456765	customer037@yahoo.com	\N	MB037	1	2024-05-28	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
39	CUST039	Nông Hà Hằng	0991481455	customer039@outlook.com	\N	MB039	2	2024-07-06	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
43	CUST043	Phạm Kim Mai	0931530835	customer043@outlook.com	\N	MB043	4	2024-03-18	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
44	CUST044	Hoàng Anh Long	0941543180	customer044@gmail.com	\N	MB044	5	2024-04-21	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
45	CUST045	Phan Duy Yến	0951555525	customer045@yahoo.com	\N	MB045	1	2024-05-24	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
47	CUST047	Võ Thị Uyên	0971580215	customer047@outlook.com	\N	MB047	1	2024-07-02	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
48	CUST048	Đặng Thúy Đức	0981592560	customer048@gmail.com	\N	MB048	1	2024-08-05	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
1	CUST001	Trần Minh Hoa	0911012345	customer001@yahoo.com	\N	MB001	2	2024-01-04	7824000.00	5750659	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.472497+07
14	CUST014	Lý Hoàng Long	0941172830	customer014@hotmail.com	\N	MB014	2	2024-06-15	8823800.00	7199683	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.530831+07
19	CUST019	Nông Hà Thảo	0991234555	customer019@outlook.com	\N	MB019	3	2024-03-02	21202300.00	19403196	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.559396+07
31	CUST031	Hồ Bảo Hoa	0911382695	customer031@outlook.com	\N	MB031	3	2024-07-10	23706260.00	23108212	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.620792+07
10	CUST010	Đỗ Thu Quân	0901123450	customer010@hotmail.com	\N	MB010	2	2024-02-03	10893720.00	9784937	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.75648+07
49	CUST049	Bùi Đức Thảo	0991604905	customer049@yahoo.com	\N	MB049	2	2024-01-08	5971720.00	4868070	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.817642+07
23	CUST023	Phạm Kim Hương	0931283935	customer023@outlook.com	\N	MB023	3	2024-07-14	28303800.00	26550791	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.892039+07
50	CUST050	Đỗ Thu Hiếu	0901617250	customer050@hotmail.com	\N	MB050	2	2024-02-11	5040600.00	3922911	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.914487+07
25	CUST025	Phan Duy Phát	0951308625	customer025@yahoo.com	\N	MB025	3	2024-01-20	24911400.00	20707302	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.917564+07
38	CUST038	Trịnh Công Quỳnh	0981469110	customer038@hotmail.com	\N	MB038	1	2024-06-03	912800.00	610430	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.927034+07
3	CUST003	Phạm Kim Khuê	0931037035	customer003@outlook.com	\N	MB003	3	2024-03-10	41861400.00	41053214	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.951791+07
7	CUST007	Võ Thị Giang	0971086415	customer007@outlook.com	\N	MB007	2	2024-07-22	5765600.00	4620914	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.966029+07
51	CUST051	Hồ Bảo Sáng	0911629595	customer051@outlook.com	\N	MB051	2	2024-03-14	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
52	CUST052	Ngô Gia Tuấn	0921641940	customer052@gmail.com	\N	MB052	3	2024-04-17	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
53	CUST053	Dương Khánh Hương	0931654285	customer053@yahoo.com	\N	MB053	3	2024-05-20	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
59	CUST059	Nông Hà Minh	0991728355	customer059@outlook.com	\N	MB059	1	2024-03-10	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
63	CUST063	Phạm Kim Khuê	0931777735	customer063@outlook.com	\N	MB063	3	2024-07-22	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
64	CUST064	Hoàng Anh Tâm	0941790080	customer064@gmail.com	\N	MB064	3	2024-08-25	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
65	CUST065	Phan Duy Linh	0951802425	customer065@yahoo.com	\N	MB065	4	2024-01-28	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
67	CUST067	Võ Thị Giang	0971827115	customer067@outlook.com	\N	MB067	1	2024-03-06	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
69	CUST069	Bùi Đức Hằng	0991851805	customer069@yahoo.com	\N	MB069	1	2024-05-12	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
70	CUST070	Đỗ Thu Quân	0901864150	customer070@hotmail.com	\N	MB070	1	2024-06-15	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
73	CUST073	Dương Khánh Mai	0931901185	customer073@yahoo.com	\N	MB073	2	2024-01-24	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
75	CUST075	Mai Quốc Yến	0951925875	customer075@outlook.com	\N	MB075	3	2024-03-02	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
79	CUST079	Nông Hà Thảo	0991975255	customer079@outlook.com	\N	MB079	1	2024-07-14	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
80	CUST080	Nguyễn Văn Hiếu	0901987600	customer080@gmail.com	\N	MB080	1	2024-08-17	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
82	CUST082	Lê Hữu Tuấn	0922012290	customer082@hotmail.com	\N	MB082	2	2024-02-23	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
83	CUST083	Phạm Kim Hương	0932024635	customer083@outlook.com	\N	MB083	2	2024-03-26	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
84	CUST084	Hoàng Anh Dũng	0942036980	customer084@gmail.com	\N	MB084	2	2024-04-01	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
86	CUST086	Vũ Hùng Nam	0962061670	customer086@hotmail.com	\N	MB086	3	2024-06-07	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
89	CUST089	Bùi Đức Minh	0992098705	customer089@yahoo.com	\N	MB089	1	2024-01-16	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
92	CUST092	Ngô Gia Vinh	0922135740	customer092@gmail.com	\N	MB092	1	2024-04-25	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
93	CUST093	Dương Khánh Khuê	0932148085	customer093@yahoo.com	\N	MB093	2	2024-05-28	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
94	CUST094	Lý Hoàng Tâm	0942160430	customer094@hotmail.com	\N	MB094	2	2024-06-03	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
96	CUST096	Cao Thanh Sơn	0962185120	customer096@gmail.com	\N	MB096	3	2024-08-09	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
97	CUST097	Tôn Hải Giang	0972197465	customer097@yahoo.com	\N	MB097	3	2024-01-12	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
99	CUST099	Nông Hà Hằng	0992222155	customer099@outlook.com	\N	MB099	5	2024-03-18	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
95	CUST095	Mai Quốc Linh	0952172775	customer095@outlook.com	\N	MB095	2	2024-07-06	11157800.00	9101737	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.404045+07
77	CUST077	Tôn Hải Uyên	0971950565	customer077@yahoo.com	\N	MB077	2	2024-05-08	5095600.00	3680941	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.456491+07
72	CUST072	Ngô Gia Nga	0921888840	customer072@gmail.com	\N	MB072	2	2024-08-21	11104100.00	9432468	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.51221+07
78	CUST078	Trịnh Công Đức	0981962910	customer078@hotmail.com	\N	MB078	4	2024-06-11	64679100.00	75010984	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.626479+07
55	CUST055	Mai Quốc Phát	0951678975	customer055@outlook.com	\N	MB055	2	2024-07-26	16871200.00	13484743	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.687418+07
91	CUST091	Hồ Bảo Hoa	0912123395	customer091@outlook.com	\N	MB091	1	2024-03-22	4949200.00	3739720	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.695772+07
100	CUST100	Nguyễn Văn Quân	0902234500	customer100@gmail.com	\N	MB100	1	2024-04-21	3433000.00	2569086	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.799592+07
66	CUST066	Vũ Hùng Sơn	0961814770	customer066@hotmail.com	\N	MB066	2	2024-02-03	8748880.00	7549797	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.812472+07
90	CUST090	Đỗ Thu Khách	0902111050	customer090@hotmail.com	\N	MB090	2	2024-02-19	11527500.00	9259783	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.843385+07
101	CUST101	Trần Minh Châu	0912246845	customer101@yahoo.com	\N	MB101	1	2024-05-24	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
102	CUST102	Lê Hữu Nga	0922259190	customer102@hotmail.com	\N	MB102	1	2024-06-27	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
103	CUST103	Phạm Kim Mai	0932271535	customer103@outlook.com	\N	MB103	1	2024-07-02	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
105	CUST105	Phan Duy Yến	0952296225	customer105@yahoo.com	\N	MB105	2	2024-01-08	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
109	CUST109	Bùi Đức Thảo	0992345605	customer109@yahoo.com	\N	MB109	4	2024-05-20	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
110	CUST110	Đỗ Thu Hiếu	0902357950	customer110@hotmail.com	\N	MB110	5	2024-06-23	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
113	CUST113	Dương Khánh Hương	0932394985	customer113@yahoo.com	\N	MB113	1	2024-01-04	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
114	CUST114	Lý Hoàng Dũng	0942407330	customer114@hotmail.com	\N	MB114	1	2024-02-07	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
115	CUST115	Mai Quốc Phát	0952419675	customer115@outlook.com	\N	MB115	2	2024-03-10	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
119	CUST119	Nông Hà Minh	0992469055	customer119@outlook.com	\N	MB119	3	2024-07-22	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
124	CUST124	Hoàng Anh Tâm	0942530780	customer124@gmail.com	\N	MB124	1	2024-04-09	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
126	CUST126	Vũ Hùng Sơn	0962555470	customer126@hotmail.com	\N	MB126	2	2024-06-15	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
127	CUST127	Võ Thị Giang	0972567815	customer127@outlook.com	\N	MB127	2	2024-07-18	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
129	CUST129	Bùi Đức Hằng	0992592505	customer129@yahoo.com	\N	MB129	3	2024-01-24	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
130	CUST130	Đỗ Thu Quân	0902604850	customer130@hotmail.com	\N	MB130	3	2024-02-27	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
131	CUST131	Hồ Bảo Châu	0912617195	customer131@outlook.com	\N	MB131	4	2024-03-02	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
132	CUST132	Ngô Gia Nga	0922629540	customer132@gmail.com	\N	MB132	5	2024-04-05	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
133	CUST133	Dương Khánh Mai	0932641885	customer133@yahoo.com	\N	MB133	1	2024-05-08	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
134	CUST134	Lý Hoàng Long	0942654230	customer134@hotmail.com	\N	MB134	1	2024-06-11	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
135	CUST135	Mai Quốc Yến	0952666575	customer135@outlook.com	\N	MB135	1	2024-07-14	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
137	CUST137	Tôn Hải Uyên	0972691265	customer137@yahoo.com	\N	MB137	2	2024-01-20	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
139	CUST139	Nông Hà Thảo	0992715955	customer139@outlook.com	\N	MB139	2	2024-03-26	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
140	CUST140	Nguyễn Văn Hiếu	0902728300	customer140@gmail.com	\N	MB140	3	2024-04-01	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
143	CUST143	Phạm Kim Hương	0932765335	customer143@outlook.com	\N	MB143	5	2024-07-10	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
144	CUST144	Hoàng Anh Dũng	0942777680	customer144@gmail.com	\N	MB144	1	2024-08-13	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
146	CUST146	Vũ Hùng Nam	0962802370	customer146@hotmail.com	\N	MB146	1	2024-02-19	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
147	CUST147	Võ Thị Phương	0972814715	customer147@outlook.com	\N	MB147	1	2024-03-22	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
148	CUST148	Đặng Thúy Bình	0982827060	customer148@gmail.com	\N	MB148	2	2024-04-25	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
108	CUST108	Đặng Thúy Đức	0982333260	customer108@gmail.com	\N	MB108	2	2024-04-17	6092600.00	4866922	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.568572+07
112	CUST112	Ngô Gia Tuấn	0922382640	customer112@gmail.com	\N	MB112	3	2024-08-01	33613600.00	34037141	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.634102+07
136	CUST136	Cao Thanh Loan	0962678920	customer136@gmail.com	\N	MB136	3	2024-08-17	34855600.00	32277270	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.711866+07
107	CUST107	Võ Thị Uyên	0972320915	customer107@outlook.com	\N	MB107	2	2024-03-14	9644200.00	8158305	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.807762+07
145	CUST145	Phan Duy Phát	0952790025	customer145@yahoo.com	\N	MB145	2	2024-01-16	9566120.00	7473760	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.846448+07
153	CUST153	Dương Khánh Khuê	0932888785	customer153@yahoo.com	\N	MB153	4	2024-01-12	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
154	CUST154	Lý Hoàng Tâm	0942901130	customer154@hotmail.com	\N	MB154	5	2024-02-15	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
156	CUST156	Cao Thanh Sơn	0962925820	customer156@gmail.com	\N	MB156	1	2024-04-21	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
157	CUST157	Tôn Hải Giang	0972938165	customer157@yahoo.com	\N	MB157	1	2024-05-24	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
160	CUST160	Nguyễn Văn Quân	0902975200	customer160@gmail.com	\N	MB160	2	2024-08-05	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
161	CUST161	Trần Minh Châu	0912987545	customer161@yahoo.com	\N	MB161	2	2024-01-08	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
168	CUST168	Đặng Thúy Đức	0983073960	customer168@gmail.com	\N	MB168	1	2024-08-01	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
169	CUST169	Bùi Đức Thảo	0993086305	customer169@yahoo.com	\N	MB169	1	2024-01-04	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
172	CUST172	Ngô Gia Tuấn	0923123340	customer172@gmail.com	\N	MB172	2	2024-04-13	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
175	CUST175	Mai Quốc Phát	0953160375	customer175@outlook.com	\N	MB175	4	2024-07-22	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
176	CUST176	Cao Thanh Nam	0963172720	customer176@gmail.com	\N	MB176	5	2024-08-25	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
177	CUST177	Tôn Hải Phương	0973185065	customer177@yahoo.com	\N	MB177	1	2024-01-28	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
178	CUST178	Trịnh Công Bình	0983197410	customer178@hotmail.com	\N	MB178	1	2024-02-03	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
181	CUST181	Trần Minh Hoa	0913234445	customer181@yahoo.com	\N	MB181	2	2024-05-12	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
183	CUST183	Phạm Kim Khuê	0933259135	customer183@outlook.com	\N	MB183	2	2024-07-18	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
185	CUST185	Phan Duy Linh	0953283825	customer185@yahoo.com	\N	MB185	3	2024-01-24	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
187	CUST187	Võ Thị Giang	0973308515	customer187@outlook.com	\N	MB187	5	2024-03-02	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
189	CUST189	Bùi Đức Hằng	0993333205	customer189@yahoo.com	\N	MB189	1	2024-05-08	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
190	CUST190	Đỗ Thu Quân	0903345550	customer190@hotmail.com	\N	MB190	1	2024-06-11	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
191	CUST191	Hồ Bảo Châu	0913357895	customer191@outlook.com	\N	MB191	1	2024-07-14	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
192	CUST192	Ngô Gia Nga	0923370240	customer192@gmail.com	\N	MB192	2	2024-08-17	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
197	CUST197	Tôn Hải Uyên	0973431965	customer197@yahoo.com	\N	MB197	4	2024-05-04	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
198	CUST198	Trịnh Công Đức	0983444310	customer198@hotmail.com	\N	MB198	5	2024-06-07	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
199	CUST199	Nông Hà Thảo	0993456655	customer199@outlook.com	\N	MB199	1	2024-07-10	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
200	CUST200	Nguyễn Văn Hiếu	0903469000	customer200@gmail.com	\N	MB200	1	2024-08-13	0.00	0	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.797542+07
173	CUST173	Dương Khánh Hương	0933135685	customer173@yahoo.com	\N	MB173	1	2024-05-16	2544600.00	1750879	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.237757+07
158	CUST158	Trịnh Công Quỳnh	0982950510	customer158@hotmail.com	\N	MB158	1	2024-06-27	3390400.00	2267312	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.256039+07
171	CUST171	Hồ Bảo Sáng	0913110995	customer171@outlook.com	\N	MB171	1	2024-03-10	1304000.00	872043	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.436151+07
164	CUST164	Hoàng Anh Long	0943024580	customer164@gmail.com	\N	MB164	2	2024-04-17	7348000.00	6160148	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.673754+07
193	CUST193	Dương Khánh Mai	0933382585	customer193@yahoo.com	\N	MB193	2	2024-01-20	12331300.00	11008101	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.678263+07
184	CUST184	Hoàng Anh Tâm	0943271480	customer184@gmail.com	\N	MB184	2	2024-08-21	6605300.00	5650699	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.682114+07
162	CUST162	Lê Hữu Nga	0922999890	customer162@hotmail.com	\N	MB162	1	2024-02-11	2934000.00	1962097	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.950387+07
182	CUST182	Lê Hữu Vinh	0923246790	customer182@hotmail.com	\N	MB182	2	2024-06-15	18285410.00	14355997	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.971134+07
141	CUST141	Trần Minh Sáng	0912740645	customer141@yahoo.com	\N	MB141	5	2024-05-04	116509200.00	179825754	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.073825+07
186	CUST186	Vũ Hùng Sơn	0963296170	customer186@hotmail.com	\N	MB186	3	2024-02-27	29810900.00	30817328	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.085831+07
40	CUST040	Nguyễn Văn Quân	0901493800	customer040@gmail.com	\N	MB040	3	2024-08-09	36330420.00	36500475	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.098676+07
180	CUST180	Nguyễn Văn Khách	0903222100	customer180@gmail.com	\N	MB180	2	2024-04-09	8513600.00	7079539	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.129032+07
155	CUST155	Mai Quốc Linh	0952913475	customer155@outlook.com	\N	MB155	2	2024-03-18	17461480.00	14042195	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.138423+07
167	CUST167	Võ Thị Uyên	0973061615	customer167@outlook.com	\N	MB167	2	2024-07-26	8400600.00	6664177	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.141517+07
163	CUST163	Phạm Kim Mai	0933012235	customer163@outlook.com	\N	MB163	5	2024-03-14	124182390.00	190156951	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.145105+07
128	CUST128	Đặng Thúy Quỳnh	0982580160	customer128@gmail.com	\N	MB128	3	2024-08-21	41221600.00	44754811	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.151089+07
170	CUST170	Đỗ Thu Hiếu	0903098650	customer170@hotmail.com	\N	MB170	3	2024-02-07	30966340.00	31908747	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.183125+07
195	CUST195	Mai Quốc Yến	0953407275	customer195@outlook.com	\N	MB195	4	2024-03-26	50544120.00	55435655	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.188449+07
58	CUST058	Trịnh Công Bình	0981716010	customer058@hotmail.com	\N	MB058	3	2024-02-07	40910640.00	44207807	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.23318+07
111	CUST111	Hồ Bảo Sáng	0912370295	customer111@outlook.com	\N	MB111	2	2024-07-26	11154600.00	9266995	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.242385+07
33	CUST033	Dương Khánh Khuê	0931407385	customer033@yahoo.com	\N	MB033	2	2024-01-16	10711300.00	8396069	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.257185+07
174	CUST174	Lý Hoàng Dũng	0943148030	customer174@hotmail.com	\N	MB174	3	2024-06-19	40980100.00	41847171	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.261298+07
16	CUST016	Cao Thanh Loan	0961197520	customer016@gmail.com	\N	MB016	3	2024-08-21	27544400.00	20425929	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.265824+07
9	CUST009	Bùi Đức Hằng	0991111105	customer009@yahoo.com	\N	MB009	2	2024-01-28	9580600.00	8146539	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.282713+07
88	CUST088	Đặng Thúy Bình	0982086360	customer088@gmail.com	\N	MB088	2	2024-08-13	16034350.00	15081250	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.288029+07
35	CUST035	Mai Quốc Linh	0951432075	customer035@outlook.com	\N	MB035	2	2024-03-22	18623400.00	16504995	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.292571+07
116	CUST116	Cao Thanh Nam	0962432020	customer116@gmail.com	\N	MB116	3	2024-04-13	31302940.00	32757708	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.296407+07
138	CUST138	Trịnh Công Đức	0982703610	customer138@hotmail.com	\N	MB138	4	2024-02-23	54550820.00	63046860	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.307185+07
61	CUST061	Trần Minh Hoa	0911753045	customer061@yahoo.com	\N	MB061	4	2024-05-16	55798540.00	65195026	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.33486+07
57	CUST057	Tôn Hải Phương	0971703665	customer057@yahoo.com	\N	MB057	3	2024-01-04	34068960.00	34272662	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.344576+07
13	CUST013	Dương Khánh Mai	0931160485	customer013@yahoo.com	\N	MB013	4	2024-05-12	53520180.00	55562673	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.371917+07
166	CUST166	Vũ Hùng Loan	0963049270	customer166@hotmail.com	\N	MB166	3	2024-06-23	29508860.00	30937778	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.37392+07
149	CUST149	Bùi Đức Minh	0992839405	customer149@yahoo.com	\N	MB149	3	2024-05-28	30215720.00	30544746	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.384919+07
196	CUST196	Cao Thanh Loan	0963419620	customer196@gmail.com	\N	MB196	4	2024-04-01	70143100.00	86581405	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.390265+07
104	CUST104	Hoàng Anh Long	0942283880	customer104@gmail.com	\N	MB104	3	2024-08-05	49563540.00	57560414	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.396471+07
24	CUST024	Hoàng Anh Dũng	0941296280	customer024@gmail.com	\N	MB024	3	2024-08-17	41417780.00	46251290	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.409594+07
150	CUST150	Đỗ Thu Khách	0902851750	customer150@hotmail.com	\N	MB150	3	2024-06-03	43305900.00	50669763	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.426398+07
74	CUST074	Lý Hoàng Long	0941913530	customer074@hotmail.com	\N	MB074	5	2024-02-27	102168380.00	141900388	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.461463+07
29	CUST029	Bùi Đức Minh	0991358005	customer029@yahoo.com	\N	MB029	3	2024-05-04	28061400.00	28313620	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.484577+07
76	CUST076	Cao Thanh Loan	0961938220	customer076@gmail.com	\N	MB076	3	2024-04-05	28621460.00	28406871	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.491522+07
179	CUST179	Nông Hà Minh	0993209755	customer179@outlook.com	\N	MB179	5	2024-03-06	119181880.00	178590530	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.503402+07
106	CUST106	Vũ Hùng Loan	0962308570	customer106@hotmail.com	\N	MB106	2	2024-02-11	14243200.00	12710791	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.527602+07
165	CUST165	Phan Duy Yến	0953036925	customer165@yahoo.com	\N	MB165	2	2024-05-20	12945280.00	11394788	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.533614+07
54	CUST054	Lý Hoàng Dũng	0941666630	customer054@hotmail.com	\N	MB054	3	2024-06-23	27101700.00	27336707	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.540112+07
30	CUST030	Đỗ Thu Khách	0901370350	customer030@hotmail.com	\N	MB030	3	2024-06-07	36198480.00	38953691	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.546069+07
18	CUST018	Trịnh Công Đức	0981222210	customer018@hotmail.com	\N	MB018	3	2024-02-27	44134720.00	51058990	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.587811+07
188	CUST188	Đặng Thúy Quỳnh	0983320860	customer188@gmail.com	\N	MB188	4	2024-04-05	63617280.00	76509961	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.59433+07
152	CUST152	Ngô Gia Vinh	0922876440	customer152@gmail.com	\N	MB152	4	2024-08-09	51022320.00	57881921	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.602128+07
118	CUST118	Trịnh Công Bình	0982456710	customer118@hotmail.com	\N	MB118	2	2024-06-19	7230760.00	6306256	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.65306+07
68	CUST068	Đặng Thúy Quỳnh	0981839460	customer068@gmail.com	\N	MB068	4	2024-04-09	76012140.00	97439386	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.762793+07
46	CUST046	Vũ Hùng Loan	0961567870	customer046@hotmail.com	\N	MB046	4	2024-06-27	81072800.00	100092694	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.787475+07
121	CUST121	Trần Minh Hoa	0912493745	customer121@yahoo.com	\N	MB121	2	2024-01-28	15977980.00	14073347	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.969734+07
125	CUST125	Phan Duy Linh	0952543125	customer125@yahoo.com	\N	MB125	4	2024-05-12	72199160.00	89623275	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.613698+07
123	CUST123	Phạm Kim Khuê	0932518435	customer123@outlook.com	\N	MB123	3	2024-03-06	47004000.00	50352399	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.666006+07
85	CUST085	Phan Duy Phát	0952049325	customer085@yahoo.com	\N	MB085	3	2024-05-04	43412180.00	48309017	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.698518+07
21	CUST021	Trần Minh Sáng	0911259245	customer021@yahoo.com	\N	MB021	3	2024-05-08	34169440.00	35731960	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.72131+07
87	CUST087	Võ Thị Phương	0972074015	customer087@outlook.com	\N	MB087	3	2024-07-10	20561300.00	17033192	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.723981+07
71	CUST071	Hồ Bảo Châu	0911876495	customer071@outlook.com	\N	MB071	4	2024-07-18	54497800.00	65810743	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.727872+07
142	CUST142	Lê Hữu Tuấn	0922752990	customer142@hotmail.com	\N	MB142	4	2024-06-07	54317500.00	62347507	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.743608+07
151	CUST151	Hồ Bảo Hoa	0912864095	customer151@outlook.com	\N	MB151	2	2024-07-06	19362120.00	18449903	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.750138+07
81	CUST081	Trần Minh Sáng	0911999945	customer081@yahoo.com	\N	MB081	4	2024-01-20	66833340.00	84501272	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.764992+07
159	CUST159	Nông Hà Hằng	0992962855	customer159@outlook.com	\N	MB159	3	2024-07-02	41471500.00	45862770	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.782505+07
22	CUST022	Lê Hữu Tuấn	0921271590	customer022@hotmail.com	\N	MB022	4	2024-06-11	71907340.00	89814176	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.789534+07
120	CUST120	Nguyễn Văn Khách	0902481400	customer120@gmail.com	\N	MB120	2	2024-08-25	17724580.00	16626500	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.793934+07
194	CUST194	Lý Hoàng Long	0943394930	customer194@hotmail.com	\N	MB194	2	2024-02-23	10639940.00	8821785	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.82139+07
41	CUST041	Trần Minh Châu	0911506145	customer041@yahoo.com	\N	MB041	2	2024-01-12	17207960.00	16036693	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.825732+07
117	CUST117	Tôn Hải Phương	0972444365	customer117@yahoo.com	\N	MB117	3	2024-05-16	23599200.00	21399672	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.831823+07
6	CUST006	Vũ Hùng Sơn	0961074070	customer006@hotmail.com	\N	MB006	4	2024-06-19	70448140.00	81803411	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.837872+07
98	CUST098	Trịnh Công Quỳnh	0982209810	customer098@hotmail.com	\N	MB098	4	2024-02-15	59413880.00	71890729	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.850059+07
56	CUST056	Cao Thanh Nam	0961691320	customer056@gmail.com	\N	MB056	3	2024-08-01	42520640.00	47493030	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.864397+07
42	CUST042	Lê Hữu Nga	0921518490	customer042@hotmail.com	\N	MB042	4	2024-02-15	58413700.00	62103464	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.872868+07
122	CUST122	Lê Hữu Vinh	0922506090	customer122@hotmail.com	\N	MB122	4	2024-02-03	65563280.00	75181789	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.896946+07
60	CUST060	Nguyễn Văn Khách	0901740700	customer060@gmail.com	\N	MB060	4	2024-04-13	97777530.00	131059126	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.920495+07
27	CUST027	Võ Thị Phương	0971333315	customer027@outlook.com	\N	MB027	2	2024-03-26	19809160.00	17229728	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.928514+07
8	CUST008	Đặng Thúy Quỳnh	0981098760	customer008@gmail.com	\N	MB008	4	2024-08-25	73398840.00	84422431	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.934217+07
62	CUST062	Lê Hữu Vinh	0921765390	customer062@hotmail.com	\N	MB062	5	2024-06-19	135323340.00	211878770	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:21.958288+07
\.


--
-- TOC entry 5336 (class 0 OID 36801)
-- Dependencies: 231
-- Data for Name: discount_rules; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.discount_rules (rule_id, category_id, days_before_expiry, discount_percentage, rule_name, is_active, created_at) FROM stdin;
1	5	5	50.00	Thực phẩm đồ khô - giảm 50% khi hạn dưới 5 ngày	t	2025-09-28 03:46:20.781594+07
2	5	15	20.00	Thực phẩm đồ khô - giảm 20% khi hạn dưới 15 ngày	t	2025-09-28 03:46:20.781594+07
3	6	1	50.00	Rau quả - giảm 50% khi hạn dưới 1 ngày	t	2025-09-28 03:46:20.781594+07
4	6	3	30.00	Rau quả - giảm 30% khi hạn dưới 3 ngày	t	2025-09-28 03:46:20.781594+07
5	7	2	40.00	Thịt cá - giảm 40% khi hạn dưới 2 ngày	t	2025-09-28 03:46:20.781594+07
6	7	5	20.00	Thịt cá - giảm 20% khi hạn dưới 5 ngày	t	2025-09-28 03:46:20.781594+07
7	8	3	35.00	Sữa trứng - giảm 35% khi hạn dưới 3 ngày	t	2025-09-28 03:46:20.781594+07
8	8	7	15.00	Sữa trứng - giảm 15% khi hạn dưới 7 ngày	t	2025-09-28 03:46:20.781594+07
9	9	30	25.00	Đồ uống có cồn - giảm 25% khi hạn dưới 30 ngày	t	2025-09-28 03:46:20.781594+07
10	10	10	20.00	Đồ uống không cồn - giảm 20% khi hạn dưới 10 ngày	t	2025-09-28 03:46:20.781594+07
11	10	5	35.00	Đồ uống không cồn - giảm 35% khi hạn dưới 5 ngày	t	2025-09-28 03:46:20.781594+07
12	11	15	15.00	Đồ uống nóng - giảm 15% khi hạn dưới 15 ngày	t	2025-09-28 03:46:20.781594+07
\.


--
-- TOC entry 5338 (class 0 OID 36810)
-- Dependencies: 233
-- Data for Name: display_shelves; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.display_shelves (shelf_id, shelf_code, shelf_name, category_id, location, max_capacity, is_active, created_at) FROM stdin;
1	SH001	Quầy văn phòng phẩm 1	1	Khu A - Tầng 1	500	t	2025-09-28 03:46:20.781594+07
2	SH002	Quầy đồ gia dụng 1	2	Khu B - Tầng 1	200	t	2025-09-28 03:46:20.781594+07
3	SH003	Quầy điện tử 1	3	Khu C - Tầng 1	300	t	2025-09-28 03:46:20.781594+07
4	SH004	Quầy thực phẩm khô	5	Khu D - Tầng 1	800	t	2025-09-28 03:46:20.781594+07
5	SH005	Quầy đồ uống không cồn	10	Khu E - Tầng 1	600	t	2025-09-28 03:46:20.781594+07
6	SH006	Quầy văn phòng phẩm 2	1	Khu A - Tầng 2	400	t	2025-09-28 03:46:20.781594+07
7	SH007	Quầy rau quả tươi	6	Khu F - Tầng 1	300	t	2025-09-28 03:46:20.781594+07
8	SH008	Quầy mỹ phẩm	12	Khu G - Tầng 1	250	t	2025-09-28 03:46:20.781594+07
9	SH009	Quầy thời trang	17	Khu H - Tầng 1	200	t	2025-09-28 03:46:20.781594+07
10	SH010	Quầy đồ bếp	4	Khu I - Tầng 1	150	t	2025-09-28 03:46:20.781594+07
\.


--
-- TOC entry 5352 (class 0 OID 36905)
-- Dependencies: 247
-- Data for Name: employee_work_hours; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.employee_work_hours (work_hour_id, employee_id, work_date, check_in_time, check_out_time, total_hours, created_at) FROM stdin;
1	1	2025-09-01	2025-09-01 08:00:00+07	2025-09-01 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
2	3	2025-09-01	2025-09-01 08:00:00+07	2025-09-01 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
3	5	2025-09-01	2025-09-01 08:00:00+07	2025-09-01 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
4	2	2025-09-01	2025-09-01 14:00:00+07	2025-09-01 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
5	4	2025-09-01	2025-09-01 14:00:00+07	2025-09-01 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
6	6	2025-09-01	2025-09-01 14:00:00+07	2025-09-01 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
7	1	2025-09-02	2025-09-02 08:00:00+07	2025-09-02 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
8	3	2025-09-02	2025-09-02 08:00:00+07	2025-09-02 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
9	5	2025-09-02	2025-09-02 08:00:00+07	2025-09-02 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
10	2	2025-09-02	2025-09-02 14:00:00+07	2025-09-02 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
11	4	2025-09-02	2025-09-02 14:00:00+07	2025-09-02 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
12	6	2025-09-02	2025-09-02 14:00:00+07	2025-09-02 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
13	1	2025-09-03	2025-09-03 08:00:00+07	2025-09-03 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
14	3	2025-09-03	2025-09-03 08:00:00+07	2025-09-03 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
15	5	2025-09-03	2025-09-03 08:00:00+07	2025-09-03 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
16	2	2025-09-03	2025-09-03 14:00:00+07	2025-09-03 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
17	4	2025-09-03	2025-09-03 14:00:00+07	2025-09-03 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
18	6	2025-09-03	2025-09-03 14:00:00+07	2025-09-03 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
19	1	2025-09-04	2025-09-04 08:00:00+07	2025-09-04 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
20	3	2025-09-04	2025-09-04 08:00:00+07	2025-09-04 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
21	5	2025-09-04	2025-09-04 08:00:00+07	2025-09-04 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
22	2	2025-09-04	2025-09-04 14:00:00+07	2025-09-04 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
23	4	2025-09-04	2025-09-04 14:00:00+07	2025-09-04 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
24	6	2025-09-04	2025-09-04 14:00:00+07	2025-09-04 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
25	1	2025-09-05	2025-09-05 08:00:00+07	2025-09-05 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
26	3	2025-09-05	2025-09-05 08:00:00+07	2025-09-05 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
27	5	2025-09-05	2025-09-05 08:00:00+07	2025-09-05 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
28	2	2025-09-05	2025-09-05 14:00:00+07	2025-09-05 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
29	4	2025-09-05	2025-09-05 14:00:00+07	2025-09-05 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
30	6	2025-09-05	2025-09-05 14:00:00+07	2025-09-05 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
31	1	2025-09-06	2025-09-06 08:00:00+07	2025-09-06 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
32	3	2025-09-06	2025-09-06 08:00:00+07	2025-09-06 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
33	5	2025-09-06	2025-09-06 08:00:00+07	2025-09-06 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
34	2	2025-09-06	2025-09-06 14:00:00+07	2025-09-06 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
35	4	2025-09-06	2025-09-06 14:00:00+07	2025-09-06 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
36	6	2025-09-06	2025-09-06 14:00:00+07	2025-09-06 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
37	1	2025-09-08	2025-09-08 08:00:00+07	2025-09-08 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
38	3	2025-09-08	2025-09-08 08:00:00+07	2025-09-08 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
39	5	2025-09-08	2025-09-08 08:00:00+07	2025-09-08 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
40	2	2025-09-08	2025-09-08 14:00:00+07	2025-09-08 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
41	4	2025-09-08	2025-09-08 14:00:00+07	2025-09-08 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
42	6	2025-09-08	2025-09-08 14:00:00+07	2025-09-08 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
43	1	2025-09-09	2025-09-09 08:00:00+07	2025-09-09 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
44	3	2025-09-09	2025-09-09 08:00:00+07	2025-09-09 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
45	5	2025-09-09	2025-09-09 08:00:00+07	2025-09-09 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
46	2	2025-09-09	2025-09-09 14:00:00+07	2025-09-09 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
47	4	2025-09-09	2025-09-09 14:00:00+07	2025-09-09 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
48	6	2025-09-09	2025-09-09 14:00:00+07	2025-09-09 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
49	1	2025-09-10	2025-09-10 08:00:00+07	2025-09-10 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
50	3	2025-09-10	2025-09-10 08:00:00+07	2025-09-10 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
51	5	2025-09-10	2025-09-10 08:00:00+07	2025-09-10 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
52	2	2025-09-10	2025-09-10 14:00:00+07	2025-09-10 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
53	4	2025-09-10	2025-09-10 14:00:00+07	2025-09-10 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
54	6	2025-09-10	2025-09-10 14:00:00+07	2025-09-10 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
55	1	2025-09-11	2025-09-11 08:00:00+07	2025-09-11 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
56	3	2025-09-11	2025-09-11 08:00:00+07	2025-09-11 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
57	5	2025-09-11	2025-09-11 08:00:00+07	2025-09-11 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
58	2	2025-09-11	2025-09-11 14:00:00+07	2025-09-11 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
59	4	2025-09-11	2025-09-11 14:00:00+07	2025-09-11 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
60	6	2025-09-11	2025-09-11 14:00:00+07	2025-09-11 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
61	1	2025-09-12	2025-09-12 08:00:00+07	2025-09-12 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
62	3	2025-09-12	2025-09-12 08:00:00+07	2025-09-12 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
63	5	2025-09-12	2025-09-12 08:00:00+07	2025-09-12 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
64	2	2025-09-12	2025-09-12 14:00:00+07	2025-09-12 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
65	4	2025-09-12	2025-09-12 14:00:00+07	2025-09-12 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
66	6	2025-09-12	2025-09-12 14:00:00+07	2025-09-12 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
67	1	2025-09-13	2025-09-13 08:00:00+07	2025-09-13 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
68	3	2025-09-13	2025-09-13 08:00:00+07	2025-09-13 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
69	5	2025-09-13	2025-09-13 08:00:00+07	2025-09-13 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
70	2	2025-09-13	2025-09-13 14:00:00+07	2025-09-13 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
71	4	2025-09-13	2025-09-13 14:00:00+07	2025-09-13 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
72	6	2025-09-13	2025-09-13 14:00:00+07	2025-09-13 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
73	1	2025-09-15	2025-09-15 08:00:00+07	2025-09-15 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
74	3	2025-09-15	2025-09-15 08:00:00+07	2025-09-15 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
75	5	2025-09-15	2025-09-15 08:00:00+07	2025-09-15 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
76	2	2025-09-15	2025-09-15 14:00:00+07	2025-09-15 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
77	4	2025-09-15	2025-09-15 14:00:00+07	2025-09-15 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
78	6	2025-09-15	2025-09-15 14:00:00+07	2025-09-15 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
79	1	2025-09-16	2025-09-16 08:00:00+07	2025-09-16 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
80	3	2025-09-16	2025-09-16 08:00:00+07	2025-09-16 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
81	5	2025-09-16	2025-09-16 08:00:00+07	2025-09-16 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
82	2	2025-09-16	2025-09-16 14:00:00+07	2025-09-16 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
83	4	2025-09-16	2025-09-16 14:00:00+07	2025-09-16 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
84	6	2025-09-16	2025-09-16 14:00:00+07	2025-09-16 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
85	1	2025-09-17	2025-09-17 08:00:00+07	2025-09-17 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
86	3	2025-09-17	2025-09-17 08:00:00+07	2025-09-17 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
87	5	2025-09-17	2025-09-17 08:00:00+07	2025-09-17 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
88	2	2025-09-17	2025-09-17 14:00:00+07	2025-09-17 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
89	4	2025-09-17	2025-09-17 14:00:00+07	2025-09-17 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
90	6	2025-09-17	2025-09-17 14:00:00+07	2025-09-17 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
91	1	2025-09-18	2025-09-18 08:00:00+07	2025-09-18 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
92	3	2025-09-18	2025-09-18 08:00:00+07	2025-09-18 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
93	5	2025-09-18	2025-09-18 08:00:00+07	2025-09-18 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
94	2	2025-09-18	2025-09-18 14:00:00+07	2025-09-18 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
95	4	2025-09-18	2025-09-18 14:00:00+07	2025-09-18 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
96	6	2025-09-18	2025-09-18 14:00:00+07	2025-09-18 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
97	1	2025-09-19	2025-09-19 08:00:00+07	2025-09-19 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
98	3	2025-09-19	2025-09-19 08:00:00+07	2025-09-19 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
99	5	2025-09-19	2025-09-19 08:00:00+07	2025-09-19 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
100	2	2025-09-19	2025-09-19 14:00:00+07	2025-09-19 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
101	4	2025-09-19	2025-09-19 14:00:00+07	2025-09-19 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
102	6	2025-09-19	2025-09-19 14:00:00+07	2025-09-19 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
103	1	2025-09-20	2025-09-20 08:00:00+07	2025-09-20 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
104	3	2025-09-20	2025-09-20 08:00:00+07	2025-09-20 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
105	5	2025-09-20	2025-09-20 08:00:00+07	2025-09-20 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
106	2	2025-09-20	2025-09-20 14:00:00+07	2025-09-20 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
107	4	2025-09-20	2025-09-20 14:00:00+07	2025-09-20 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
108	6	2025-09-20	2025-09-20 14:00:00+07	2025-09-20 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
109	1	2025-09-22	2025-09-22 08:00:00+07	2025-09-22 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
110	3	2025-09-22	2025-09-22 08:00:00+07	2025-09-22 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
111	5	2025-09-22	2025-09-22 08:00:00+07	2025-09-22 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
112	2	2025-09-22	2025-09-22 14:00:00+07	2025-09-22 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
113	4	2025-09-22	2025-09-22 14:00:00+07	2025-09-22 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
114	6	2025-09-22	2025-09-22 14:00:00+07	2025-09-22 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
115	1	2025-09-23	2025-09-23 08:00:00+07	2025-09-23 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
116	3	2025-09-23	2025-09-23 08:00:00+07	2025-09-23 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
117	5	2025-09-23	2025-09-23 08:00:00+07	2025-09-23 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
118	2	2025-09-23	2025-09-23 14:00:00+07	2025-09-23 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
119	4	2025-09-23	2025-09-23 14:00:00+07	2025-09-23 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
120	6	2025-09-23	2025-09-23 14:00:00+07	2025-09-23 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
121	1	2025-09-24	2025-09-24 08:00:00+07	2025-09-24 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
122	3	2025-09-24	2025-09-24 08:00:00+07	2025-09-24 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
123	5	2025-09-24	2025-09-24 08:00:00+07	2025-09-24 16:00:00+07	8.00	2025-09-28 03:46:20.781594+07
124	2	2025-09-24	2025-09-24 14:00:00+07	2025-09-24 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
125	4	2025-09-24	2025-09-24 14:00:00+07	2025-09-24 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
126	6	2025-09-24	2025-09-24 14:00:00+07	2025-09-24 22:00:00+07	8.00	2025-09-28 03:46:20.781594+07
\.


--
-- TOC entry 5340 (class 0 OID 36820)
-- Dependencies: 235
-- Data for Name: employees; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.employees (employee_id, employee_code, full_name, position_id, phone, email, address, hire_date, id_card, bank_account, is_active, created_at, updated_at) FROM stdin;
1	EMP001	Nguyễn Quản Lý	1	0901111111	manager@supermarket.vn	\N	2024-01-01	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.787327+07
2	EMP002	Trần Giám Sát	2	0902222222	supervisor@supermarket.vn	\N	2024-01-15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.787327+07
3	EMP003	Lê Thu Ngân	3	0903333333	cashier1@supermarket.vn	\N	2024-02-01	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.787327+07
4	EMP004	Phạm Bán Hàng	4	0904444444	sales1@supermarket.vn	\N	2024-02-15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.787327+07
5	EMP005	Hoàng Thủ Kho	5	0905555555	stock1@supermarket.vn	\N	2024-03-01	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.787327+07
6	EMP006	Võ Thu Ngân 2	3	0906666666	cashier2@supermarket.vn	\N	2024-03-16	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.787327+07
\.


--
-- TOC entry 5332 (class 0 OID 36773)
-- Dependencies: 227
-- Data for Name: membership_levels; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.membership_levels (level_id, level_name, min_spending, discount_percentage, points_multiplier, created_at) FROM stdin;
1	Bronze	0.00	0.00	1.00	2025-09-28 03:46:20.781594+07
2	Silver	5000000.00	3.00	1.20	2025-09-28 03:46:20.781594+07
3	Gold	20000000.00	5.00	1.50	2025-09-28 03:46:20.781594+07
4	Platinum	50000000.00	8.00	2.00	2025-09-28 03:46:20.781594+07
5	Diamond	100000000.00	10.00	2.50	2025-09-28 03:46:20.781594+07
\.


--
-- TOC entry 5330 (class 0 OID 36762)
-- Dependencies: 225
-- Data for Name: positions; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.positions (position_id, position_code, position_name, base_salary, hourly_rate, created_at) FROM stdin;
1	MGR	Quản lý	15000000.00	100000.00	2025-09-28 03:46:20.781594+07
2	SUP	Giám sát	10000000.00	70000.00	2025-09-28 03:46:20.781594+07
3	CASH	Thu ngân	7000000.00	50000.00	2025-09-28 03:46:20.781594+07
4	SALE	Nhân viên bán hàng	6000000.00	45000.00	2025-09-28 03:46:20.781594+07
5	STOCK	Nhân viên kho	6500000.00	48000.00	2025-09-28 03:46:20.781594+07
6	SEC	Bảo vệ	5500000.00	40000.00	2025-09-28 03:46:20.781594+07
\.


--
-- TOC entry 5324 (class 0 OID 36730)
-- Dependencies: 219
-- Data for Name: product_categories; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.product_categories (category_id, category_name, description, created_at, updated_at) FROM stdin;
1	Văn phòng phẩm	Đồ dùng văn phòng, học tập	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
2	Đồ gia dụng	Đồ dùng gia đình	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
3	Đồ điện tử	Thiết bị điện tử tiêu dùng	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
4	Đồ bếp	Dụng cụ nhà bếp	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
5	Thực phẩm - Đồ khô	Thực phẩm khô có hạn sử dụng dài	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
6	Thực phẩm - Rau quả	Rau củ quả tươi sống có hạn ngắn	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
7	Thực phẩm - Thịt cá	Thịt, cá và hải sản	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
8	Thực phẩm - Sữa trứng	Sữa, trứng và các sản phẩm từ sữa	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
9	Đồ uống - Có cồn	Bia, rượu và đồ uống có cồn	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
10	Đồ uống - Không cồn	Nước ngọt, nước suối và đồ uống không cồn	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
11	Đồ uống - Nóng	Cà phê, trà và đồ uống nóng	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
12	Mỹ phẩm - Chăm sóc da	Kem dưỡng da, sữa rửa mặt	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
13	Mỹ phẩm - Trang điểm	Son, phấn và đồ trang điểm	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
14	Mỹ phẩm - Vệ sinh cá nhân	Dầu gội, kem đánh răng, xà phòng	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
15	Thời trang - Nam	Quần áo nam và phụ kiện	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
16	Thời trang - Nữ	Quần áo nữ và phụ kiện	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
17	Thời trang - Unisex	Đồ dùng chung cho nam nữ	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.783198+07
\.


--
-- TOC entry 5334 (class 0 OID 36785)
-- Dependencies: 229
-- Data for Name: products; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.products (product_id, product_code, product_name, category_id, supplier_id, unit, import_price, selling_price, shelf_life_days, low_stock_threshold, barcode, description, is_active, created_at, updated_at) FROM stdin;
1	VPP001	Bút bi Thiên Long	1	3	Cây	3000.00	5000.00	365	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
2	VPP002	Vở học sinh 96 trang	1	3	Quyển	8000.00	12000.00	365	30	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
3	VPP003	Bút chì 2B	1	3	Cây	2000.00	3500.00	365	25	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
4	VPP004	Thước kẻ nhựa 30cm	1	3	Cái	5000.00	8000.00	365	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
5	VPP005	Gôm tẩy Hồng Hà	1	3	Cái	1500.00	3000.00	365	30	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
6	VPP006	Bút máy học sinh	1	3	Cây	15000.00	25000.00	365	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
7	VPP007	Giấy A4 Double A	1	3	Ream	45000.00	65000.00	365	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
8	VPP008	Keo dán UHU	1	3	Tuýp	8000.00	12000.00	730	25	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
9	VPP009	Bìa hồ sơ	1	3	Cái	3000.00	5000.00	365	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
10	VPP010	Kẹp giấy	1	3	Hộp	12000.00	18000.00	365	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
11	VPP011	Bút dạ quang	1	3	Cây	8000.00	12000.00	365	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
12	VPP012	Stapler kim bấm	1	3	Cái	35000.00	55000.00	365	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
13	VPP013	Kim bấm số 10	1	3	Hộp	5000.00	8000.00	365	25	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
14	VPP014	Bảng viết bút lông	1	3	Cái	150000.00	250000.00	365	5	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
15	VPP015	Máy tính Casio FX-580	1	3	Cái	280000.00	450000.00	365	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
16	GD001	Chảo chống dính 26cm	2	4	Cái	150000.00	250000.00	\N	5	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
17	GD002	Bộ nồi inox 3 món	2	4	Bộ	350000.00	550000.00	\N	3	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
18	GD003	Khăn tắm cotton	2	4	Cái	45000.00	75000.00	\N	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
19	GD004	Bộ dao inox 6 món	2	4	Bộ	120000.00	200000.00	\N	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
20	GD005	Thớt gỗ cao su	2	4	Cái	35000.00	60000.00	\N	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
21	GD006	Bộ chén đĩa sứ	2	4	Bộ	180000.00	300000.00	\N	6	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
22	GD007	Gương soi trang điểm	2	4	Cái	80000.00	130000.00	\N	12	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
23	GD008	Thùng rác có nắp	2	4	Cái	65000.00	110000.00	\N	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
24	GD009	Dây phơi quần áo	2	4	Cái	25000.00	45000.00	\N	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
25	GD010	Bộ ly thủy tinh	2	4	Bộ	90000.00	150000.00	\N	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
26	GD011	Giá để giày dép	2	4	Cái	120000.00	200000.00	\N	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
27	GD012	Rổ đựng đồ đa năng	2	4	Cái	55000.00	90000.00	\N	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
28	GD013	Kệ gia vị 3 tầng	2	4	Cái	85000.00	140000.00	\N	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
29	GD014	Bàn ủi hơi nước	2	4	Cái	300000.00	480000.00	\N	5	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
30	GD015	Tủ nhựa 5 ngăn	2	4	Cái	450000.00	750000.00	\N	3	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
31	DT001	Tai nghe Bluetooth	3	2	Cái	200000.00	350000.00	\N	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
32	DT002	Sạc dự phòng 10000mAh	3	2	Cái	180000.00	300000.00	\N	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
33	DT003	Cáp USB Type-C	3	2	Cái	25000.00	50000.00	\N	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
34	DT004	Loa Bluetooth mini	3	2	Cái	150000.00	250000.00	\N	12	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
35	DT005	Chuột không dây	3	2	Cái	80000.00	130000.00	\N	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
36	DT006	Bàn phím gaming	3	2	Cái	350000.00	580000.00	\N	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
37	DT007	Webcam HD 720p	3	2	Cái	120000.00	200000.00	\N	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
38	DT008	Đèn LED USB	3	2	Cái	35000.00	60000.00	\N	25	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
39	DT009	Hub USB 4 cổng	3	2	Cái	65000.00	110000.00	\N	18	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
40	DT010	Thẻ nhớ MicroSD 32GB	3	2	Cái	90000.00	150000.00	\N	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
41	DT011	Giá đỡ điện thoại	3	2	Cái	45000.00	75000.00	\N	22	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
42	DT012	Ốp lưng iPhone	3	2	Cái	30000.00	55000.00	\N	30	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
43	DT013	Miếng dán màn hình	3	2	Cái	15000.00	30000.00	\N	40	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
44	DT014	Pin AA Panasonic	3	2	Vỉ	12000.00	20000.00	\N	35	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
45	DT015	Đồng hồ thông minh	3	2	Cái	800000.00	1300000.00	\N	5	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
46	DB001	Nồi cơm điện 1.8L	4	4	Cái	380000.00	650000.00	\N	5	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
47	DB002	Máy xay sinh tố	4	4	Cái	250000.00	420000.00	\N	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
48	DB003	Ấm đun nước siêu tốc	4	4	Cái	180000.00	300000.00	\N	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
49	DB004	Bếp gas hồng ngoại	4	4	Cái	450000.00	750000.00	\N	6	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
50	DB005	Lò vi sóng 20L	4	4	Cái	1200000.00	1950000.00	\N	3	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
51	DB006	Máy pha cà phê	4	4	Cái	650000.00	1100000.00	\N	4	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
52	DB007	Nồi áp suất 5L	4	4	Cái	320000.00	520000.00	\N	6	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
53	DB008	Máy nướng bánh mì	4	4	Cái	280000.00	450000.00	\N	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
54	DB009	Bộ dao thớt inox	4	4	Bộ	95000.00	160000.00	\N	12	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
55	DB010	Máy đánh trứng cầm tay	4	4	Cái	85000.00	140000.00	\N	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
56	TP001	Gạo ST25 5kg	5	1	Bao	120000.00	180000.00	180	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
57	TP002	Mì gói Hảo Hảo	5	1	Thùng	85000.00	115000.00	180	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
58	TP003	Dầu ăn Tường An 1L	5	1	Chai	35000.00	52000.00	365	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
59	TP004	Muối I-ốt 500g	5	1	Gói	8000.00	12000.00	730	25	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
60	TP005	Đường cát trắng 1kg	5	1	Gói	18000.00	25000.00	365	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
61	TP006	Nước mắm Phú Quốc	5	1	Chai	45000.00	70000.00	730	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
62	TP007	Bột mì đa dụng 1kg	5	1	Gói	22000.00	35000.00	365	18	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
63	TP008	Bánh quy Oreo	5	1	Gói	15000.00	25000.00	120	25	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
64	TP009	Cà rốt 1kg	6	1	Kg	15000.00	25000.00	7	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
65	TP010	Khoai tây 1kg	6	1	Kg	18000.00	28000.00	10	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
66	TP011	Bắp cải 1kg	6	1	Kg	12000.00	20000.00	5	25	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
67	TP012	Táo Fuji 1kg	6	1	Kg	35000.00	55000.00	14	12	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
68	TP013	Chuối tiêu 1kg	6	1	Kg	25000.00	40000.00	3	18	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
69	TP014	Thịt heo ba chỉ 500g	7	1	Gói	65000.00	95000.00	5	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
70	TP015	Cá thu đông lạnh	7	1	Con	85000.00	120000.00	90	12	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
71	TP016	Tôm đông lạnh 500g	7	1	Gói	120000.00	180000.00	90	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
72	TP017	Xúc xích Đức Việt	7	1	Gói	55000.00	85000.00	60	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
73	TP018	Trứng gà hộp 10 quả	8	1	Hộp	30000.00	45000.00	30	30	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
74	TP019	Sữa tươi Vinamilk 1L	8	1	Hộp	28000.00	42000.00	7	30	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
75	TP020	Phô mai lát Laughing Cow	8	1	Hộp	35000.00	55000.00	60	18	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
76	DU001	Bia Saigon lon 330ml	9	5	Thùng	220000.00	320000.00	365	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
77	DU002	Bia Heineken lon 330ml	9	5	Thùng	280000.00	420000.00	365	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
78	DU003	Rượu vang Đà Lạt	9	5	Chai	120000.00	180000.00	730	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
79	DU004	Nước suối Aquafina 500ml	10	5	Thùng	80000.00	120000.00	365	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
80	DU005	Coca Cola 330ml	10	5	Thùng	180000.00	260000.00	365	12	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
81	DU006	Pepsi lon 330ml	10	5	Thùng	175000.00	250000.00	365	12	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
82	DU007	Nước cam Tropicana	10	5	Thùng	200000.00	290000.00	180	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
83	DU008	Nước dừa Cocoxim	10	5	Thùng	180000.00	260000.00	365	12	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
84	DU009	Nước tăng lực RedBull	10	5	Thùng	280000.00	400000.00	365	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
85	DU010	Sữa chua uống TH	10	5	Thùng	120000.00	180000.00	15	18	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
86	DU011	Nước khoáng LaVie	10	5	Thùng	90000.00	135000.00	365	16	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
87	DU012	Cà phê Nescafe Gold	11	5	Lọ	85000.00	130000.00	730	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
88	DU013	Trà xanh không độ	11	5	Thùng	140000.00	200000.00	180	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
89	DU014	Trà đá Lipton chai	11	5	Thùng	150000.00	220000.00	180	14	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
90	DU015	Trà sữa Lipton	11	5	Thùng	160000.00	230000.00	180	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
91	MP001	Kem chống nắng Nivea	12	1	Tuýp	65000.00	110000.00	365	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
92	MP002	Sữa rửa mặt Cetaphil	12	1	Chai	180000.00	280000.00	365	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
93	MP003	Nước hoa hồng Mamonde	12	2	Chai	120000.00	190000.00	365	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
94	MP004	Kem dưỡng da Olay	12	2	Lọ	150000.00	240000.00	365	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
95	MP005	Son dưỡng môi Vaseline	13	2	Cây	35000.00	60000.00	365	18	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
96	MP006	Mascara Maybelline	13	2	Cây	180000.00	290000.00	365	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
97	MP007	Phấn phủ L'Oreal	13	3	Hộp	250000.00	400000.00	365	6	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
98	MP008	Dầu gội Head & Shoulders	14	1	Chai	85000.00	130000.00	365	12	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
99	MP009	Kem đánh răng Colgate	14	1	Tuýp	25000.00	40000.00	730	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
100	MP010	Xịt khử mùi Rexona	14	3	Chai	55000.00	90000.00	365	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
101	TT001	Quần jean nam	15	3	Cái	200000.00	350000.00	365	10	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
102	TT002	Áo polo nam	15	3	Cái	120000.00	200000.00	365	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
103	TT003	Váy maxi nữ	16	3	Cái	180000.00	320000.00	365	12	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
104	TT004	Túi xách nữ	16	3	Cái	120000.00	220000.00	365	8	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
105	TT005	Áo thun cotton unisex	17	3	Cái	80000.00	150000.00	365	20	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
106	TT006	Dép tông nam nữ	17	3	Đôi	45000.00	80000.00	365	15	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
107	TT007	Đồng hồ đeo tay	17	3	Cái	150000.00	280000.00	365	12	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.788364+07
\.


--
-- TOC entry 5360 (class 0 OID 36954)
-- Dependencies: 255
-- Data for Name: purchase_order_details; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.purchase_order_details (detail_id, order_id, product_id, quantity, unit_price, subtotal, created_at) FROM stdin;
1	1	16	254	150000.00	38100000.00	2025-09-28 03:46:20.845113+07
2	1	17	139	350000.00	48650000.00	2025-09-28 03:46:20.845113+07
3	1	18	380	45000.00	17100000.00	2025-09-28 03:46:20.845113+07
4	1	19	109	120000.00	13080000.00	2025-09-28 03:46:20.845113+07
5	1	20	107	35000.00	3745000.00	2025-09-28 03:46:20.845113+07
6	1	21	122	180000.00	21960000.00	2025-09-28 03:46:20.845113+07
7	1	22	130	80000.00	10400000.00	2025-09-28 03:46:20.845113+07
8	1	23	341	65000.00	22165000.00	2025-09-28 03:46:20.845113+07
9	1	24	444	25000.00	11100000.00	2025-09-28 03:46:20.845113+07
10	1	25	258	90000.00	23220000.00	2025-09-28 03:46:20.845113+07
11	1	26	341	120000.00	40920000.00	2025-09-28 03:46:20.845113+07
12	1	27	421	55000.00	23155000.00	2025-09-28 03:46:20.845113+07
13	1	28	113	85000.00	9605000.00	2025-09-28 03:46:20.845113+07
14	1	29	101	300000.00	30300000.00	2025-09-28 03:46:20.845113+07
15	1	30	469	450000.00	211050000.00	2025-09-28 03:46:20.845113+07
16	1	46	284	380000.00	107920000.00	2025-09-28 03:46:20.845113+07
17	1	47	128	250000.00	32000000.00	2025-09-28 03:46:20.845113+07
18	1	48	125	180000.00	22500000.00	2025-09-28 03:46:20.845113+07
19	1	49	100	450000.00	45000000.00	2025-09-28 03:46:20.845113+07
20	1	50	371	1200000.00	445200000.00	2025-09-28 03:46:20.845113+07
21	1	51	363	650000.00	235950000.00	2025-09-28 03:46:20.845113+07
22	1	52	174	320000.00	55680000.00	2025-09-28 03:46:20.845113+07
23	1	53	341	280000.00	95480000.00	2025-09-28 03:46:20.845113+07
24	1	54	393	95000.00	37335000.00	2025-09-28 03:46:20.845113+07
25	1	55	490	85000.00	41650000.00	2025-09-28 03:46:20.845113+07
26	2	31	381	200000.00	76200000.00	2025-09-28 03:46:20.857513+07
27	2	32	380	180000.00	68400000.00	2025-09-28 03:46:20.857513+07
28	2	33	331	25000.00	8275000.00	2025-09-28 03:46:20.857513+07
29	2	34	421	150000.00	63150000.00	2025-09-28 03:46:20.857513+07
30	2	35	176	80000.00	14080000.00	2025-09-28 03:46:20.857513+07
31	2	36	189	350000.00	66150000.00	2025-09-28 03:46:20.857513+07
32	2	37	488	120000.00	58560000.00	2025-09-28 03:46:20.857513+07
33	2	38	291	35000.00	10185000.00	2025-09-28 03:46:20.857513+07
34	2	39	496	65000.00	32240000.00	2025-09-28 03:46:20.857513+07
35	2	40	305	90000.00	27450000.00	2025-09-28 03:46:20.857513+07
36	2	41	169	45000.00	7605000.00	2025-09-28 03:46:20.857513+07
37	2	42	335	30000.00	10050000.00	2025-09-28 03:46:20.857513+07
38	2	43	140	15000.00	2100000.00	2025-09-28 03:46:20.857513+07
39	2	44	484	12000.00	5808000.00	2025-09-28 03:46:20.857513+07
40	2	45	253	800000.00	202400000.00	2025-09-28 03:46:20.857513+07
41	2	93	411	120000.00	49320000.00	2025-09-28 03:46:20.857513+07
42	2	94	437	150000.00	65550000.00	2025-09-28 03:46:20.857513+07
43	2	95	164	35000.00	5740000.00	2025-09-28 03:46:20.857513+07
44	2	96	451	180000.00	81180000.00	2025-09-28 03:46:20.857513+07
45	3	56	183	120000.00	21960000.00	2025-09-28 03:46:20.863607+07
46	3	57	275	85000.00	23375000.00	2025-09-28 03:46:20.863607+07
47	3	58	494	35000.00	17290000.00	2025-09-28 03:46:20.863607+07
48	3	59	316	8000.00	2528000.00	2025-09-28 03:46:20.863607+07
49	3	60	485	18000.00	8730000.00	2025-09-28 03:46:20.863607+07
50	3	61	425	45000.00	19125000.00	2025-09-28 03:46:20.863607+07
51	3	62	280	22000.00	6160000.00	2025-09-28 03:46:20.863607+07
52	3	63	290	15000.00	4350000.00	2025-09-28 03:46:20.863607+07
53	3	64	210	15000.00	3150000.00	2025-09-28 03:46:20.863607+07
54	3	65	450	18000.00	8100000.00	2025-09-28 03:46:20.863607+07
55	3	66	306	12000.00	3672000.00	2025-09-28 03:46:20.863607+07
56	3	67	385	35000.00	13475000.00	2025-09-28 03:46:20.863607+07
57	3	68	112	25000.00	2800000.00	2025-09-28 03:46:20.863607+07
58	3	69	428	65000.00	27820000.00	2025-09-28 03:46:20.863607+07
59	3	70	167	85000.00	14195000.00	2025-09-28 03:46:20.863607+07
60	3	71	119	120000.00	14280000.00	2025-09-28 03:46:20.863607+07
61	3	72	202	55000.00	11110000.00	2025-09-28 03:46:20.863607+07
62	3	73	262	30000.00	7860000.00	2025-09-28 03:46:20.863607+07
63	3	74	497	28000.00	13916000.00	2025-09-28 03:46:20.863607+07
64	3	75	200	35000.00	7000000.00	2025-09-28 03:46:20.863607+07
65	3	91	416	65000.00	27040000.00	2025-09-28 03:46:20.863607+07
66	3	92	325	180000.00	58500000.00	2025-09-28 03:46:20.863607+07
67	3	98	163	85000.00	13855000.00	2025-09-28 03:46:20.863607+07
68	3	99	246	25000.00	6150000.00	2025-09-28 03:46:20.863607+07
69	4	76	369	220000.00	81180000.00	2025-09-28 03:46:20.87102+07
70	4	77	225	280000.00	63000000.00	2025-09-28 03:46:20.87102+07
71	4	78	295	120000.00	35400000.00	2025-09-28 03:46:20.87102+07
72	4	79	462	80000.00	36960000.00	2025-09-28 03:46:20.87102+07
73	4	80	232	180000.00	41760000.00	2025-09-28 03:46:20.87102+07
74	4	81	469	175000.00	82075000.00	2025-09-28 03:46:20.87102+07
75	4	82	142	200000.00	28400000.00	2025-09-28 03:46:20.87102+07
76	4	83	158	180000.00	28440000.00	2025-09-28 03:46:20.87102+07
77	4	84	132	280000.00	36960000.00	2025-09-28 03:46:20.87102+07
78	4	85	261	120000.00	31320000.00	2025-09-28 03:46:20.87102+07
79	4	86	215	90000.00	19350000.00	2025-09-28 03:46:20.87102+07
80	4	87	435	85000.00	36975000.00	2025-09-28 03:46:20.87102+07
81	4	88	132	140000.00	18480000.00	2025-09-28 03:46:20.87102+07
82	4	89	417	150000.00	62550000.00	2025-09-28 03:46:20.87102+07
83	4	90	279	160000.00	44640000.00	2025-09-28 03:46:20.87102+07
84	5	1	410	3000.00	1230000.00	2025-09-28 03:46:20.876586+07
85	5	2	374	8000.00	2992000.00	2025-09-28 03:46:20.876586+07
86	5	3	486	2000.00	972000.00	2025-09-28 03:46:20.876586+07
87	5	4	283	5000.00	1415000.00	2025-09-28 03:46:20.876586+07
88	5	5	329	1500.00	493500.00	2025-09-28 03:46:20.876586+07
89	5	6	464	15000.00	6960000.00	2025-09-28 03:46:20.876586+07
90	5	7	116	45000.00	5220000.00	2025-09-28 03:46:20.876586+07
91	5	8	339	8000.00	2712000.00	2025-09-28 03:46:20.876586+07
92	5	9	395	3000.00	1185000.00	2025-09-28 03:46:20.876586+07
93	5	10	224	12000.00	2688000.00	2025-09-28 03:46:20.876586+07
94	5	11	110	8000.00	880000.00	2025-09-28 03:46:20.876586+07
95	5	12	272	35000.00	9520000.00	2025-09-28 03:46:20.876586+07
96	5	13	457	5000.00	2285000.00	2025-09-28 03:46:20.876586+07
97	5	14	340	150000.00	51000000.00	2025-09-28 03:46:20.876586+07
98	5	15	465	280000.00	130200000.00	2025-09-28 03:46:20.876586+07
99	5	97	383	250000.00	95750000.00	2025-09-28 03:46:20.876586+07
100	5	100	331	55000.00	18205000.00	2025-09-28 03:46:20.876586+07
101	5	101	174	200000.00	34800000.00	2025-09-28 03:46:20.876586+07
102	5	102	259	120000.00	31080000.00	2025-09-28 03:46:20.876586+07
103	5	103	239	180000.00	43020000.00	2025-09-28 03:46:20.876586+07
104	5	104	469	120000.00	56280000.00	2025-09-28 03:46:20.876586+07
105	5	105	451	80000.00	36080000.00	2025-09-28 03:46:20.876586+07
106	5	106	323	45000.00	14535000.00	2025-09-28 03:46:20.876586+07
107	5	107	422	150000.00	63300000.00	2025-09-28 03:46:20.876586+07
108	6	17	160	350000.00	56000000.00	2025-09-28 03:46:21.641287+07
\.


--
-- TOC entry 5356 (class 0 OID 36930)
-- Dependencies: 251
-- Data for Name: purchase_orders; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.purchase_orders (order_id, order_no, supplier_id, employee_id, order_date, delivery_date, total_amount, status, notes, created_at, updated_at) FROM stdin;
5	PO202509005	3	1	2025-09-01	2025-09-02	612802500.00	RECEIVED	\N	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.876586+07
3	PO202509003	1	1	2025-09-01	2025-09-02	336441000.00	RECEIVED	\N	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.863607+07
6	PO202509006	4	1	2025-09-14	2025-09-16	56000000.00	RECEIVED	\N	2025-09-28 03:46:21.641287+07	2025-09-28 03:46:21.641287+07
1	PO202509001	4	1	2025-09-01	2025-09-02	1643265000.00	RECEIVED	\N	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.845113+07
4	PO202509004	5	1	2025-09-01	2025-09-02	647490000.00	RECEIVED	\N	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:20.87102+07
2	PO202509002	2	1	2025-09-01	2025-09-02	854443000.00	RECEIVED	\N	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.857513+07
\.


--
-- TOC entry 5358 (class 0 OID 36944)
-- Dependencies: 253
-- Data for Name: sales_invoice_details; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.sales_invoice_details (detail_id, invoice_id, product_id, quantity, unit_price, discount_percentage, discount_amount, subtotal, created_at) FROM stdin;
1	1	20	2	60000.00	0.00	0.00	120000.00	2025-09-28 03:46:21.016783+07
2	1	34	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.016783+07
3	1	105	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.016783+07
4	1	15	1	450000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.016783+07
5	1	47	5	420000.00	0.00	0.00	2100000.00	2025-09-28 03:46:21.016783+07
6	1	35	5	130000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.016783+07
7	1	5	1	3000.00	0.00	0.00	3000.00	2025-09-28 03:46:21.016783+07
8	1	5	5	3000.00	0.00	0.00	15000.00	2025-09-28 03:46:21.016783+07
9	2	83	2	260000.00	0.00	0.00	520000.00	2025-09-28 03:46:21.030378+07
10	2	38	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.030378+07
11	2	26	3	200000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.030378+07
12	2	55	1	140000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.030378+07
13	2	34	4	250000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.030378+07
14	2	61	2	70000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.030378+07
15	2	38	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.030378+07
16	2	92	4	280000.00	0.00	0.00	1120000.00	2025-09-28 03:46:21.030378+07
17	2	68	4	40000.00	0.00	0.00	160000.00	2025-09-28 03:46:21.030378+07
18	2	51	1	1100000.00	0.00	0.00	1100000.00	2025-09-28 03:46:21.030378+07
19	3	63	3	25000.00	0.00	0.00	75000.00	2025-09-28 03:46:21.037779+07
20	3	34	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.037779+07
21	4	18	4	75000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.040038+07
22	4	28	2	140000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.040038+07
23	4	4	5	8000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.040038+07
24	4	84	4	400000.00	0.00	0.00	1600000.00	2025-09-28 03:46:21.040038+07
25	4	51	2	1100000.00	0.00	0.00	2200000.00	2025-09-28 03:46:21.040038+07
26	4	79	4	120000.00	0.00	0.00	480000.00	2025-09-28 03:46:21.040038+07
27	4	10	2	18000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.040038+07
28	5	21	4	300000.00	0.00	0.00	1200000.00	2025-09-28 03:46:21.045797+07
29	5	28	2	140000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.045797+07
30	5	93	1	190000.00	0.00	0.00	190000.00	2025-09-28 03:46:21.045797+07
31	5	68	5	40000.00	0.00	0.00	200000.00	2025-09-28 03:46:21.045797+07
32	5	63	5	25000.00	0.00	0.00	125000.00	2025-09-28 03:46:21.045797+07
33	5	48	4	300000.00	0.00	0.00	1200000.00	2025-09-28 03:46:21.045797+07
34	5	66	5	20000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.045797+07
35	5	67	1	55000.00	0.00	0.00	55000.00	2025-09-28 03:46:21.045797+07
36	6	65	2	28000.00	0.00	0.00	56000.00	2025-09-28 03:46:21.051377+07
37	6	36	4	580000.00	0.00	0.00	2320000.00	2025-09-28 03:46:21.051377+07
38	6	5	3	3000.00	0.00	0.00	9000.00	2025-09-28 03:46:21.051377+07
39	6	54	5	160000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.051377+07
40	6	38	2	60000.00	0.00	0.00	120000.00	2025-09-28 03:46:21.051377+07
41	6	32	2	300000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.051377+07
42	6	106	1	80000.00	0.00	0.00	80000.00	2025-09-28 03:46:21.051377+07
43	6	11	3	12000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.051377+07
44	6	84	2	400000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.051377+07
45	6	79	2	120000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.051377+07
46	7	49	5	750000.00	0.00	0.00	3750000.00	2025-09-28 03:46:21.057034+07
47	7	43	3	30000.00	0.00	0.00	90000.00	2025-09-28 03:46:21.057034+07
48	7	45	4	1300000.00	0.00	0.00	5200000.00	2025-09-28 03:46:21.057034+07
49	7	55	4	140000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.057034+07
50	7	3	2	3500.00	0.00	0.00	7000.00	2025-09-28 03:46:21.057034+07
51	7	55	5	140000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.057034+07
52	7	65	1	28000.00	0.00	0.00	28000.00	2025-09-28 03:46:21.057034+07
53	7	63	4	25000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.057034+07
54	7	23	2	110000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.057034+07
55	8	27	2	90000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.062376+07
56	8	38	3	60000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.062376+07
57	8	107	2	280000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.062376+07
58	8	85	1	180000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.062376+07
59	8	54	5	160000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.062376+07
60	8	27	3	90000.00	0.00	0.00	270000.00	2025-09-28 03:46:21.062376+07
61	8	38	2	60000.00	0.00	0.00	120000.00	2025-09-28 03:46:21.062376+07
62	8	50	2	1950000.00	0.00	0.00	3900000.00	2025-09-28 03:46:21.062376+07
63	8	56	5	180000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.062376+07
64	8	66	5	20000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.062376+07
65	9	8	5	12000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.0693+07
66	9	85	5	180000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.0693+07
67	9	4	2	8000.00	0.00	0.00	16000.00	2025-09-28 03:46:21.0693+07
68	9	45	3	1300000.00	0.00	0.00	3900000.00	2025-09-28 03:46:21.0693+07
69	9	91	5	110000.00	0.00	0.00	550000.00	2025-09-28 03:46:21.0693+07
70	9	93	4	190000.00	0.00	0.00	760000.00	2025-09-28 03:46:21.0693+07
71	10	44	1	20000.00	0.00	0.00	20000.00	2025-09-28 03:46:21.072439+07
72	10	68	1	40000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.072439+07
73	11	50	3	1950000.00	0.00	0.00	5850000.00	2025-09-28 03:46:21.073825+07
74	11	19	2	200000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.073825+07
75	11	6	3	25000.00	0.00	0.00	75000.00	2025-09-28 03:46:21.073825+07
76	11	92	3	280000.00	0.00	0.00	840000.00	2025-09-28 03:46:21.073825+07
77	11	22	2	130000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.073825+07
78	11	106	3	80000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.073825+07
79	11	25	5	150000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.073825+07
80	11	17	5	550000.00	0.00	0.00	2750000.00	2025-09-28 03:46:21.073825+07
81	11	12	1	55000.00	0.00	0.00	55000.00	2025-09-28 03:46:21.073825+07
82	11	19	2	200000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.073825+07
83	12	36	3	580000.00	0.00	0.00	1740000.00	2025-09-28 03:46:21.080742+07
84	12	17	2	550000.00	0.00	0.00	1100000.00	2025-09-28 03:46:21.080742+07
85	12	3	3	3500.00	0.00	0.00	10500.00	2025-09-28 03:46:21.080742+07
86	12	19	5	200000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.080742+07
87	12	6	2	25000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.080742+07
88	12	92	5	280000.00	0.00	0.00	1400000.00	2025-09-28 03:46:21.080742+07
89	12	36	3	580000.00	0.00	0.00	1740000.00	2025-09-28 03:46:21.080742+07
90	13	49	2	750000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.085831+07
91	13	12	1	55000.00	0.00	0.00	55000.00	2025-09-28 03:46:21.085831+07
92	13	19	2	200000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.085831+07
93	13	81	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.085831+07
94	13	6	1	25000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.085831+07
95	13	86	5	135000.00	0.00	0.00	675000.00	2025-09-28 03:46:21.085831+07
96	13	11	5	12000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.085831+07
97	14	26	4	200000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.091295+07
98	14	52	5	520000.00	0.00	0.00	2600000.00	2025-09-28 03:46:21.091295+07
99	14	34	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.091295+07
100	14	107	4	280000.00	0.00	0.00	1120000.00	2025-09-28 03:46:21.091295+07
101	14	57	5	115000.00	0.00	0.00	575000.00	2025-09-28 03:46:21.091295+07
102	14	55	3	140000.00	0.00	0.00	420000.00	2025-09-28 03:46:21.091295+07
103	14	84	5	400000.00	0.00	0.00	2000000.00	2025-09-28 03:46:21.091295+07
104	14	107	2	280000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.091295+07
105	14	35	5	130000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.091295+07
106	14	36	2	580000.00	0.00	0.00	1160000.00	2025-09-28 03:46:21.091295+07
107	15	10	4	18000.00	0.00	0.00	72000.00	2025-09-28 03:46:21.098676+07
108	15	93	3	190000.00	0.00	0.00	570000.00	2025-09-28 03:46:21.098676+07
109	15	62	5	35000.00	0.00	0.00	175000.00	2025-09-28 03:46:21.098676+07
110	15	57	5	115000.00	0.00	0.00	575000.00	2025-09-28 03:46:21.098676+07
111	15	17	5	550000.00	0.00	0.00	2750000.00	2025-09-28 03:46:21.098676+07
112	15	54	2	160000.00	0.00	0.00	320000.00	2025-09-28 03:46:21.098676+07
113	15	62	4	35000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.098676+07
114	15	17	2	550000.00	0.00	0.00	1100000.00	2025-09-28 03:46:21.098676+07
115	16	20	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.10444+07
116	16	81	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.10444+07
117	17	5	2	3000.00	0.00	0.00	6000.00	2025-09-28 03:46:21.106104+07
118	17	16	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.106104+07
119	17	107	4	280000.00	0.00	0.00	1120000.00	2025-09-28 03:46:21.106104+07
120	17	8	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.106104+07
121	17	31	3	350000.00	0.00	0.00	1050000.00	2025-09-28 03:46:21.106104+07
122	17	18	2	75000.00	0.00	0.00	150000.00	2025-09-28 03:46:21.106104+07
123	17	17	2	550000.00	0.00	0.00	1100000.00	2025-09-28 03:46:21.106104+07
124	17	55	2	140000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.106104+07
125	18	53	4	450000.00	0.00	0.00	1800000.00	2025-09-28 03:46:21.111383+07
126	18	65	4	28000.00	0.00	0.00	112000.00	2025-09-28 03:46:21.111383+07
127	18	18	2	75000.00	0.00	0.00	150000.00	2025-09-28 03:46:21.111383+07
128	18	22	2	130000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.111383+07
129	18	56	2	180000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.111383+07
130	18	82	3	290000.00	0.00	0.00	870000.00	2025-09-28 03:46:21.111383+07
131	18	2	4	12000.00	0.00	0.00	48000.00	2025-09-28 03:46:21.111383+07
132	18	62	1	35000.00	0.00	0.00	35000.00	2025-09-28 03:46:21.111383+07
133	19	27	2	90000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.117511+07
134	19	49	2	750000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.117511+07
135	19	85	4	180000.00	0.00	0.00	720000.00	2025-09-28 03:46:21.117511+07
136	19	85	1	180000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.117511+07
137	19	4	3	8000.00	0.00	0.00	24000.00	2025-09-28 03:46:21.117511+07
138	19	48	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.117511+07
139	19	28	1	140000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.117511+07
140	19	53	5	450000.00	0.00	0.00	2250000.00	2025-09-28 03:46:21.117511+07
141	19	16	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.117511+07
142	19	62	4	35000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.117511+07
143	20	22	5	130000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.12512+07
144	20	91	2	110000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.12512+07
145	20	24	4	45000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.12512+07
146	20	33	3	50000.00	0.00	0.00	150000.00	2025-09-28 03:46:21.12512+07
147	20	6	4	25000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.12512+07
148	21	46	2	650000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.129032+07
149	21	91	2	110000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.129032+07
150	21	61	2	70000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.129032+07
151	22	7	2	65000.00	0.00	0.00	130000.00	2025-09-28 03:46:21.131687+07
152	22	8	4	12000.00	0.00	0.00	48000.00	2025-09-28 03:46:21.131687+07
153	22	79	1	120000.00	0.00	0.00	120000.00	2025-09-28 03:46:21.131687+07
154	22	27	2	90000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.131687+07
155	22	17	2	550000.00	0.00	0.00	1100000.00	2025-09-28 03:46:21.131687+07
156	22	59	5	12000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.131687+07
157	22	51	1	1100000.00	0.00	0.00	1100000.00	2025-09-28 03:46:21.131687+07
158	22	105	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.131687+07
159	22	8	4	12000.00	0.00	0.00	48000.00	2025-09-28 03:46:21.131687+07
160	23	65	1	28000.00	0.00	0.00	28000.00	2025-09-28 03:46:21.138423+07
161	23	93	2	190000.00	0.00	0.00	380000.00	2025-09-28 03:46:21.138423+07
162	23	51	3	1100000.00	0.00	0.00	3300000.00	2025-09-28 03:46:21.138423+07
163	23	81	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.138423+07
164	24	66	3	20000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.141517+07
165	24	20	5	60000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.141517+07
166	24	56	5	180000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.141517+07
167	24	34	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.141517+07
168	25	25	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.145105+07
169	25	68	5	40000.00	0.00	0.00	200000.00	2025-09-28 03:46:21.145105+07
170	25	3	5	3500.00	0.00	0.00	17500.00	2025-09-28 03:46:21.145105+07
171	25	58	2	52000.00	0.00	0.00	104000.00	2025-09-28 03:46:21.145105+07
172	25	81	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.145105+07
173	25	6	3	25000.00	0.00	0.00	75000.00	2025-09-28 03:46:21.145105+07
174	25	83	3	260000.00	0.00	0.00	780000.00	2025-09-28 03:46:21.145105+07
175	25	56	3	180000.00	0.00	0.00	540000.00	2025-09-28 03:46:21.145105+07
176	25	85	5	180000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.145105+07
177	26	31	3	350000.00	0.00	0.00	1050000.00	2025-09-28 03:46:21.151089+07
178	26	35	5	130000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.151089+07
179	26	105	3	150000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.151089+07
180	26	21	4	300000.00	0.00	0.00	1200000.00	2025-09-28 03:46:21.151089+07
181	26	61	4	70000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.151089+07
182	26	61	4	70000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.151089+07
183	26	26	5	200000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.151089+07
184	26	49	1	750000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.151089+07
185	27	53	3	450000.00	0.00	0.00	1350000.00	2025-09-28 03:46:21.157356+07
186	27	82	3	290000.00	0.00	0.00	870000.00	2025-09-28 03:46:21.157356+07
187	27	93	4	190000.00	0.00	0.00	760000.00	2025-09-28 03:46:21.157356+07
188	27	47	4	420000.00	0.00	0.00	1680000.00	2025-09-28 03:46:21.157356+07
189	27	67	5	55000.00	0.00	0.00	275000.00	2025-09-28 03:46:21.157356+07
190	27	29	1	480000.00	0.00	0.00	480000.00	2025-09-28 03:46:21.157356+07
191	27	44	5	20000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.157356+07
192	27	83	2	260000.00	0.00	0.00	520000.00	2025-09-28 03:46:21.157356+07
193	27	1	3	5000.00	0.00	0.00	15000.00	2025-09-28 03:46:21.157356+07
194	27	80	5	260000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.157356+07
195	28	54	4	160000.00	0.00	0.00	640000.00	2025-09-28 03:46:21.163184+07
196	28	92	1	280000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.163184+07
197	28	34	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.163184+07
198	28	38	5	60000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.163184+07
199	28	93	5	190000.00	0.00	0.00	950000.00	2025-09-28 03:46:21.163184+07
200	28	52	2	520000.00	0.00	0.00	1040000.00	2025-09-28 03:46:21.163184+07
201	28	63	5	25000.00	0.00	0.00	125000.00	2025-09-28 03:46:21.163184+07
202	28	18	5	75000.00	0.00	0.00	375000.00	2025-09-28 03:46:21.163184+07
203	28	7	3	65000.00	0.00	0.00	195000.00	2025-09-28 03:46:21.163184+07
204	28	58	3	52000.00	0.00	0.00	156000.00	2025-09-28 03:46:21.163184+07
205	29	48	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.169581+07
206	29	40	1	150000.00	0.00	0.00	150000.00	2025-09-28 03:46:21.169581+07
207	29	93	5	190000.00	0.00	0.00	950000.00	2025-09-28 03:46:21.169581+07
208	29	68	4	40000.00	0.00	0.00	160000.00	2025-09-28 03:46:21.169581+07
209	29	55	4	140000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.169581+07
210	30	79	4	120000.00	0.00	0.00	480000.00	2025-09-28 03:46:21.172789+07
211	30	56	3	180000.00	0.00	0.00	540000.00	2025-09-28 03:46:21.172789+07
212	30	34	4	250000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.172789+07
213	30	91	4	110000.00	0.00	0.00	440000.00	2025-09-28 03:46:21.172789+07
214	30	61	4	70000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.172789+07
215	30	4	2	8000.00	0.00	0.00	16000.00	2025-09-28 03:46:21.172789+07
216	30	56	2	180000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.172789+07
217	30	41	1	75000.00	0.00	0.00	75000.00	2025-09-28 03:46:21.172789+07
218	31	79	2	120000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.178641+07
219	31	24	1	45000.00	0.00	0.00	45000.00	2025-09-28 03:46:21.178641+07
220	31	61	4	70000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.178641+07
221	31	36	1	580000.00	0.00	0.00	580000.00	2025-09-28 03:46:21.178641+07
222	32	27	4	90000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.181721+07
223	33	17	2	550000.00	0.00	0.00	1100000.00	2025-09-28 03:46:21.183125+07
224	33	21	4	300000.00	0.00	0.00	1200000.00	2025-09-28 03:46:21.183125+07
225	33	55	5	140000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.183125+07
226	33	67	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.183125+07
227	33	5	3	3000.00	0.00	0.00	9000.00	2025-09-28 03:46:21.183125+07
228	33	52	1	520000.00	0.00	0.00	520000.00	2025-09-28 03:46:21.183125+07
229	33	7	4	65000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.183125+07
230	34	5	3	3000.00	0.00	0.00	9000.00	2025-09-28 03:46:21.188449+07
231	34	58	1	52000.00	0.00	0.00	52000.00	2025-09-28 03:46:21.188449+07
232	34	91	3	110000.00	0.00	0.00	330000.00	2025-09-28 03:46:21.188449+07
233	34	64	5	25000.00	0.00	0.00	125000.00	2025-09-28 03:46:21.188449+07
234	34	17	3	550000.00	0.00	0.00	1650000.00	2025-09-28 03:46:21.188449+07
235	34	93	4	190000.00	0.00	0.00	760000.00	2025-09-28 03:46:21.188449+07
236	34	51	2	1100000.00	0.00	0.00	2200000.00	2025-09-28 03:46:21.188449+07
237	34	57	1	115000.00	0.00	0.00	115000.00	2025-09-28 03:46:21.188449+07
238	35	67	5	55000.00	0.00	0.00	275000.00	2025-09-28 03:46:21.194251+07
239	35	80	3	260000.00	0.00	0.00	780000.00	2025-09-28 03:46:21.194251+07
240	35	4	1	8000.00	0.00	0.00	8000.00	2025-09-28 03:46:21.194251+07
241	35	85	1	180000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.194251+07
242	35	84	2	400000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.194251+07
243	35	34	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.194251+07
244	35	40	4	150000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.194251+07
245	35	11	3	12000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.194251+07
246	36	14	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.199433+07
247	36	50	5	1950000.00	0.00	0.00	9750000.00	2025-09-28 03:46:21.199433+07
248	36	4	1	8000.00	0.00	0.00	8000.00	2025-09-28 03:46:21.199433+07
249	36	12	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.199433+07
250	36	46	5	650000.00	0.00	0.00	3250000.00	2025-09-28 03:46:21.199433+07
251	36	18	4	75000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.199433+07
252	36	16	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.199433+07
253	36	86	2	135000.00	0.00	0.00	270000.00	2025-09-28 03:46:21.199433+07
254	36	67	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.199433+07
255	36	4	5	8000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.199433+07
256	37	57	2	115000.00	0.00	0.00	230000.00	2025-09-28 03:46:21.205387+07
257	37	50	2	1950000.00	0.00	0.00	3900000.00	2025-09-28 03:46:21.205387+07
258	37	84	4	400000.00	0.00	0.00	1600000.00	2025-09-28 03:46:21.205387+07
259	37	31	2	350000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.205387+07
260	37	51	1	1100000.00	0.00	0.00	1100000.00	2025-09-28 03:46:21.205387+07
261	37	85	1	180000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.205387+07
262	37	29	4	480000.00	0.00	0.00	1920000.00	2025-09-28 03:46:21.205387+07
263	37	6	4	25000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.205387+07
264	38	38	3	60000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.210723+07
265	38	36	1	580000.00	0.00	0.00	580000.00	2025-09-28 03:46:21.210723+07
266	38	20	2	60000.00	0.00	0.00	120000.00	2025-09-28 03:46:21.210723+07
267	38	79	5	120000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.210723+07
268	38	32	5	300000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.210723+07
269	38	22	3	130000.00	0.00	0.00	390000.00	2025-09-28 03:46:21.210723+07
270	38	59	3	12000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.210723+07
271	38	10	1	18000.00	0.00	0.00	18000.00	2025-09-28 03:46:21.210723+07
272	38	40	1	150000.00	0.00	0.00	150000.00	2025-09-28 03:46:21.210723+07
273	39	21	5	300000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.217278+07
274	39	79	3	120000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.217278+07
275	39	32	5	300000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.217278+07
276	40	54	5	160000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.219923+07
277	40	86	4	135000.00	0.00	0.00	540000.00	2025-09-28 03:46:21.219923+07
278	40	59	2	12000.00	0.00	0.00	24000.00	2025-09-28 03:46:21.219923+07
279	41	105	3	150000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.221966+07
280	41	25	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.221966+07
281	41	22	3	130000.00	0.00	0.00	390000.00	2025-09-28 03:46:21.221966+07
282	41	21	4	300000.00	0.00	0.00	1200000.00	2025-09-28 03:46:21.221966+07
283	41	29	1	480000.00	0.00	0.00	480000.00	2025-09-28 03:46:21.221966+07
284	42	40	3	150000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.225953+07
285	42	43	2	30000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.225953+07
286	42	53	4	450000.00	0.00	0.00	1800000.00	2025-09-28 03:46:21.225953+07
287	42	45	1	1300000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.225953+07
288	42	83	3	260000.00	0.00	0.00	780000.00	2025-09-28 03:46:21.225953+07
289	42	25	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.225953+07
290	42	52	3	520000.00	0.00	0.00	1560000.00	2025-09-28 03:46:21.225953+07
291	42	5	3	3000.00	0.00	0.00	9000.00	2025-09-28 03:46:21.225953+07
292	42	41	3	75000.00	0.00	0.00	225000.00	2025-09-28 03:46:21.225953+07
293	42	31	4	350000.00	0.00	0.00	1400000.00	2025-09-28 03:46:21.225953+07
294	43	49	4	750000.00	0.00	0.00	3000000.00	2025-09-28 03:46:21.23318+07
295	43	31	4	350000.00	0.00	0.00	1400000.00	2025-09-28 03:46:21.23318+07
296	43	27	5	90000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.23318+07
297	43	59	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.23318+07
298	43	85	1	180000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.23318+07
299	43	4	4	8000.00	0.00	0.00	32000.00	2025-09-28 03:46:21.23318+07
300	44	24	3	45000.00	0.00	0.00	135000.00	2025-09-28 03:46:21.237757+07
301	44	26	3	200000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.237757+07
302	45	17	5	550000.00	0.00	0.00	2750000.00	2025-09-28 03:46:21.239754+07
303	45	55	2	140000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.239754+07
304	46	46	2	650000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.241027+07
305	47	63	1	25000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.242385+07
306	47	22	2	130000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.242385+07
307	47	32	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.242385+07
308	47	16	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.242385+07
309	47	79	5	120000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.242385+07
310	47	14	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.242385+07
311	48	1	4	5000.00	0.00	0.00	20000.00	2025-09-28 03:46:21.247261+07
312	48	26	3	200000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.247261+07
313	48	36	3	580000.00	0.00	0.00	1740000.00	2025-09-28 03:46:21.247261+07
314	49	57	4	115000.00	0.00	0.00	460000.00	2025-09-28 03:46:21.249812+07
315	49	79	3	120000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.249812+07
316	49	41	4	75000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.249812+07
317	49	54	4	160000.00	0.00	0.00	640000.00	2025-09-28 03:46:21.249812+07
318	49	31	3	350000.00	0.00	0.00	1050000.00	2025-09-28 03:46:21.249812+07
319	50	53	2	450000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.25321+07
320	50	107	2	280000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.25321+07
321	50	51	4	1100000.00	0.00	0.00	4400000.00	2025-09-28 03:46:21.25321+07
322	50	59	3	12000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.25321+07
323	50	47	5	420000.00	0.00	0.00	2100000.00	2025-09-28 03:46:21.25321+07
324	51	80	4	260000.00	0.00	0.00	1040000.00	2025-09-28 03:46:21.256039+07
325	52	9	2	5000.00	0.00	0.00	10000.00	2025-09-28 03:46:21.257185+07
326	52	67	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.257185+07
327	52	9	1	5000.00	0.00	0.00	5000.00	2025-09-28 03:46:21.257185+07
328	52	81	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.257185+07
329	52	16	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.257185+07
330	53	15	3	450000.00	0.00	0.00	1350000.00	2025-09-28 03:46:21.261298+07
331	53	9	5	5000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.261298+07
332	53	45	1	1300000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.261298+07
333	53	49	1	750000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.261298+07
334	53	31	2	350000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.261298+07
335	53	32	5	300000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.261298+07
336	54	56	1	180000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.265824+07
337	54	22	2	130000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.265824+07
338	54	50	4	1950000.00	0.00	0.00	7800000.00	2025-09-28 03:46:21.265824+07
339	55	29	2	480000.00	0.00	0.00	960000.00	2025-09-28 03:46:21.268674+07
340	55	36	5	580000.00	0.00	0.00	2900000.00	2025-09-28 03:46:21.268674+07
341	55	42	2	55000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.268674+07
342	55	12	5	55000.00	0.00	0.00	275000.00	2025-09-28 03:46:21.268674+07
343	55	68	5	40000.00	0.00	0.00	200000.00	2025-09-28 03:46:21.268674+07
344	55	55	5	140000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.268674+07
345	55	34	4	250000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.268674+07
346	55	20	3	60000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.268674+07
347	56	34	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.27374+07
348	56	79	3	120000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.27374+07
349	56	56	4	180000.00	0.00	0.00	720000.00	2025-09-28 03:46:21.27374+07
350	56	41	2	75000.00	0.00	0.00	150000.00	2025-09-28 03:46:21.27374+07
351	56	20	1	60000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.27374+07
352	56	65	2	28000.00	0.00	0.00	56000.00	2025-09-28 03:46:21.27374+07
353	56	52	3	520000.00	0.00	0.00	1560000.00	2025-09-28 03:46:21.27374+07
354	57	5	4	3000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.277554+07
355	57	50	4	1950000.00	0.00	0.00	7800000.00	2025-09-28 03:46:21.277554+07
356	57	105	3	150000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.277554+07
357	57	61	1	70000.00	0.00	0.00	70000.00	2025-09-28 03:46:21.277554+07
358	57	19	2	200000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.277554+07
359	57	106	5	80000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.277554+07
360	57	58	1	52000.00	0.00	0.00	52000.00	2025-09-28 03:46:21.277554+07
361	57	16	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.277554+07
362	57	58	2	52000.00	0.00	0.00	104000.00	2025-09-28 03:46:21.277554+07
363	57	92	2	280000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.277554+07
364	58	92	4	280000.00	0.00	0.00	1120000.00	2025-09-28 03:46:21.282713+07
365	58	64	2	25000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.282713+07
366	58	23	3	110000.00	0.00	0.00	330000.00	2025-09-28 03:46:21.282713+07
367	58	54	1	160000.00	0.00	0.00	160000.00	2025-09-28 03:46:21.282713+07
368	59	12	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.285751+07
369	59	17	2	550000.00	0.00	0.00	1100000.00	2025-09-28 03:46:21.285751+07
370	59	61	3	70000.00	0.00	0.00	210000.00	2025-09-28 03:46:21.285751+07
371	60	14	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.288029+07
372	60	32	2	300000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.288029+07
373	60	16	4	250000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.288029+07
374	60	3	5	3500.00	0.00	0.00	17500.00	2025-09-28 03:46:21.288029+07
375	60	12	1	55000.00	0.00	0.00	55000.00	2025-09-28 03:46:21.288029+07
376	60	33	1	50000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.288029+07
377	61	19	2	200000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.292571+07
378	61	83	5	260000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.292571+07
379	61	67	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.292571+07
380	61	15	3	450000.00	0.00	0.00	1350000.00	2025-09-28 03:46:21.292571+07
381	61	64	3	25000.00	0.00	0.00	75000.00	2025-09-28 03:46:21.292571+07
382	62	15	1	450000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.296407+07
383	62	91	1	110000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.296407+07
384	62	79	3	120000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.296407+07
385	62	1	5	5000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.296407+07
386	62	34	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.296407+07
387	62	1	4	5000.00	0.00	0.00	20000.00	2025-09-28 03:46:21.296407+07
388	63	31	3	350000.00	0.00	0.00	1050000.00	2025-09-28 03:46:21.301443+07
389	63	7	1	65000.00	0.00	0.00	65000.00	2025-09-28 03:46:21.301443+07
390	63	32	3	300000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.301443+07
391	63	22	2	130000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.301443+07
392	63	93	4	190000.00	0.00	0.00	760000.00	2025-09-28 03:46:21.301443+07
393	63	46	1	650000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.301443+07
394	63	83	5	260000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.301443+07
395	64	14	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.307185+07
396	64	4	4	8000.00	0.00	0.00	32000.00	2025-09-28 03:46:21.307185+07
397	65	5	1	3000.00	0.00	0.00	3000.00	2025-09-28 03:46:21.311695+07
398	65	32	2	300000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.311695+07
399	65	58	1	52000.00	0.00	0.00	52000.00	2025-09-28 03:46:21.311695+07
400	65	45	2	1300000.00	0.00	0.00	2600000.00	2025-09-28 03:46:21.311695+07
401	65	31	3	350000.00	0.00	0.00	1050000.00	2025-09-28 03:46:21.311695+07
402	65	61	1	70000.00	0.00	0.00	70000.00	2025-09-28 03:46:21.311695+07
403	65	34	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.311695+07
404	65	3	4	3500.00	0.00	0.00	14000.00	2025-09-28 03:46:21.311695+07
405	65	15	4	450000.00	0.00	0.00	1800000.00	2025-09-28 03:46:21.311695+07
406	65	68	1	40000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.311695+07
407	66	11	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.318174+07
408	66	84	1	400000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.318174+07
409	66	10	4	18000.00	0.00	0.00	72000.00	2025-09-28 03:46:21.318174+07
410	66	47	5	420000.00	0.00	0.00	2100000.00	2025-09-28 03:46:21.318174+07
411	66	86	5	135000.00	0.00	0.00	675000.00	2025-09-28 03:46:21.318174+07
412	67	3	4	3500.00	0.00	0.00	14000.00	2025-09-28 03:46:21.322378+07
413	67	67	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.322378+07
414	67	28	2	140000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.322378+07
415	67	34	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.322378+07
416	67	45	1	1300000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.322378+07
417	67	20	3	60000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.322378+07
418	68	61	4	70000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.328074+07
419	68	67	1	55000.00	0.00	0.00	55000.00	2025-09-28 03:46:21.328074+07
420	68	93	2	190000.00	0.00	0.00	380000.00	2025-09-28 03:46:21.328074+07
421	68	59	4	12000.00	0.00	0.00	48000.00	2025-09-28 03:46:21.328074+07
422	68	8	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.328074+07
423	68	85	1	180000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.328074+07
424	68	57	4	115000.00	0.00	0.00	460000.00	2025-09-28 03:46:21.328074+07
425	68	92	1	280000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.328074+07
426	68	105	1	150000.00	0.00	0.00	150000.00	2025-09-28 03:46:21.328074+07
427	69	20	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.33486+07
428	69	81	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.33486+07
429	69	46	2	650000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.33486+07
430	69	55	4	140000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.33486+07
431	69	3	4	3500.00	0.00	0.00	14000.00	2025-09-28 03:46:21.33486+07
432	69	29	3	480000.00	0.00	0.00	1440000.00	2025-09-28 03:46:21.33486+07
433	69	62	4	35000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.33486+07
434	69	56	4	180000.00	0.00	0.00	720000.00	2025-09-28 03:46:21.33486+07
435	69	19	2	200000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.33486+07
436	69	5	5	3000.00	0.00	0.00	15000.00	2025-09-28 03:46:21.33486+07
437	70	52	4	520000.00	0.00	0.00	2080000.00	2025-09-28 03:46:21.34231+07
438	70	50	2	1950000.00	0.00	0.00	3900000.00	2025-09-28 03:46:21.34231+07
439	70	1	1	5000.00	0.00	0.00	5000.00	2025-09-28 03:46:21.34231+07
440	71	68	4	40000.00	0.00	0.00	160000.00	2025-09-28 03:46:21.344576+07
441	71	23	1	110000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.344576+07
442	71	11	3	12000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.344576+07
443	71	36	4	580000.00	0.00	0.00	2320000.00	2025-09-28 03:46:21.344576+07
444	71	12	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.344576+07
445	71	16	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.344576+07
446	71	36	1	580000.00	0.00	0.00	580000.00	2025-09-28 03:46:21.344576+07
447	71	85	4	180000.00	0.00	0.00	720000.00	2025-09-28 03:46:21.344576+07
448	72	15	2	450000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.351255+07
449	72	54	3	160000.00	0.00	0.00	480000.00	2025-09-28 03:46:21.351255+07
450	72	31	1	350000.00	0.00	0.00	350000.00	2025-09-28 03:46:21.351255+07
451	72	48	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.351255+07
452	72	10	3	18000.00	0.00	0.00	54000.00	2025-09-28 03:46:21.351255+07
453	72	48	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.351255+07
454	72	106	4	80000.00	0.00	0.00	320000.00	2025-09-28 03:46:21.351255+07
455	73	25	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.356226+07
456	73	17	5	550000.00	0.00	0.00	2750000.00	2025-09-28 03:46:21.356226+07
457	73	28	5	140000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.356226+07
458	73	93	3	190000.00	0.00	0.00	570000.00	2025-09-28 03:46:21.356226+07
459	73	58	4	52000.00	0.00	0.00	208000.00	2025-09-28 03:46:21.356226+07
460	73	66	1	20000.00	0.00	0.00	20000.00	2025-09-28 03:46:21.356226+07
461	73	65	3	28000.00	0.00	0.00	84000.00	2025-09-28 03:46:21.356226+07
462	73	34	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.356226+07
463	73	19	5	200000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.356226+07
464	73	41	5	75000.00	0.00	0.00	375000.00	2025-09-28 03:46:21.356226+07
465	74	63	5	25000.00	0.00	0.00	125000.00	2025-09-28 03:46:21.362519+07
466	74	45	4	1300000.00	0.00	0.00	5200000.00	2025-09-28 03:46:21.362519+07
467	75	8	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.364762+07
468	75	86	5	135000.00	0.00	0.00	675000.00	2025-09-28 03:46:21.364762+07
469	75	59	2	12000.00	0.00	0.00	24000.00	2025-09-28 03:46:21.364762+07
470	76	65	2	28000.00	0.00	0.00	56000.00	2025-09-28 03:46:21.367257+07
471	76	34	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.367257+07
472	76	27	4	90000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.367257+07
473	76	106	2	80000.00	0.00	0.00	160000.00	2025-09-28 03:46:21.367257+07
474	76	61	2	70000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.367257+07
475	76	107	1	280000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.367257+07
476	77	34	4	250000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.371917+07
477	77	32	2	300000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.371917+07
478	78	8	3	12000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.37392+07
479	78	20	5	60000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.37392+07
480	78	46	2	650000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.37392+07
481	78	23	1	110000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.37392+07
482	78	54	1	160000.00	0.00	0.00	160000.00	2025-09-28 03:46:21.37392+07
483	78	28	5	140000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.37392+07
484	78	63	4	25000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.37392+07
485	78	20	1	60000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.37392+07
486	78	54	3	160000.00	0.00	0.00	480000.00	2025-09-28 03:46:21.37392+07
487	78	41	1	75000.00	0.00	0.00	75000.00	2025-09-28 03:46:21.37392+07
488	79	38	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.3807+07
489	79	25	5	150000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.3807+07
490	79	61	2	70000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.3807+07
491	79	17	5	550000.00	0.00	0.00	2750000.00	2025-09-28 03:46:21.3807+07
492	79	81	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.3807+07
493	80	25	5	150000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.384919+07
494	80	55	3	140000.00	0.00	0.00	420000.00	2025-09-28 03:46:21.384919+07
495	80	80	5	260000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.384919+07
496	80	66	1	20000.00	0.00	0.00	20000.00	2025-09-28 03:46:21.384919+07
497	80	14	4	250000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.384919+07
498	80	84	2	400000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.384919+07
499	80	4	4	8000.00	0.00	0.00	32000.00	2025-09-28 03:46:21.384919+07
500	81	53	1	450000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.390265+07
501	81	83	4	260000.00	0.00	0.00	1040000.00	2025-09-28 03:46:21.390265+07
502	81	6	1	25000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.390265+07
503	81	50	3	1950000.00	0.00	0.00	5850000.00	2025-09-28 03:46:21.390265+07
504	81	105	4	150000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.390265+07
505	81	55	2	140000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.390265+07
506	81	53	2	450000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.390265+07
507	81	42	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.390265+07
508	82	21	4	300000.00	0.00	0.00	1200000.00	2025-09-28 03:46:21.396471+07
509	82	64	5	25000.00	0.00	0.00	125000.00	2025-09-28 03:46:21.396471+07
510	82	57	4	115000.00	0.00	0.00	460000.00	2025-09-28 03:46:21.396471+07
511	82	59	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.396471+07
512	82	22	4	130000.00	0.00	0.00	520000.00	2025-09-28 03:46:21.396471+07
513	82	2	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.396471+07
514	82	91	3	110000.00	0.00	0.00	330000.00	2025-09-28 03:46:21.396471+07
515	82	34	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.396471+07
516	82	18	5	75000.00	0.00	0.00	375000.00	2025-09-28 03:46:21.396471+07
517	82	92	4	280000.00	0.00	0.00	1120000.00	2025-09-28 03:46:21.396471+07
518	83	10	5	18000.00	0.00	0.00	90000.00	2025-09-28 03:46:21.404045+07
519	83	31	3	350000.00	0.00	0.00	1050000.00	2025-09-28 03:46:21.404045+07
520	83	85	4	180000.00	0.00	0.00	720000.00	2025-09-28 03:46:21.404045+07
521	83	35	4	130000.00	0.00	0.00	520000.00	2025-09-28 03:46:21.404045+07
522	84	66	3	20000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.407604+07
523	84	68	1	40000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.407604+07
524	85	26	1	200000.00	0.00	0.00	200000.00	2025-09-28 03:46:21.409594+07
525	85	67	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.409594+07
526	85	27	2	90000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.409594+07
527	85	35	3	130000.00	0.00	0.00	390000.00	2025-09-28 03:46:21.409594+07
528	85	80	5	260000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.409594+07
529	85	51	2	1100000.00	0.00	0.00	2200000.00	2025-09-28 03:46:21.409594+07
530	85	12	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.409594+07
531	85	82	1	290000.00	0.00	0.00	290000.00	2025-09-28 03:46:21.409594+07
532	85	5	4	3000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.409594+07
533	85	5	2	3000.00	0.00	0.00	6000.00	2025-09-28 03:46:21.409594+07
534	86	8	5	12000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.417141+07
535	86	106	2	80000.00	0.00	0.00	160000.00	2025-09-28 03:46:21.417141+07
536	86	2	2	12000.00	0.00	0.00	24000.00	2025-09-28 03:46:21.417141+07
537	86	9	4	5000.00	0.00	0.00	20000.00	2025-09-28 03:46:21.417141+07
538	86	1	3	5000.00	0.00	0.00	15000.00	2025-09-28 03:46:21.417141+07
539	86	40	1	150000.00	0.00	0.00	150000.00	2025-09-28 03:46:21.417141+07
540	86	17	1	550000.00	0.00	0.00	550000.00	2025-09-28 03:46:21.417141+07
541	86	67	2	55000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.417141+07
542	86	64	3	25000.00	0.00	0.00	75000.00	2025-09-28 03:46:21.417141+07
543	86	7	5	65000.00	0.00	0.00	325000.00	2025-09-28 03:46:21.417141+07
544	87	92	4	280000.00	0.00	0.00	1120000.00	2025-09-28 03:46:21.424412+07
545	87	64	1	25000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.424412+07
546	88	92	2	280000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.426398+07
547	88	15	4	450000.00	0.00	0.00	1800000.00	2025-09-28 03:46:21.426398+07
548	88	42	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.426398+07
549	88	85	3	180000.00	0.00	0.00	540000.00	2025-09-28 03:46:21.426398+07
550	88	20	1	60000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.426398+07
551	88	9	1	5000.00	0.00	0.00	5000.00	2025-09-28 03:46:21.426398+07
552	88	86	3	135000.00	0.00	0.00	405000.00	2025-09-28 03:46:21.426398+07
553	88	40	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.426398+07
554	88	40	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.426398+07
555	88	66	5	20000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.426398+07
556	89	3	1	3500.00	0.00	0.00	3500.00	2025-09-28 03:46:21.433772+07
557	89	32	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.433772+07
558	89	80	1	260000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.433772+07
559	90	106	5	80000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.436151+07
560	91	4	5	8000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.437473+07
561	91	20	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.437473+07
562	91	45	1	1300000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.437473+07
563	91	64	2	25000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.437473+07
564	91	1	5	5000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.437473+07
565	91	91	3	110000.00	0.00	0.00	330000.00	2025-09-28 03:46:21.437473+07
566	91	85	2	180000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.437473+07
567	91	20	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.437473+07
568	91	17	2	550000.00	0.00	0.00	1100000.00	2025-09-28 03:46:21.437473+07
569	91	36	2	580000.00	0.00	0.00	1160000.00	2025-09-28 03:46:21.437473+07
570	92	43	3	30000.00	0.00	0.00	90000.00	2025-09-28 03:46:21.443249+07
571	92	106	1	80000.00	0.00	0.00	80000.00	2025-09-28 03:46:21.443249+07
572	92	28	1	140000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.443249+07
573	93	105	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.44551+07
574	94	53	5	450000.00	0.00	0.00	2250000.00	2025-09-28 03:46:21.446401+07
575	94	80	3	260000.00	0.00	0.00	780000.00	2025-09-28 03:46:21.446401+07
576	94	26	4	200000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.446401+07
577	94	5	3	3000.00	0.00	0.00	9000.00	2025-09-28 03:46:21.446401+07
578	94	66	5	20000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.446401+07
579	94	79	4	120000.00	0.00	0.00	480000.00	2025-09-28 03:46:21.446401+07
580	94	79	4	120000.00	0.00	0.00	480000.00	2025-09-28 03:46:21.446401+07
581	94	46	3	650000.00	0.00	0.00	1950000.00	2025-09-28 03:46:21.446401+07
582	94	12	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.446401+07
583	94	35	5	130000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.446401+07
584	95	59	4	12000.00	0.00	0.00	48000.00	2025-09-28 03:46:21.454072+07
585	95	19	3	200000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.454072+07
586	95	10	5	18000.00	0.00	0.00	90000.00	2025-09-28 03:46:21.454072+07
587	96	16	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.456491+07
588	96	92	2	280000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.456491+07
589	97	83	5	260000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.458508+07
590	97	46	2	650000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.458508+07
591	97	36	3	580000.00	0.00	0.00	1740000.00	2025-09-28 03:46:21.458508+07
592	98	12	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.461463+07
593	98	17	5	550000.00	0.00	0.00	2750000.00	2025-09-28 03:46:21.461463+07
594	98	48	2	300000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.461463+07
595	98	35	5	130000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.461463+07
596	98	16	4	250000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.461463+07
597	98	21	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.461463+07
598	98	49	3	750000.00	0.00	0.00	2250000.00	2025-09-28 03:46:21.461463+07
599	99	51	3	1100000.00	0.00	0.00	3300000.00	2025-09-28 03:46:21.467263+07
600	99	26	2	200000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.467263+07
601	99	14	4	250000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.467263+07
602	99	27	3	90000.00	0.00	0.00	270000.00	2025-09-28 03:46:21.467263+07
603	99	82	1	290000.00	0.00	0.00	290000.00	2025-09-28 03:46:21.467263+07
604	99	5	5	3000.00	0.00	0.00	15000.00	2025-09-28 03:46:21.467263+07
605	100	29	5	480000.00	0.00	0.00	2400000.00	2025-09-28 03:46:21.472497+07
606	101	14	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.473653+07
607	101	38	2	60000.00	0.00	0.00	120000.00	2025-09-28 03:46:21.473653+07
608	101	31	4	350000.00	0.00	0.00	1400000.00	2025-09-28 03:46:21.473653+07
609	101	92	5	280000.00	0.00	0.00	1400000.00	2025-09-28 03:46:21.473653+07
610	101	91	5	110000.00	0.00	0.00	550000.00	2025-09-28 03:46:21.473653+07
611	101	11	4	12000.00	0.00	0.00	48000.00	2025-09-28 03:46:21.473653+07
612	101	48	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.473653+07
613	101	85	2	180000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.473653+07
614	102	18	3	75000.00	0.00	0.00	225000.00	2025-09-28 03:46:21.479868+07
615	102	35	5	130000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.479868+07
616	102	8	4	12000.00	0.00	0.00	48000.00	2025-09-28 03:46:21.479868+07
617	102	6	3	25000.00	0.00	0.00	75000.00	2025-09-28 03:46:21.479868+07
618	102	36	3	580000.00	0.00	0.00	1740000.00	2025-09-28 03:46:21.479868+07
619	102	27	1	90000.00	0.00	0.00	90000.00	2025-09-28 03:46:21.479868+07
620	103	106	2	80000.00	0.00	0.00	160000.00	2025-09-28 03:46:21.484577+07
621	103	10	5	18000.00	0.00	0.00	90000.00	2025-09-28 03:46:21.484577+07
622	103	59	4	12000.00	0.00	0.00	48000.00	2025-09-28 03:46:21.484577+07
623	103	35	5	130000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.484577+07
624	103	84	4	400000.00	0.00	0.00	1600000.00	2025-09-28 03:46:21.484577+07
625	103	86	3	135000.00	0.00	0.00	405000.00	2025-09-28 03:46:21.484577+07
626	103	10	4	18000.00	0.00	0.00	72000.00	2025-09-28 03:46:21.484577+07
627	103	93	4	190000.00	0.00	0.00	760000.00	2025-09-28 03:46:21.484577+07
628	103	12	2	55000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.484577+07
629	104	33	2	50000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.491522+07
630	104	65	2	28000.00	0.00	0.00	56000.00	2025-09-28 03:46:21.491522+07
631	104	17	2	550000.00	0.00	0.00	1100000.00	2025-09-28 03:46:21.491522+07
632	104	68	2	40000.00	0.00	0.00	80000.00	2025-09-28 03:46:21.491522+07
633	104	67	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.491522+07
634	104	52	2	520000.00	0.00	0.00	1040000.00	2025-09-28 03:46:21.491522+07
635	104	33	4	50000.00	0.00	0.00	200000.00	2025-09-28 03:46:21.491522+07
636	104	106	2	80000.00	0.00	0.00	160000.00	2025-09-28 03:46:21.491522+07
637	104	17	3	550000.00	0.00	0.00	1650000.00	2025-09-28 03:46:21.491522+07
638	105	38	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.4982+07
639	105	12	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.4982+07
640	105	84	2	400000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.4982+07
641	105	57	4	115000.00	0.00	0.00	460000.00	2025-09-28 03:46:21.4982+07
642	105	63	1	25000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.4982+07
643	105	31	4	350000.00	0.00	0.00	1400000.00	2025-09-28 03:46:21.4982+07
644	106	81	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.502024+07
645	107	93	5	190000.00	0.00	0.00	950000.00	2025-09-28 03:46:21.503402+07
646	107	82	5	290000.00	0.00	0.00	1450000.00	2025-09-28 03:46:21.503402+07
647	107	26	2	200000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.503402+07
648	107	5	3	3000.00	0.00	0.00	9000.00	2025-09-28 03:46:21.503402+07
649	107	44	2	20000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.503402+07
650	107	19	3	200000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.503402+07
651	107	28	2	140000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.503402+07
652	107	49	3	750000.00	0.00	0.00	2250000.00	2025-09-28 03:46:21.503402+07
653	107	67	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.503402+07
654	107	38	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.503402+07
655	108	35	1	130000.00	0.00	0.00	130000.00	2025-09-28 03:46:21.51221+07
656	108	82	3	290000.00	0.00	0.00	870000.00	2025-09-28 03:46:21.51221+07
657	108	57	3	115000.00	0.00	0.00	345000.00	2025-09-28 03:46:21.51221+07
658	108	85	3	180000.00	0.00	0.00	540000.00	2025-09-28 03:46:21.51221+07
659	108	6	2	25000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.51221+07
660	109	66	5	20000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.516568+07
661	109	7	1	65000.00	0.00	0.00	65000.00	2025-09-28 03:46:21.516568+07
662	109	105	1	150000.00	0.00	0.00	150000.00	2025-09-28 03:46:21.516568+07
663	109	48	3	300000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.516568+07
664	110	49	1	750000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.519495+07
665	110	81	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.519495+07
666	111	58	5	52000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.521713+07
667	111	4	5	8000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.521713+07
668	111	105	1	150000.00	0.00	0.00	150000.00	2025-09-28 03:46:21.521713+07
669	111	16	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.521713+07
670	111	43	2	30000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.521713+07
671	111	59	3	12000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.521713+07
672	111	28	1	140000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.521713+07
673	112	14	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.527602+07
674	112	61	3	70000.00	0.00	0.00	210000.00	2025-09-28 03:46:21.527602+07
675	112	58	5	52000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.527602+07
676	113	32	3	300000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.530831+07
677	113	22	5	130000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.530831+07
678	113	91	3	110000.00	0.00	0.00	330000.00	2025-09-28 03:46:21.530831+07
679	114	68	1	40000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.533614+07
680	114	10	2	18000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.533614+07
681	114	64	4	25000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.533614+07
682	114	58	4	52000.00	0.00	0.00	208000.00	2025-09-28 03:46:21.533614+07
683	114	80	3	260000.00	0.00	0.00	780000.00	2025-09-28 03:46:21.533614+07
684	114	67	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.533614+07
685	114	4	3	8000.00	0.00	0.00	24000.00	2025-09-28 03:46:21.533614+07
686	114	14	4	250000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.533614+07
687	115	81	4	250000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.540112+07
688	115	57	5	115000.00	0.00	0.00	575000.00	2025-09-28 03:46:21.540112+07
689	115	9	3	5000.00	0.00	0.00	15000.00	2025-09-28 03:46:21.540112+07
690	115	82	4	290000.00	0.00	0.00	1160000.00	2025-09-28 03:46:21.540112+07
691	115	105	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.540112+07
692	115	15	1	450000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.540112+07
693	115	86	2	135000.00	0.00	0.00	270000.00	2025-09-28 03:46:21.540112+07
694	116	11	5	12000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.546069+07
695	117	34	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.547491+07
696	117	65	2	28000.00	0.00	0.00	56000.00	2025-09-28 03:46:21.547491+07
697	117	43	2	30000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.547491+07
698	117	44	3	20000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.547491+07
699	117	46	5	650000.00	0.00	0.00	3250000.00	2025-09-28 03:46:21.547491+07
700	117	82	2	290000.00	0.00	0.00	580000.00	2025-09-28 03:46:21.547491+07
701	117	80	2	260000.00	0.00	0.00	520000.00	2025-09-28 03:46:21.547491+07
702	117	51	5	1100000.00	0.00	0.00	5500000.00	2025-09-28 03:46:21.547491+07
703	118	23	1	110000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.554026+07
704	118	28	1	140000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.554026+07
705	118	6	2	25000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.554026+07
706	118	46	3	650000.00	0.00	0.00	1950000.00	2025-09-28 03:46:21.554026+07
707	118	19	4	200000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.554026+07
708	118	83	1	260000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.554026+07
709	118	40	5	150000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.554026+07
710	118	3	2	3500.00	0.00	0.00	7000.00	2025-09-28 03:46:21.554026+07
711	119	63	3	25000.00	0.00	0.00	75000.00	2025-09-28 03:46:21.559396+07
712	119	36	3	580000.00	0.00	0.00	1740000.00	2025-09-28 03:46:21.559396+07
713	119	83	4	260000.00	0.00	0.00	1040000.00	2025-09-28 03:46:21.559396+07
714	119	81	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.559396+07
715	119	81	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.559396+07
716	120	42	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.563635+07
717	120	56	1	180000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.563635+07
718	120	42	1	55000.00	0.00	0.00	55000.00	2025-09-28 03:46:21.563635+07
719	120	17	1	550000.00	0.00	0.00	550000.00	2025-09-28 03:46:21.563635+07
720	120	8	3	12000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.563635+07
721	121	105	3	150000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.568572+07
722	121	79	3	120000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.568572+07
723	121	62	3	35000.00	0.00	0.00	105000.00	2025-09-28 03:46:21.568572+07
724	121	12	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.568572+07
725	122	82	5	290000.00	0.00	0.00	1450000.00	2025-09-28 03:46:21.572215+07
726	122	42	2	55000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.572215+07
727	123	6	1	25000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.573766+07
728	123	3	5	3500.00	0.00	0.00	17500.00	2025-09-28 03:46:21.573766+07
729	123	56	1	180000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.573766+07
730	123	64	1	25000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.573766+07
731	123	5	5	3000.00	0.00	0.00	15000.00	2025-09-28 03:46:21.573766+07
732	123	19	3	200000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.573766+07
733	123	40	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.573766+07
734	123	16	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.573766+07
735	123	6	1	25000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.573766+07
736	123	91	3	110000.00	0.00	0.00	330000.00	2025-09-28 03:46:21.573766+07
737	124	19	1	200000.00	0.00	0.00	200000.00	2025-09-28 03:46:21.580659+07
738	124	25	3	150000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.580659+07
739	124	67	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.580659+07
740	124	11	2	12000.00	0.00	0.00	24000.00	2025-09-28 03:46:21.580659+07
741	124	44	2	20000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.580659+07
742	124	54	1	160000.00	0.00	0.00	160000.00	2025-09-28 03:46:21.580659+07
743	124	92	5	280000.00	0.00	0.00	1400000.00	2025-09-28 03:46:21.580659+07
744	124	27	5	90000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.580659+07
745	124	22	5	130000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.580659+07
746	124	20	3	60000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.580659+07
747	125	47	4	420000.00	0.00	0.00	1680000.00	2025-09-28 03:46:21.587811+07
748	125	106	5	80000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.587811+07
749	125	26	3	200000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.587811+07
750	125	62	2	35000.00	0.00	0.00	70000.00	2025-09-28 03:46:21.587811+07
751	125	28	5	140000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.587811+07
752	125	2	3	12000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.587811+07
753	125	32	2	300000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.587811+07
754	125	4	1	8000.00	0.00	0.00	8000.00	2025-09-28 03:46:21.587811+07
755	125	86	2	135000.00	0.00	0.00	270000.00	2025-09-28 03:46:21.587811+07
756	126	36	2	580000.00	0.00	0.00	1160000.00	2025-09-28 03:46:21.59433+07
757	126	42	2	55000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.59433+07
758	126	91	4	110000.00	0.00	0.00	440000.00	2025-09-28 03:46:21.59433+07
759	126	44	3	20000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.59433+07
760	126	85	4	180000.00	0.00	0.00	720000.00	2025-09-28 03:46:21.59433+07
761	126	34	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.59433+07
762	126	2	4	12000.00	0.00	0.00	48000.00	2025-09-28 03:46:21.59433+07
763	126	45	3	1300000.00	0.00	0.00	3900000.00	2025-09-28 03:46:21.59433+07
764	126	57	1	115000.00	0.00	0.00	115000.00	2025-09-28 03:46:21.59433+07
765	126	34	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.59433+07
766	127	36	4	580000.00	0.00	0.00	2320000.00	2025-09-28 03:46:21.602128+07
767	127	52	4	520000.00	0.00	0.00	2080000.00	2025-09-28 03:46:21.602128+07
768	127	93	2	190000.00	0.00	0.00	380000.00	2025-09-28 03:46:21.602128+07
769	127	82	3	290000.00	0.00	0.00	870000.00	2025-09-28 03:46:21.602128+07
770	127	10	4	18000.00	0.00	0.00	72000.00	2025-09-28 03:46:21.602128+07
771	127	56	1	180000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.602128+07
772	127	66	2	20000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.602128+07
773	128	2	2	12000.00	0.00	0.00	24000.00	2025-09-28 03:46:21.608389+07
774	128	106	3	80000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.608389+07
775	128	66	1	20000.00	0.00	0.00	20000.00	2025-09-28 03:46:21.608389+07
776	128	35	3	130000.00	0.00	0.00	390000.00	2025-09-28 03:46:21.608389+07
777	128	62	4	35000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.608389+07
778	128	36	5	580000.00	0.00	0.00	2900000.00	2025-09-28 03:46:21.608389+07
779	128	23	5	110000.00	0.00	0.00	550000.00	2025-09-28 03:46:21.608389+07
780	128	107	1	280000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.608389+07
781	129	48	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.613698+07
782	129	14	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.613698+07
783	129	38	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.613698+07
784	129	40	1	150000.00	0.00	0.00	150000.00	2025-09-28 03:46:21.613698+07
785	129	27	3	90000.00	0.00	0.00	270000.00	2025-09-28 03:46:21.613698+07
786	129	46	5	650000.00	0.00	0.00	3250000.00	2025-09-28 03:46:21.613698+07
787	129	57	2	115000.00	0.00	0.00	230000.00	2025-09-28 03:46:21.613698+07
788	129	105	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.613698+07
789	129	24	2	45000.00	0.00	0.00	90000.00	2025-09-28 03:46:21.613698+07
790	130	42	5	55000.00	0.00	0.00	275000.00	2025-09-28 03:46:21.620792+07
791	130	82	4	290000.00	0.00	0.00	1160000.00	2025-09-28 03:46:21.620792+07
792	130	34	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.620792+07
793	130	34	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.620792+07
794	130	31	2	350000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.620792+07
795	130	42	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.620792+07
796	131	57	3	115000.00	0.00	0.00	345000.00	2025-09-28 03:46:21.626479+07
797	131	50	3	1950000.00	0.00	0.00	5850000.00	2025-09-28 03:46:21.626479+07
798	131	52	2	520000.00	0.00	0.00	1040000.00	2025-09-28 03:46:21.626479+07
799	131	50	2	1950000.00	0.00	0.00	3900000.00	2025-09-28 03:46:21.626479+07
800	131	105	2	150000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.626479+07
801	132	25	4	150000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.631092+07
802	132	83	5	260000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.631092+07
803	132	55	4	140000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.631092+07
804	132	17	3	550000.00	0.00	0.00	1650000.00	2025-09-28 03:46:21.631092+07
805	133	61	2	70000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.634102+07
806	133	52	4	520000.00	0.00	0.00	2080000.00	2025-09-28 03:46:21.634102+07
807	133	29	4	480000.00	0.00	0.00	1920000.00	2025-09-28 03:46:21.634102+07
808	133	38	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.634102+07
809	133	15	1	450000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.634102+07
810	133	27	2	90000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.634102+07
811	134	83	4	260000.00	0.00	0.00	1040000.00	2025-09-28 03:46:21.639091+07
812	134	61	3	70000.00	0.00	0.00	210000.00	2025-09-28 03:46:21.639091+07
813	135	85	1	180000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.65306+07
814	136	59	3	12000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.654679+07
815	136	12	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.654679+07
816	136	29	4	480000.00	0.00	0.00	1920000.00	2025-09-28 03:46:21.654679+07
817	136	25	5	150000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.654679+07
818	136	68	1	40000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.654679+07
819	136	64	2	25000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.654679+07
820	136	68	3	40000.00	0.00	0.00	120000.00	2025-09-28 03:46:21.654679+07
821	136	24	5	45000.00	0.00	0.00	225000.00	2025-09-28 03:46:21.654679+07
822	136	65	2	28000.00	0.00	0.00	56000.00	2025-09-28 03:46:21.654679+07
823	136	17	3	550000.00	0.00	0.00	1650000.00	2025-09-28 03:46:21.654679+07
824	137	8	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.662668+07
825	137	15	1	450000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.662668+07
826	137	28	4	140000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.662668+07
827	137	85	4	180000.00	0.00	0.00	720000.00	2025-09-28 03:46:21.662668+07
828	138	68	2	40000.00	0.00	0.00	80000.00	2025-09-28 03:46:21.666006+07
829	138	106	4	80000.00	0.00	0.00	320000.00	2025-09-28 03:46:21.666006+07
830	138	36	3	580000.00	0.00	0.00	1740000.00	2025-09-28 03:46:21.666006+07
831	139	32	2	300000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.668903+07
832	139	58	5	52000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.668903+07
833	139	4	2	8000.00	0.00	0.00	16000.00	2025-09-28 03:46:21.668903+07
834	139	33	1	50000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.668903+07
835	139	84	5	400000.00	0.00	0.00	2000000.00	2025-09-28 03:46:21.668903+07
836	139	25	4	150000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.668903+07
837	139	91	4	110000.00	0.00	0.00	440000.00	2025-09-28 03:46:21.668903+07
838	140	93	2	190000.00	0.00	0.00	380000.00	2025-09-28 03:46:21.673754+07
839	140	81	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.673754+07
840	140	91	1	110000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.673754+07
841	140	57	1	115000.00	0.00	0.00	115000.00	2025-09-28 03:46:21.673754+07
842	140	83	2	260000.00	0.00	0.00	520000.00	2025-09-28 03:46:21.673754+07
843	141	51	1	1100000.00	0.00	0.00	1100000.00	2025-09-28 03:46:21.678263+07
844	141	56	5	180000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.678263+07
845	141	9	4	5000.00	0.00	0.00	20000.00	2025-09-28 03:46:21.678263+07
846	141	62	1	35000.00	0.00	0.00	35000.00	2025-09-28 03:46:21.678263+07
847	142	24	5	45000.00	0.00	0.00	225000.00	2025-09-28 03:46:21.682114+07
848	142	12	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.682114+07
849	142	62	5	35000.00	0.00	0.00	175000.00	2025-09-28 03:46:21.682114+07
850	142	27	2	90000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.682114+07
851	142	44	3	20000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.682114+07
852	142	41	4	75000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.682114+07
853	143	27	4	90000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.687418+07
854	143	49	4	750000.00	0.00	0.00	3000000.00	2025-09-28 03:46:21.687418+07
855	143	92	2	280000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.687418+07
856	144	9	2	5000.00	0.00	0.00	10000.00	2025-09-28 03:46:21.690353+07
857	144	49	2	750000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.690353+07
858	144	33	1	50000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.690353+07
859	144	48	2	300000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.690353+07
860	144	6	2	25000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.690353+07
861	144	20	5	60000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.690353+07
862	144	21	5	300000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.690353+07
863	144	42	3	55000.00	0.00	0.00	165000.00	2025-09-28 03:46:21.690353+07
864	144	53	2	450000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.690353+07
865	145	55	1	140000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.695772+07
866	145	85	5	180000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.695772+07
867	145	44	4	20000.00	0.00	0.00	80000.00	2025-09-28 03:46:21.695772+07
868	146	55	5	140000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.698518+07
869	146	40	5	150000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.698518+07
870	146	23	1	110000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.698518+07
871	146	66	2	20000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.698518+07
872	146	27	3	90000.00	0.00	0.00	270000.00	2025-09-28 03:46:21.698518+07
873	146	18	1	75000.00	0.00	0.00	75000.00	2025-09-28 03:46:21.698518+07
874	146	85	5	180000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.698518+07
875	146	36	3	580000.00	0.00	0.00	1740000.00	2025-09-28 03:46:21.698518+07
876	146	58	4	52000.00	0.00	0.00	208000.00	2025-09-28 03:46:21.698518+07
877	146	56	4	180000.00	0.00	0.00	720000.00	2025-09-28 03:46:21.698518+07
878	147	91	5	110000.00	0.00	0.00	550000.00	2025-09-28 03:46:21.706096+07
879	147	59	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.706096+07
880	147	91	3	110000.00	0.00	0.00	330000.00	2025-09-28 03:46:21.706096+07
881	147	79	4	120000.00	0.00	0.00	480000.00	2025-09-28 03:46:21.706096+07
882	147	43	4	30000.00	0.00	0.00	120000.00	2025-09-28 03:46:21.706096+07
883	147	38	2	60000.00	0.00	0.00	120000.00	2025-09-28 03:46:21.706096+07
884	147	23	2	110000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.706096+07
885	147	16	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.706096+07
886	147	24	5	45000.00	0.00	0.00	225000.00	2025-09-28 03:46:21.706096+07
887	148	50	4	1950000.00	0.00	0.00	7800000.00	2025-09-28 03:46:21.711866+07
888	148	22	2	130000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.711866+07
889	149	42	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.714121+07
890	149	38	1	60000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.714121+07
891	149	55	4	140000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.714121+07
892	149	32	4	300000.00	0.00	0.00	1200000.00	2025-09-28 03:46:21.714121+07
893	149	36	1	580000.00	0.00	0.00	580000.00	2025-09-28 03:46:21.714121+07
894	149	59	3	12000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.714121+07
895	149	27	5	90000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.714121+07
896	149	48	2	300000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.714121+07
897	149	34	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.714121+07
898	149	9	3	5000.00	0.00	0.00	15000.00	2025-09-28 03:46:21.714121+07
899	150	23	1	110000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.72131+07
900	150	32	2	300000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.72131+07
901	150	85	2	180000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.72131+07
902	151	22	2	130000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.723981+07
903	151	41	3	75000.00	0.00	0.00	225000.00	2025-09-28 03:46:21.723981+07
904	151	9	2	5000.00	0.00	0.00	10000.00	2025-09-28 03:46:21.723981+07
905	151	85	5	180000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.723981+07
906	152	9	4	5000.00	0.00	0.00	20000.00	2025-09-28 03:46:21.727872+07
907	152	32	5	300000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.727872+07
908	152	91	5	110000.00	0.00	0.00	550000.00	2025-09-28 03:46:21.727872+07
909	152	54	2	160000.00	0.00	0.00	320000.00	2025-09-28 03:46:21.727872+07
910	152	38	3	60000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.727872+07
911	152	15	1	450000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.727872+07
912	152	86	2	135000.00	0.00	0.00	270000.00	2025-09-28 03:46:21.727872+07
913	152	52	1	520000.00	0.00	0.00	520000.00	2025-09-28 03:46:21.727872+07
914	152	65	2	28000.00	0.00	0.00	56000.00	2025-09-28 03:46:21.727872+07
915	152	91	1	110000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.727872+07
916	153	42	5	55000.00	0.00	0.00	275000.00	2025-09-28 03:46:21.735702+07
917	154	2	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.736847+07
918	154	54	4	160000.00	0.00	0.00	640000.00	2025-09-28 03:46:21.736847+07
919	154	85	2	180000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.736847+07
920	154	63	5	25000.00	0.00	0.00	125000.00	2025-09-28 03:46:21.736847+07
921	154	53	3	450000.00	0.00	0.00	1350000.00	2025-09-28 03:46:21.736847+07
922	154	48	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.736847+07
923	154	91	5	110000.00	0.00	0.00	550000.00	2025-09-28 03:46:21.736847+07
924	154	93	2	190000.00	0.00	0.00	380000.00	2025-09-28 03:46:21.736847+07
925	154	43	4	30000.00	0.00	0.00	120000.00	2025-09-28 03:46:21.736847+07
926	155	44	3	20000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.743608+07
927	155	92	4	280000.00	0.00	0.00	1120000.00	2025-09-28 03:46:21.743608+07
928	155	93	4	190000.00	0.00	0.00	760000.00	2025-09-28 03:46:21.743608+07
929	155	83	2	260000.00	0.00	0.00	520000.00	2025-09-28 03:46:21.743608+07
930	155	11	4	12000.00	0.00	0.00	48000.00	2025-09-28 03:46:21.743608+07
931	156	9	5	5000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.747954+07
932	156	32	5	300000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.747954+07
933	156	47	2	420000.00	0.00	0.00	840000.00	2025-09-28 03:46:21.747954+07
934	157	28	1	140000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.750138+07
935	157	33	2	50000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.750138+07
936	157	9	4	5000.00	0.00	0.00	20000.00	2025-09-28 03:46:21.750138+07
937	157	56	1	180000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.750138+07
938	157	63	4	25000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.750138+07
939	157	26	4	200000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.750138+07
940	157	3	3	3500.00	0.00	0.00	10500.00	2025-09-28 03:46:21.750138+07
941	157	6	2	25000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.750138+07
942	158	10	4	18000.00	0.00	0.00	72000.00	2025-09-28 03:46:21.75648+07
943	158	32	3	300000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.75648+07
944	158	44	1	20000.00	0.00	0.00	20000.00	2025-09-28 03:46:21.75648+07
945	158	91	1	110000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.75648+07
946	158	107	2	280000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.75648+07
947	158	66	3	20000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.75648+07
948	159	28	5	140000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.761337+07
949	159	19	4	200000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.761337+07
950	160	107	5	280000.00	0.00	0.00	1400000.00	2025-09-28 03:46:21.762793+07
951	160	35	2	130000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.762793+07
952	161	12	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.764992+07
953	161	82	4	290000.00	0.00	0.00	1160000.00	2025-09-28 03:46:21.764992+07
954	161	16	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.764992+07
955	161	106	4	80000.00	0.00	0.00	320000.00	2025-09-28 03:46:21.764992+07
956	161	38	5	60000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.764992+07
957	161	10	3	18000.00	0.00	0.00	54000.00	2025-09-28 03:46:21.764992+07
958	161	64	2	25000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.764992+07
959	161	6	2	25000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.764992+07
960	162	14	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.771503+07
961	162	32	4	300000.00	0.00	0.00	1200000.00	2025-09-28 03:46:21.771503+07
962	162	33	2	50000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.771503+07
963	162	19	5	200000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.771503+07
964	163	5	3	3000.00	0.00	0.00	9000.00	2025-09-28 03:46:21.775464+07
965	163	25	3	150000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.775464+07
966	163	63	5	25000.00	0.00	0.00	125000.00	2025-09-28 03:46:21.775464+07
967	163	41	2	75000.00	0.00	0.00	150000.00	2025-09-28 03:46:21.775464+07
968	163	66	2	20000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.775464+07
969	163	23	5	110000.00	0.00	0.00	550000.00	2025-09-28 03:46:21.775464+07
970	163	21	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.775464+07
971	163	9	2	5000.00	0.00	0.00	10000.00	2025-09-28 03:46:21.775464+07
972	164	40	5	150000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.780598+07
973	164	25	5	150000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.780598+07
974	165	58	2	52000.00	0.00	0.00	104000.00	2025-09-28 03:46:21.782505+07
975	165	31	2	350000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.782505+07
976	165	81	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.782505+07
977	165	82	1	290000.00	0.00	0.00	290000.00	2025-09-28 03:46:21.782505+07
978	165	19	1	200000.00	0.00	0.00	200000.00	2025-09-28 03:46:21.782505+07
979	165	28	3	140000.00	0.00	0.00	420000.00	2025-09-28 03:46:21.782505+07
980	166	107	5	280000.00	0.00	0.00	1400000.00	2025-09-28 03:46:21.787475+07
981	166	29	2	480000.00	0.00	0.00	960000.00	2025-09-28 03:46:21.787475+07
982	167	12	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.789534+07
983	167	67	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.789534+07
984	167	86	1	135000.00	0.00	0.00	135000.00	2025-09-28 03:46:21.789534+07
985	167	81	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.789534+07
986	167	15	3	450000.00	0.00	0.00	1350000.00	2025-09-28 03:46:21.789534+07
987	168	12	5	55000.00	0.00	0.00	275000.00	2025-09-28 03:46:21.793934+07
988	168	5	2	3000.00	0.00	0.00	6000.00	2025-09-28 03:46:21.793934+07
989	168	32	5	300000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.793934+07
990	168	2	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.793934+07
991	168	54	2	160000.00	0.00	0.00	320000.00	2025-09-28 03:46:21.793934+07
992	168	92	1	280000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.793934+07
993	168	7	2	65000.00	0.00	0.00	130000.00	2025-09-28 03:46:21.793934+07
994	169	34	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.799592+07
995	169	33	1	50000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.799592+07
996	170	21	4	300000.00	0.00	0.00	1200000.00	2025-09-28 03:46:21.801392+07
997	170	21	3	300000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.801392+07
998	170	26	5	200000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.801392+07
999	170	82	4	290000.00	0.00	0.00	1160000.00	2025-09-28 03:46:21.801392+07
1000	170	32	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.801392+07
1001	170	26	1	200000.00	0.00	0.00	200000.00	2025-09-28 03:46:21.801392+07
1002	170	52	3	520000.00	0.00	0.00	1560000.00	2025-09-28 03:46:21.801392+07
1003	170	91	2	110000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.801392+07
1004	170	85	2	180000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.801392+07
1005	171	49	1	750000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.807762+07
1006	171	92	2	280000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.807762+07
1007	171	20	5	60000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.807762+07
1008	171	42	2	55000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.807762+07
1009	172	25	4	150000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.812472+07
1010	172	61	3	70000.00	0.00	0.00	210000.00	2025-09-28 03:46:21.812472+07
1011	172	107	1	280000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.812472+07
1012	172	14	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.812472+07
1013	172	59	4	12000.00	0.00	0.00	48000.00	2025-09-28 03:46:21.812472+07
1014	173	55	3	140000.00	0.00	0.00	420000.00	2025-09-28 03:46:21.817642+07
1015	173	23	5	110000.00	0.00	0.00	550000.00	2025-09-28 03:46:21.817642+07
1016	173	68	1	40000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.817642+07
1017	173	8	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.817642+07
1018	174	9	5	5000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.82139+07
1019	174	67	4	55000.00	0.00	0.00	220000.00	2025-09-28 03:46:21.82139+07
1020	174	22	2	130000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.82139+07
1021	174	58	2	52000.00	0.00	0.00	104000.00	2025-09-28 03:46:21.82139+07
1022	174	86	5	135000.00	0.00	0.00	675000.00	2025-09-28 03:46:21.82139+07
1023	175	26	4	200000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.825732+07
1024	175	3	5	3500.00	0.00	0.00	17500.00	2025-09-28 03:46:21.825732+07
1025	175	2	3	12000.00	0.00	0.00	36000.00	2025-09-28 03:46:21.825732+07
1026	175	25	4	150000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.825732+07
1027	175	57	4	115000.00	0.00	0.00	460000.00	2025-09-28 03:46:21.825732+07
1028	175	107	1	280000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.825732+07
1029	175	18	5	75000.00	0.00	0.00	375000.00	2025-09-28 03:46:21.825732+07
1030	176	84	4	400000.00	0.00	0.00	1600000.00	2025-09-28 03:46:21.831823+07
1031	176	28	5	140000.00	0.00	0.00	700000.00	2025-09-28 03:46:21.831823+07
1032	177	29	3	480000.00	0.00	0.00	1440000.00	2025-09-28 03:46:21.834118+07
1033	177	105	3	150000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.834118+07
1034	178	81	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.835642+07
1035	178	46	5	650000.00	0.00	0.00	3250000.00	2025-09-28 03:46:21.835642+07
1036	179	19	2	200000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.837872+07
1037	179	26	1	200000.00	0.00	0.00	200000.00	2025-09-28 03:46:21.837872+07
1038	179	34	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.837872+07
1039	179	65	3	28000.00	0.00	0.00	84000.00	2025-09-28 03:46:21.837872+07
1040	179	82	4	290000.00	0.00	0.00	1160000.00	2025-09-28 03:46:21.837872+07
1041	179	80	4	260000.00	0.00	0.00	1040000.00	2025-09-28 03:46:21.837872+07
1042	179	51	5	1100000.00	0.00	0.00	5500000.00	2025-09-28 03:46:21.837872+07
1043	180	48	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.843385+07
1044	180	47	5	420000.00	0.00	0.00	2100000.00	2025-09-28 03:46:21.843385+07
1045	180	24	5	45000.00	0.00	0.00	225000.00	2025-09-28 03:46:21.843385+07
1046	181	26	3	200000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.846448+07
1047	181	5	4	3000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.846448+07
1048	181	7	1	65000.00	0.00	0.00	65000.00	2025-09-28 03:46:21.846448+07
1049	181	107	4	280000.00	0.00	0.00	1120000.00	2025-09-28 03:46:21.846448+07
1050	182	2	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.850059+07
1051	182	52	5	520000.00	0.00	0.00	2600000.00	2025-09-28 03:46:21.850059+07
1052	182	10	4	18000.00	0.00	0.00	72000.00	2025-09-28 03:46:21.850059+07
1053	182	92	4	280000.00	0.00	0.00	1120000.00	2025-09-28 03:46:21.850059+07
1054	182	92	3	280000.00	0.00	0.00	840000.00	2025-09-28 03:46:21.850059+07
1055	182	16	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.850059+07
1056	182	47	2	420000.00	0.00	0.00	840000.00	2025-09-28 03:46:21.850059+07
1057	182	18	5	75000.00	0.00	0.00	375000.00	2025-09-28 03:46:21.850059+07
1058	182	59	2	12000.00	0.00	0.00	24000.00	2025-09-28 03:46:21.850059+07
1059	183	107	5	280000.00	0.00	0.00	1400000.00	2025-09-28 03:46:21.856902+07
1060	183	5	4	3000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.856902+07
1061	183	16	3	250000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.856902+07
1062	183	107	5	280000.00	0.00	0.00	1400000.00	2025-09-28 03:46:21.856902+07
1063	183	86	2	135000.00	0.00	0.00	270000.00	2025-09-28 03:46:21.856902+07
1064	183	41	5	75000.00	0.00	0.00	375000.00	2025-09-28 03:46:21.856902+07
1065	183	93	4	190000.00	0.00	0.00	760000.00	2025-09-28 03:46:21.856902+07
1066	184	26	2	200000.00	0.00	0.00	400000.00	2025-09-28 03:46:21.861653+07
1067	184	38	2	60000.00	0.00	0.00	120000.00	2025-09-28 03:46:21.861653+07
1068	184	38	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.861653+07
1069	184	26	4	200000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.861653+07
1070	185	26	3	200000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.864397+07
1071	185	46	1	650000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.864397+07
1072	185	63	2	25000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.864397+07
1073	185	11	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.864397+07
1074	185	68	2	40000.00	0.00	0.00	80000.00	2025-09-28 03:46:21.864397+07
1075	185	43	2	30000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.864397+07
1076	185	38	3	60000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.864397+07
1077	186	64	1	25000.00	0.00	0.00	25000.00	2025-09-28 03:46:21.869991+07
1078	186	32	5	300000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.869991+07
1079	186	106	3	80000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.869991+07
1080	186	28	4	140000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.869991+07
1081	187	18	1	75000.00	0.00	0.00	75000.00	2025-09-28 03:46:21.872868+07
1082	187	28	1	140000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.872868+07
1083	187	43	2	30000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.872868+07
1084	187	85	2	180000.00	0.00	0.00	360000.00	2025-09-28 03:46:21.872868+07
1085	187	32	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.872868+07
1086	187	50	3	1950000.00	0.00	0.00	5850000.00	2025-09-28 03:46:21.872868+07
1087	187	83	1	260000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.872868+07
1088	187	53	5	450000.00	0.00	0.00	2250000.00	2025-09-28 03:46:21.872868+07
1089	187	63	4	25000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.872868+07
1090	188	22	4	130000.00	0.00	0.00	520000.00	2025-09-28 03:46:21.880572+07
1091	188	61	1	70000.00	0.00	0.00	70000.00	2025-09-28 03:46:21.880572+07
1092	188	54	5	160000.00	0.00	0.00	800000.00	2025-09-28 03:46:21.880572+07
1093	188	20	2	60000.00	0.00	0.00	120000.00	2025-09-28 03:46:21.880572+07
1094	188	14	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.880572+07
1095	188	29	4	480000.00	0.00	0.00	1920000.00	2025-09-28 03:46:21.880572+07
1096	188	81	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.880572+07
1097	189	47	3	420000.00	0.00	0.00	1260000.00	2025-09-28 03:46:21.885429+07
1098	189	83	3	260000.00	0.00	0.00	780000.00	2025-09-28 03:46:21.885429+07
1099	189	27	1	90000.00	0.00	0.00	90000.00	2025-09-28 03:46:21.885429+07
1100	189	46	1	650000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.885429+07
1101	189	33	5	50000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.885429+07
1102	189	82	4	290000.00	0.00	0.00	1160000.00	2025-09-28 03:46:21.885429+07
1103	189	53	1	450000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.885429+07
1104	189	28	2	140000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.885429+07
1105	189	31	1	350000.00	0.00	0.00	350000.00	2025-09-28 03:46:21.885429+07
1106	189	14	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.885429+07
1107	190	4	5	8000.00	0.00	0.00	40000.00	2025-09-28 03:46:21.892039+07
1108	190	47	2	420000.00	0.00	0.00	840000.00	2025-09-28 03:46:21.892039+07
1109	190	54	4	160000.00	0.00	0.00	640000.00	2025-09-28 03:46:21.892039+07
1110	190	22	1	130000.00	0.00	0.00	130000.00	2025-09-28 03:46:21.892039+07
1111	190	49	5	750000.00	0.00	0.00	3750000.00	2025-09-28 03:46:21.892039+07
1112	190	66	4	20000.00	0.00	0.00	80000.00	2025-09-28 03:46:21.892039+07
1113	191	18	3	75000.00	0.00	0.00	225000.00	2025-09-28 03:46:21.896946+07
1114	191	3	2	3500.00	0.00	0.00	7000.00	2025-09-28 03:46:21.896946+07
1115	191	46	1	650000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.896946+07
1116	191	31	5	350000.00	0.00	0.00	1750000.00	2025-09-28 03:46:21.896946+07
1117	191	21	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.896946+07
1118	191	29	4	480000.00	0.00	0.00	1920000.00	2025-09-28 03:46:21.896946+07
1119	191	1	2	5000.00	0.00	0.00	10000.00	2025-09-28 03:46:21.896946+07
1120	191	50	3	1950000.00	0.00	0.00	5850000.00	2025-09-28 03:46:21.896946+07
1121	192	53	2	450000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.911542+07
1122	192	38	1	60000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.911542+07
1123	192	15	2	450000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.911542+07
1124	192	5	3	3000.00	0.00	0.00	9000.00	2025-09-28 03:46:21.911542+07
1125	193	25	5	150000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.914487+07
1126	193	9	3	5000.00	0.00	0.00	15000.00	2025-09-28 03:46:21.914487+07
1127	193	27	3	90000.00	0.00	0.00	270000.00	2025-09-28 03:46:21.914487+07
1128	194	91	5	110000.00	0.00	0.00	550000.00	2025-09-28 03:46:21.917564+07
1129	194	81	5	250000.00	0.00	0.00	1250000.00	2025-09-28 03:46:21.917564+07
1130	195	67	5	55000.00	0.00	0.00	275000.00	2025-09-28 03:46:21.920495+07
1131	195	22	5	130000.00	0.00	0.00	650000.00	2025-09-28 03:46:21.920495+07
1132	195	26	1	200000.00	0.00	0.00	200000.00	2025-09-28 03:46:21.920495+07
1133	195	52	3	520000.00	0.00	0.00	1560000.00	2025-09-28 03:46:21.920495+07
1134	195	61	2	70000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.920495+07
1135	195	16	2	250000.00	0.00	0.00	500000.00	2025-09-28 03:46:21.920495+07
1136	195	50	3	1950000.00	0.00	0.00	5850000.00	2025-09-28 03:46:21.920495+07
1137	195	1	1	5000.00	0.00	0.00	5000.00	2025-09-28 03:46:21.920495+07
1138	196	92	1	280000.00	0.00	0.00	280000.00	2025-09-28 03:46:21.927034+07
1139	197	58	3	52000.00	0.00	0.00	156000.00	2025-09-28 03:46:21.928514+07
1140	197	32	1	300000.00	0.00	0.00	300000.00	2025-09-28 03:46:21.928514+07
1141	197	44	4	20000.00	0.00	0.00	80000.00	2025-09-28 03:46:21.928514+07
1142	197	53	2	450000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.928514+07
1143	197	20	1	60000.00	0.00	0.00	60000.00	2025-09-28 03:46:21.928514+07
1144	197	28	4	140000.00	0.00	0.00	560000.00	2025-09-28 03:46:21.928514+07
1145	197	50	1	1950000.00	0.00	0.00	1950000.00	2025-09-28 03:46:21.928514+07
1146	198	3	3	3500.00	0.00	0.00	10500.00	2025-09-28 03:46:21.934217+07
1147	198	23	4	110000.00	0.00	0.00	440000.00	2025-09-28 03:46:21.934217+07
1148	198	28	1	140000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.934217+07
1149	198	106	3	80000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.934217+07
1150	198	63	4	25000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.934217+07
1151	198	61	3	70000.00	0.00	0.00	210000.00	2025-09-28 03:46:21.934217+07
1152	198	107	3	280000.00	0.00	0.00	840000.00	2025-09-28 03:46:21.934217+07
1153	198	55	3	140000.00	0.00	0.00	420000.00	2025-09-28 03:46:21.934217+07
1154	199	5	3	3000.00	0.00	0.00	9000.00	2025-09-28 03:46:21.940349+07
1155	199	80	4	260000.00	0.00	0.00	1040000.00	2025-09-28 03:46:21.940349+07
1156	199	83	5	260000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.940349+07
1157	199	106	3	80000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.940349+07
1158	199	19	5	200000.00	0.00	0.00	1000000.00	2025-09-28 03:46:21.940349+07
1159	199	67	2	55000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.940349+07
1160	199	45	1	1300000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.940349+07
1161	199	50	2	1950000.00	0.00	0.00	3900000.00	2025-09-28 03:46:21.940349+07
1162	199	55	3	140000.00	0.00	0.00	420000.00	2025-09-28 03:46:21.940349+07
1163	200	61	1	70000.00	0.00	0.00	70000.00	2025-09-28 03:46:21.947388+07
1164	200	52	2	520000.00	0.00	0.00	1040000.00	2025-09-28 03:46:21.947388+07
1165	200	2	1	12000.00	0.00	0.00	12000.00	2025-09-28 03:46:21.947388+07
1166	200	43	1	30000.00	0.00	0.00	30000.00	2025-09-28 03:46:21.947388+07
1167	201	53	2	450000.00	0.00	0.00	900000.00	2025-09-28 03:46:21.950387+07
1168	202	6	2	25000.00	0.00	0.00	50000.00	2025-09-28 03:46:21.951791+07
1169	202	65	5	28000.00	0.00	0.00	140000.00	2025-09-28 03:46:21.951791+07
1170	202	45	1	1300000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.951791+07
1171	202	45	4	1300000.00	0.00	0.00	5200000.00	2025-09-28 03:46:21.951791+07
1172	202	25	4	150000.00	0.00	0.00	600000.00	2025-09-28 03:46:21.951791+07
1173	202	33	5	50000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.951791+07
1174	203	49	1	750000.00	0.00	0.00	750000.00	2025-09-28 03:46:21.956303+07
1175	203	19	1	200000.00	0.00	0.00	200000.00	2025-09-28 03:46:21.956303+07
1176	203	41	5	75000.00	0.00	0.00	375000.00	2025-09-28 03:46:21.956303+07
1177	204	31	3	350000.00	0.00	0.00	1050000.00	2025-09-28 03:46:21.958288+07
1178	204	29	2	480000.00	0.00	0.00	960000.00	2025-09-28 03:46:21.958288+07
1179	204	9	1	5000.00	0.00	0.00	5000.00	2025-09-28 03:46:21.958288+07
1180	204	24	1	45000.00	0.00	0.00	45000.00	2025-09-28 03:46:21.958288+07
1181	204	58	5	52000.00	0.00	0.00	260000.00	2025-09-28 03:46:21.958288+07
1182	204	20	4	60000.00	0.00	0.00	240000.00	2025-09-28 03:46:21.958288+07
1183	204	83	5	260000.00	0.00	0.00	1300000.00	2025-09-28 03:46:21.958288+07
1184	204	7	3	65000.00	0.00	0.00	195000.00	2025-09-28 03:46:21.958288+07
1185	204	20	3	60000.00	0.00	0.00	180000.00	2025-09-28 03:46:21.958288+07
1186	204	32	4	300000.00	0.00	0.00	1200000.00	2025-09-28 03:46:21.958288+07
1187	205	105	3	150000.00	0.00	0.00	450000.00	2025-09-28 03:46:21.966029+07
1188	205	34	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.966029+07
1189	205	14	1	250000.00	0.00	0.00	250000.00	2025-09-28 03:46:21.966029+07
1190	205	91	1	110000.00	0.00	0.00	110000.00	2025-09-28 03:46:21.966029+07
1191	206	35	1	130000.00	0.00	0.00	130000.00	2025-09-28 03:46:21.969734+07
1192	207	58	4	52000.00	0.00	0.00	208000.00	2025-09-28 03:46:21.971134+07
1193	207	43	1	30000.00	0.00	0.00	30000.00	2025-09-28 03:46:21.971134+07
1194	207	3	3	3500.00	0.00	0.00	10500.00	2025-09-28 03:46:21.971134+07
1195	207	51	2	1100000.00	0.00	0.00	2200000.00	2025-09-28 03:46:21.971134+07
1196	207	47	5	420000.00	0.00	0.00	2100000.00	2025-09-28 03:46:21.971134+07
1197	208	54	1	160000.00	0.00	0.00	160000.00	2025-09-28 03:46:21.975328+07
1198	208	45	4	1300000.00	0.00	0.00	5200000.00	2025-09-28 03:46:21.975328+07
1199	208	35	4	130000.00	0.00	0.00	520000.00	2025-09-28 03:46:21.975328+07
1200	208	85	3	180000.00	0.00	0.00	540000.00	2025-09-28 03:46:21.975328+07
1201	208	44	5	20000.00	0.00	0.00	100000.00	2025-09-28 03:46:21.975328+07
1202	208	21	5	300000.00	0.00	0.00	1500000.00	2025-09-28 03:46:21.975328+07
1203	208	86	4	135000.00	0.00	0.00	540000.00	2025-09-28 03:46:21.975328+07
1204	208	10	4	18000.00	0.00	0.00	72000.00	2025-09-28 03:46:21.975328+07
\.


--
-- TOC entry 5354 (class 0 OID 36912)
-- Dependencies: 249
-- Data for Name: sales_invoices; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.sales_invoices (invoice_id, invoice_no, customer_id, employee_id, invoice_date, subtotal, discount_amount, tax_amount, total_amount, payment_method, points_earned, points_used, notes, created_at) FROM stdin;
44	INV20250900044	173	3	2025-09-07 02:00:00+07	735000.00	0.00	58800.00	793800.00	CASH	793800	0	\N	2025-09-28 03:46:21.237757+07
26	INV20250900026	128	6	2025-09-06 00:00:00+07	5660000.00	0.00	452800.00	6112800.00	CASH	9169200	0	\N	2025-09-28 03:46:21.151089+07
6	INV20250900006	\N	3	2025-09-04 15:00:00+07	5061000.00	0.00	404880.00	5465880.00	CASH	0	0	\N	2025-09-28 03:46:21.051377+07
30	INV20250900030	159	3	2025-09-05 19:00:00+07	3191000.00	0.00	255280.00	3446280.00	CASH	5169420	0	\N	2025-09-28 03:46:21.172789+07
23	INV20250900023	155	6	2025-09-05 16:00:00+07	3958000.00	0.00	316640.00	4274640.00	CASH	5129568	0	\N	2025-09-28 03:46:21.138423+07
19	INV20250900019	22	6	2025-09-05 17:00:00+07	5684000.00	0.00	454720.00	6138720.00	CARD	9208080	0	\N	2025-09-28 03:46:21.117511+07
1	INV20250900001	13	3	2025-09-03 22:00:00+07	4138000.00	0.00	331040.00	4469040.00	CARD	6703560	0	\N	2025-09-28 03:46:21.016783+07
11	INV20250900011	141	6	2025-09-05 15:00:00+07	11620000.00	0.00	929600.00	12549600.00	CASH	31374000	0	\N	2025-09-28 03:46:21.073825+07
15	INV20250900015	40	3	2025-09-05 20:00:00+07	5702000.00	0.00	456160.00	6158160.00	CARD	9237240	0	\N	2025-09-28 03:46:21.098676+07
7	INV20250900007	\N	3	2025-09-05 02:00:00+07	10655000.00	0.00	852400.00	11507400.00	CARD	0	0	\N	2025-09-28 03:46:21.057034+07
2	INV20250900002	123	3	2025-09-03 22:00:00+07	5260000.00	0.00	420800.00	5680800.00	CASH	8521200	0	\N	2025-09-28 03:46:21.030378+07
16	INV20250900016	\N	3	2025-09-06 02:00:00+07	740000.00	0.00	59200.00	799200.00	CASH	0	0	\N	2025-09-28 03:46:21.10444+07
3	INV20250900003	85	3	2025-09-04 02:00:00+07	575000.00	0.00	46000.00	621000.00	CASH	621000	0	\N	2025-09-28 03:46:21.037779+07
28	INV20250900028	\N	3	2025-09-05 22:00:00+07	4311000.00	0.00	344880.00	4655880.00	CARD	0	0	\N	2025-09-28 03:46:21.163184+07
12	INV20250900012	60	6	2025-09-05 21:00:00+07	7040500.00	0.00	563240.00	7603740.00	CARD	11405610	0	\N	2025-09-28 03:46:21.080742+07
20	INV20250900020	106	3	2025-09-06 02:00:00+07	1300000.00	0.00	104000.00	1404000.00	CARD	1684800	0	\N	2025-09-28 03:46:21.12512+07
8	INV20250900008	46	6	2025-09-05 22:00:00+07	7190000.00	0.00	575200.00	7765200.00	CASH	11647800	0	\N	2025-09-28 03:46:21.062376+07
4	INV20250900004	125	3	2025-09-04 15:00:00+07	4936000.00	0.00	394880.00	5330880.00	CARD	7996320	0	\N	2025-09-28 03:46:21.040038+07
24	INV20250900024	167	6	2025-09-05 19:00:00+07	2010000.00	0.00	160800.00	2170800.00	CARD	2604960	0	\N	2025-09-28 03:46:21.141517+07
36	INV20250900036	\N	3	2025-09-07 00:00:00+07	15503000.00	0.00	1240240.00	16743240.00	CARD	0	0	\N	2025-09-28 03:46:21.199433+07
21	INV20250900021	180	6	2025-09-05 18:00:00+07	1660000.00	0.00	132800.00	1792800.00	CASH	2151360	0	\N	2025-09-28 03:46:21.129032+07
13	INV20250900013	186	6	2025-09-05 17:00:00+07	3965000.00	0.00	317200.00	4282200.00	CARD	6423300	0	\N	2025-09-28 03:46:21.085831+07
9	INV20250900009	\N	3	2025-09-05 17:00:00+07	6186000.00	0.00	494880.00	6680880.00	CARD	0	0	\N	2025-09-28 03:46:21.0693+07
5	INV20250900005	74	6	2025-09-04 18:00:00+07	3350000.00	0.00	268000.00	3618000.00	CASH	5427000	0	\N	2025-09-28 03:46:21.045797+07
17	INV20250900017	74	3	2025-09-06 01:00:00+07	3968000.00	0.00	317440.00	4285440.00	CARD	6428160	0	\N	2025-09-28 03:46:21.106104+07
33	INV20250900033	170	6	2025-09-07 02:00:00+07	3954000.00	0.00	316320.00	4270320.00	CASH	6405480	0	\N	2025-09-28 03:46:21.183125+07
31	INV20250900031	194	3	2025-09-05 16:00:00+07	1145000.00	0.00	91600.00	1236600.00	CASH	1236600	0	\N	2025-09-28 03:46:21.178641+07
27	INV20250900027	\N	6	2025-09-05 22:00:00+07	7350000.00	0.00	588000.00	7938000.00	CASH	0	0	\N	2025-09-28 03:46:21.157356+07
10	INV20250900010	\N	6	2025-09-05 22:00:00+07	60000.00	0.00	4800.00	64800.00	CASH	0	0	\N	2025-09-28 03:46:21.072439+07
18	INV20250900018	6	6	2025-09-05 18:00:00+07	3635000.00	0.00	290800.00	3925800.00	CARD	5888700	0	\N	2025-09-28 03:46:21.111383+07
14	INV20250900014	163	3	2025-09-05 23:00:00+07	11135000.00	0.00	890800.00	12025800.00	CARD	24051600	0	\N	2025-09-28 03:46:21.091295+07
32	INV20250900032	188	3	2025-09-05 17:00:00+07	360000.00	0.00	28800.00	388800.00	CARD	388800	0	\N	2025-09-28 03:46:21.181721+07
25	INV20250900025	163	3	2025-09-05 20:00:00+07	4166500.00	0.00	333320.00	4499820.00	CASH	11249550	0	\N	2025-09-28 03:46:21.145105+07
29	INV20250900029	\N	3	2025-09-05 19:00:00+07	2120000.00	0.00	169600.00	2289600.00	CARD	0	0	\N	2025-09-28 03:46:21.169581+07
46	INV20250900046	98	6	2025-09-07 01:00:00+07	1300000.00	0.00	104000.00	1404000.00	CASH	1404000	0	\N	2025-09-28 03:46:21.241027+07
38	INV20250900038	21	3	2025-09-07 00:00:00+07	3574000.00	0.00	285920.00	3859920.00	CASH	5789880	0	\N	2025-09-28 03:46:21.210723+07
22	INV20250900022	195	6	2025-09-05 16:00:00+07	3086000.00	0.00	246880.00	3332880.00	CARD	3999456	0	\N	2025-09-28 03:46:21.131687+07
35	INV20250900035	116	3	2025-09-06 15:00:00+07	3179000.00	0.00	254320.00	3433320.00	CARD	4119984	0	\N	2025-09-28 03:46:21.194251+07
37	INV20250900037	\N	3	2025-09-06 15:00:00+07	9730000.00	0.00	778400.00	10508400.00	CASH	0	0	\N	2025-09-28 03:46:21.205387+07
40	INV20250900040	\N	3	2025-09-07 02:00:00+07	1364000.00	0.00	109120.00	1473120.00	CASH	0	0	\N	2025-09-28 03:46:21.219923+07
45	INV20250900045	\N	3	2025-09-06 20:00:00+07	3030000.00	0.00	242400.00	3272400.00	CASH	0	0	\N	2025-09-28 03:46:21.239754+07
34	INV20250900034	195	3	2025-09-07 01:00:00+07	5241000.00	0.00	419280.00	5660280.00	CASH	8490420	0	\N	2025-09-28 03:46:21.188449+07
43	INV20250900043	58	3	2025-09-06 23:00:00+07	5074000.00	0.00	405920.00	5479920.00	CASH	8219880	0	\N	2025-09-28 03:46:21.23318+07
41	INV20250900041	117	3	2025-09-06 21:00:00+07	2820000.00	0.00	225600.00	3045600.00	CASH	3654720	0	\N	2025-09-28 03:46:21.221966+07
39	INV20250900039	87	3	2025-09-06 17:00:00+07	3360000.00	0.00	268800.00	3628800.00	CARD	4354560	0	\N	2025-09-28 03:46:21.217278+07
51	INV20250900051	158	6	2025-09-06 15:00:00+07	1040000.00	0.00	83200.00	1123200.00	CASH	1123200	0	\N	2025-09-28 03:46:21.256039+07
42	INV20250900042	179	6	2025-09-07 02:00:00+07	7884000.00	0.00	630720.00	8514720.00	CASH	17029440	0	\N	2025-09-28 03:46:21.225953+07
48	INV20250900048	174	6	2025-09-07 00:00:00+07	2360000.00	0.00	188800.00	2548800.00	CASH	3058560	0	\N	2025-09-28 03:46:21.247261+07
47	INV20250900047	111	3	2025-09-06 21:00:00+07	2185000.00	0.00	174800.00	2359800.00	CARD	2831760	0	\N	2025-09-28 03:46:21.242385+07
49	INV20250900049	\N	6	2025-09-07 02:00:00+07	2810000.00	0.00	224800.00	3034800.00	CASH	0	0	\N	2025-09-28 03:46:21.249812+07
50	INV20250900050	\N	3	2025-09-06 16:00:00+07	7996000.00	0.00	639680.00	8635680.00	CASH	0	0	\N	2025-09-28 03:46:21.25321+07
52	INV20250900052	33	3	2025-09-06 23:00:00+07	2680000.00	0.00	214400.00	2894400.00	CASH	3473280	0	\N	2025-09-28 03:46:21.257185+07
59	INV20250900059	122	6	2025-09-07 01:00:00+07	1530000.00	0.00	122400.00	1652400.00	CARD	1982880	0	\N	2025-09-28 03:46:21.285751+07
80	INV20250900080	149	6	2025-09-09 17:00:00+07	4322000.00	0.00	345760.00	4667760.00	CARD	7001640	0	\N	2025-09-28 03:46:21.384919+07
90	INV20250900090	171	6	2025-09-11 00:00:00+07	400000.00	0.00	32000.00	432000.00	CARD	432000	0	\N	2025-09-28 03:46:21.436151+07
53	INV20250900053	174	3	2025-09-06 22:00:00+07	5625000.00	0.00	450000.00	6075000.00	CASH	9112500	0	\N	2025-09-28 03:46:21.261298+07
65	INV20250900065	\N	3	2025-09-09 02:00:00+07	6979000.00	0.00	558320.00	7537320.00	CASH	0	0	\N	2025-09-28 03:46:21.311695+07
60	INV20250900060	88	6	2025-09-07 00:00:00+07	2222500.00	0.00	177800.00	2400300.00	CARD	2880360	0	\N	2025-09-28 03:46:21.288029+07
54	INV20250900054	16	3	2025-09-06 23:00:00+07	8240000.00	0.00	659200.00	8899200.00	CASH	10679040	0	\N	2025-09-28 03:46:21.265824+07
86	INV20250900086	151	6	2025-09-10 16:00:00+07	1489000.00	0.00	119120.00	1608120.00	CASH	1929744	0	\N	2025-09-28 03:46:21.417141+07
82	INV20250900082	104	3	2025-09-10 23:00:00+07	4404000.00	0.00	352320.00	4756320.00	CASH	7134480	0	\N	2025-09-28 03:46:21.396471+07
69	INV20250900069	61	6	2025-09-08 19:00:00+07	6079000.00	0.00	486320.00	6565320.00	CARD	9847980	0	\N	2025-09-28 03:46:21.33486+07
61	INV20250900061	35	6	2025-09-07 00:00:00+07	3290000.00	0.00	263200.00	3553200.00	CARD	4263840	0	\N	2025-09-28 03:46:21.292571+07
55	INV20250900055	138	3	2025-09-07 02:00:00+07	6325000.00	0.00	506000.00	6831000.00	CASH	10246500	0	\N	2025-09-28 03:46:21.268674+07
66	INV20250900066	\N	3	2025-09-08 17:00:00+07	3259000.00	0.00	260720.00	3519720.00	CASH	0	0	\N	2025-09-28 03:46:21.318174+07
100	INV20250900100	1	3	2025-09-11 22:00:00+07	2400000.00	0.00	192000.00	2592000.00	CASH	3110400	0	\N	2025-09-28 03:46:21.472497+07
73	INV20250900073	\N	6	2025-09-09 20:00:00+07	7257000.00	0.00	580560.00	7837560.00	CARD	0	0	\N	2025-09-28 03:46:21.356226+07
62	INV20250900062	116	3	2025-09-06 18:00:00+07	1215000.00	0.00	97200.00	1312200.00	CASH	1968300	0	\N	2025-09-28 03:46:21.296407+07
56	INV20250900056	\N	6	2025-09-06 22:00:00+07	3156000.00	0.00	252480.00	3408480.00	CASH	0	0	\N	2025-09-28 03:46:21.27374+07
70	INV20250900070	\N	3	2025-09-08 22:00:00+07	5985000.00	0.00	478800.00	6463800.00	CARD	0	0	\N	2025-09-28 03:46:21.34231+07
67	INV20250900067	71	6	2025-09-09 02:00:00+07	3244000.00	0.00	259520.00	3503520.00	CASH	4204224	0	\N	2025-09-28 03:46:21.322378+07
78	INV20250900078	166	3	2025-09-09 19:00:00+07	3321000.00	0.00	265680.00	3586680.00	CASH	5380020	0	\N	2025-09-28 03:46:21.37392+07
63	INV20250900063	62	3	2025-09-06 18:00:00+07	4985000.00	0.00	398800.00	5383800.00	CASH	8075700	0	\N	2025-09-28 03:46:21.301443+07
57	INV20250900057	\N	6	2025-09-07 01:00:00+07	10098000.00	0.00	807840.00	10905840.00	CASH	0	0	\N	2025-09-28 03:46:21.277554+07
74	INV20250900074	13	3	2025-09-09 19:00:00+07	5325000.00	0.00	426000.00	5751000.00	CARD	8626500	0	\N	2025-09-28 03:46:21.362519+07
64	INV20250900064	138	3	2025-09-07 00:00:00+07	532000.00	0.00	42560.00	574560.00	CASH	1149120	0	\N	2025-09-28 03:46:21.307185+07
58	INV20250900058	9	3	2025-09-07 02:00:00+07	1660000.00	0.00	132800.00	1792800.00	CASH	2151360	0	\N	2025-09-28 03:46:21.282713+07
81	INV20250900081	196	6	2025-09-10 01:00:00+07	9310000.00	0.00	744800.00	10054800.00	CASH	20109600	0	\N	2025-09-28 03:46:21.390265+07
71	INV20250900071	57	3	2025-09-09 01:00:00+07	5396000.00	0.00	431680.00	5827680.00	CASH	8741520	0	\N	2025-09-28 03:46:21.344576+07
75	INV20250900075	31	6	2025-09-09 23:00:00+07	711000.00	0.00	56880.00	767880.00	CASH	767880	0	\N	2025-09-28 03:46:21.364762+07
87	INV20250900087	\N	6	2025-09-10 15:00:00+07	1145000.00	0.00	91600.00	1236600.00	CARD	0	0	\N	2025-09-28 03:46:21.424412+07
79	INV20250900079	46	3	2025-09-09 19:00:00+07	5130000.00	0.00	410400.00	5540400.00	CASH	11080800	0	\N	2025-09-28 03:46:21.3807+07
68	INV20250900068	104	3	2025-09-08 20:00:00+07	1845000.00	0.00	147600.00	1992600.00	CARD	2391120	0	\N	2025-09-28 03:46:21.328074+07
92	INV20250900092	\N	6	2025-09-10 16:00:00+07	310000.00	0.00	24800.00	334800.00	CASH	0	0	\N	2025-09-28 03:46:21.443249+07
85	INV20250900085	24	6	2025-09-11 02:00:00+07	4908000.00	0.00	392640.00	5300640.00	CARD	7950960	0	\N	2025-09-28 03:46:21.409594+07
76	INV20250900076	\N	3	2025-09-09 20:00:00+07	1746000.00	0.00	139680.00	1885680.00	CASH	0	0	\N	2025-09-28 03:46:21.367257+07
72	INV20250900072	\N	3	2025-09-08 23:00:00+07	2704000.00	0.00	216320.00	2920320.00	CASH	0	0	\N	2025-09-28 03:46:21.351255+07
83	INV20250900083	95	3	2025-09-10 16:00:00+07	2380000.00	0.00	190400.00	2570400.00	CARD	3084480	0	\N	2025-09-28 03:46:21.404045+07
77	INV20250900077	13	6	2025-09-09 17:00:00+07	1600000.00	0.00	128000.00	1728000.00	CASH	3456000	0	\N	2025-09-28 03:46:21.371917+07
95	INV20250900095	18	6	2025-09-10 19:00:00+07	738000.00	0.00	59040.00	797040.00	CASH	797040	0	\N	2025-09-28 03:46:21.454072+07
93	INV20250900093	\N	3	2025-09-11 02:00:00+07	300000.00	0.00	24000.00	324000.00	CARD	0	0	\N	2025-09-28 03:46:21.44551+07
88	INV20250900088	150	6	2025-09-11 02:00:00+07	4290000.00	0.00	343200.00	4633200.00	CARD	6949800	0	\N	2025-09-28 03:46:21.426398+07
84	INV20250900084	46	3	2025-09-10 15:00:00+07	100000.00	0.00	8000.00	108000.00	CARD	216000	0	\N	2025-09-28 03:46:21.407604+07
97	INV20250900097	25	3	2025-09-10 20:00:00+07	4340000.00	0.00	347200.00	4687200.00	CASH	5624640	0	\N	2025-09-28 03:46:21.458508+07
89	INV20250900089	\N	6	2025-09-11 00:00:00+07	563500.00	0.00	45080.00	608580.00	CASH	0	0	\N	2025-09-28 03:46:21.433772+07
91	INV20250900091	\N	3	2025-09-10 15:00:00+07	4845000.00	0.00	387600.00	5232600.00	CASH	0	0	\N	2025-09-28 03:46:21.437473+07
96	INV20250900096	77	3	2025-09-10 17:00:00+07	1310000.00	0.00	104800.00	1414800.00	CASH	1414800	0	\N	2025-09-28 03:46:21.456491+07
94	INV20250900094	68	3	2025-09-10 18:00:00+07	7664000.00	0.00	613120.00	8277120.00	CARD	16554240	0	\N	2025-09-28 03:46:21.446401+07
99	INV20250900099	81	3	2025-09-11 19:00:00+07	5275000.00	0.00	422000.00	5697000.00	CASH	8545500	0	\N	2025-09-28 03:46:21.467263+07
98	INV20250900098	74	3	2025-09-12 01:00:00+07	7770000.00	0.00	621600.00	8391600.00	CARD	16783200	0	\N	2025-09-28 03:46:21.461463+07
101	INV20250900101	30	6	2025-09-12 00:00:00+07	4678000.00	0.00	374240.00	5052240.00	CASH	7578360	0	\N	2025-09-28 03:46:21.473653+07
107	INV20250900107	179	3	2025-09-12 16:00:00+07	6384000.00	0.00	510720.00	6894720.00	CASH	17236800	0	\N	2025-09-28 03:46:21.503402+07
118	INV20250900118	\N	6	2025-09-13 02:00:00+07	4067000.00	0.00	325360.00	4392360.00	CARD	0	0	\N	2025-09-28 03:46:21.554026+07
131	INV20250900131	78	3	2025-09-13 16:00:00+07	11435000.00	0.00	914800.00	12349800.00	CARD	24699600	0	\N	2025-09-28 03:46:21.626479+07
129	INV20250900129	125	6	2025-09-13 20:00:00+07	5580000.00	0.00	446400.00	6026400.00	CASH	12052800	0	\N	2025-09-28 03:46:21.613698+07
102	INV20250900102	121	3	2025-09-12 19:00:00+07	2828000.00	0.00	226240.00	3054240.00	CASH	3665088	0	\N	2025-09-28 03:46:21.479868+07
125	INV20250900125	18	6	2025-09-12 17:00:00+07	4364000.00	0.00	349120.00	4713120.00	CARD	7069680	0	\N	2025-09-28 03:46:21.587811+07
108	INV20250900108	72	6	2025-09-12 19:00:00+07	1935000.00	0.00	154800.00	2089800.00	CASH	2507760	0	\N	2025-09-28 03:46:21.51221+07
127	INV20250900127	152	3	2025-09-13 20:00:00+07	5942000.00	0.00	475360.00	6417360.00	CARD	9626040	0	\N	2025-09-28 03:46:21.602128+07
119	INV20250900119	19	3	2025-09-12 18:00:00+07	3855000.00	0.00	308400.00	4163400.00	CASH	4996080	0	\N	2025-09-28 03:46:21.559396+07
114	INV20250900114	165	3	2025-09-12 19:00:00+07	2408000.00	0.00	192640.00	2600640.00	CASH	3120768	0	\N	2025-09-28 03:46:21.533614+07
109	INV20250900109	\N	3	2025-09-12 15:00:00+07	1215000.00	0.00	97200.00	1312200.00	CASH	0	0	\N	2025-09-28 03:46:21.516568+07
103	INV20250900103	29	6	2025-09-12 20:00:00+07	3895000.00	0.00	311600.00	4206600.00	CASH	6309900	0	\N	2025-09-28 03:46:21.484577+07
110	INV20250900110	8	6	2025-09-12 23:00:00+07	2000000.00	0.00	160000.00	2160000.00	CASH	2592000	0	\N	2025-09-28 03:46:21.519495+07
123	INV20250900123	\N	6	2025-09-12 16:00:00+07	1767500.00	0.00	141400.00	1908900.00	CASH	0	0	\N	2025-09-28 03:46:21.573766+07
104	INV20250900104	76	3	2025-09-12 18:00:00+07	4551000.00	0.00	364080.00	4915080.00	CASH	7372620	0	\N	2025-09-28 03:46:21.491522+07
120	INV20250900120	122	3	2025-09-12 17:00:00+07	1041000.00	0.00	83280.00	1124280.00	CASH	1349136	0	\N	2025-09-28 03:46:21.563635+07
115	INV20250900115	54	3	2025-09-13 02:00:00+07	3770000.00	0.00	301600.00	4071600.00	CASH	6107400	0	\N	2025-09-28 03:46:21.540112+07
111	INV20250900111	118	6	2025-09-12 23:00:00+07	936000.00	0.00	74880.00	1010880.00	CARD	1213056	0	\N	2025-09-28 03:46:21.521713+07
105	INV20250900105	\N	6	2025-09-13 02:00:00+07	3145000.00	0.00	251600.00	3396600.00	CARD	0	0	\N	2025-09-28 03:46:21.4982+07
116	INV20250900116	30	6	2025-09-12 15:00:00+07	60000.00	0.00	4800.00	64800.00	CASH	97200	0	\N	2025-09-28 03:46:21.546069+07
106	INV20250900106	145	6	2025-09-12 20:00:00+07	500000.00	0.00	40000.00	540000.00	CARD	540000	0	\N	2025-09-28 03:46:21.502024+07
140	INV20250900140	164	6	2025-09-16 21:00:00+07	1375000.00	0.00	110000.00	1485000.00	CASH	1782000	0	\N	2025-09-28 03:46:21.673754+07
134	INV20250900134	\N	3	2025-09-13 17:00:00+07	1250000.00	0.00	100000.00	1350000.00	CARD	0	0	\N	2025-09-28 03:46:21.639091+07
139	INV20250900139	\N	3	2025-09-16 22:00:00+07	3966000.00	0.00	317280.00	4283280.00	CASH	0	0	\N	2025-09-28 03:46:21.668903+07
121	INV20250900121	108	3	2025-09-12 22:00:00+07	1135000.00	0.00	90800.00	1225800.00	CASH	1225800	0	\N	2025-09-28 03:46:21.568572+07
132	INV20250900132	\N	3	2025-09-13 22:00:00+07	4110000.00	0.00	328800.00	4438800.00	CASH	0	0	\N	2025-09-28 03:46:21.631092+07
130	INV20250900130	31	3	2025-09-13 20:00:00+07	3300000.00	0.00	264000.00	3564000.00	CARD	5346000	0	\N	2025-09-28 03:46:21.620792+07
117	INV20250900117	8	3	2025-09-13 00:00:00+07	10526000.00	0.00	842080.00	11368080.00	CASH	17052120	0	\N	2025-09-28 03:46:21.547491+07
112	INV20250900112	106	6	2025-09-12 21:00:00+07	1220000.00	0.00	97600.00	1317600.00	CASH	1581120	0	\N	2025-09-28 03:46:21.527602+07
126	INV20250900126	188	6	2025-09-13 17:00:00+07	8553000.00	0.00	684240.00	9237240.00	CARD	18474480	0	\N	2025-09-28 03:46:21.59433+07
113	INV20250900113	14	6	2025-09-13 00:00:00+07	1880000.00	0.00	150400.00	2030400.00	CARD	2436480	0	\N	2025-09-28 03:46:21.530831+07
135	INV20250900135	118	3	2025-09-15 17:00:00+07	180000.00	0.00	14400.00	194400.00	CARD	233280	0	\N	2025-09-28 03:46:21.65306+07
124	INV20250900124	\N	6	2025-09-12 21:00:00+07	3774000.00	0.00	301920.00	4075920.00	CASH	0	0	\N	2025-09-28 03:46:21.580659+07
128	INV20250900128	\N	3	2025-09-13 18:00:00+07	4544000.00	0.00	363520.00	4907520.00	CASH	0	0	\N	2025-09-28 03:46:21.608389+07
122	INV20250900122	\N	3	2025-09-12 15:00:00+07	1560000.00	0.00	124800.00	1684800.00	CARD	0	0	\N	2025-09-28 03:46:21.572215+07
143	INV20250900143	55	3	2025-09-16 16:00:00+07	3920000.00	0.00	313600.00	4233600.00	CASH	5080320	0	\N	2025-09-28 03:46:21.687418+07
137	INV20250900137	\N	3	2025-09-16 17:00:00+07	1742000.00	0.00	139360.00	1881360.00	CARD	0	0	\N	2025-09-28 03:46:21.662668+07
138	INV20250900138	123	3	2025-09-17 00:00:00+07	2140000.00	0.00	171200.00	2311200.00	CASH	3466800	0	\N	2025-09-28 03:46:21.666006+07
133	INV20250900133	112	3	2025-09-13 22:00:00+07	5010000.00	0.00	400800.00	5410800.00	CARD	8116200	0	\N	2025-09-28 03:46:21.634102+07
148	INV20250900148	136	3	2025-09-19 19:00:00+07	8060000.00	0.00	644800.00	8704800.00	CASH	13057200	0	\N	2025-09-28 03:46:21.711866+07
136	INV20250900136	142	3	2025-09-16 15:00:00+07	5067000.00	0.00	405360.00	5472360.00	CARD	8208540	0	\N	2025-09-28 03:46:21.654679+07
145	INV20250900145	91	3	2025-09-16 19:00:00+07	1120000.00	0.00	89600.00	1209600.00	CARD	1209600	0	\N	2025-09-28 03:46:21.695772+07
142	INV20250900142	184	3	2025-09-16 17:00:00+07	1105000.00	0.00	88400.00	1193400.00	CASH	1432080	0	\N	2025-09-28 03:46:21.682114+07
141	INV20250900141	193	3	2025-09-16 16:00:00+07	2055000.00	0.00	164400.00	2219400.00	CASH	2663280	0	\N	2025-09-28 03:46:21.678263+07
144	INV20250900144	\N	3	2025-09-17 02:00:00+07	5075000.00	0.00	406000.00	5481000.00	CASH	0	0	\N	2025-09-28 03:46:21.690353+07
147	INV20250900147	\N	3	2025-09-18 16:00:00+07	2807000.00	0.00	224560.00	3031560.00	CASH	0	0	\N	2025-09-28 03:46:21.706096+07
146	INV20250900146	85	6	2025-09-16 23:00:00+07	5513000.00	0.00	441040.00	5954040.00	CARD	8931060	0	\N	2025-09-28 03:46:21.698518+07
149	INV20250900149	\N	6	2025-09-19 20:00:00+07	4471000.00	0.00	357680.00	4828680.00	CASH	0	0	\N	2025-09-28 03:46:21.714121+07
193	INV20250900193	50	6	2025-09-23 15:00:00+07	1035000.00	0.00	82800.00	1117800.00	CASH	1117800	0	\N	2025-09-28 03:46:21.914487+07
168	INV20250900168	120	6	2025-09-19 21:00:00+07	2523000.00	0.00	201840.00	2724840.00	CASH	3269808	0	\N	2025-09-28 03:46:21.793934+07
150	INV20250900150	21	6	2025-09-20 02:00:00+07	1070000.00	0.00	85600.00	1155600.00	CARD	1733400	0	\N	2025-09-28 03:46:21.72131+07
172	INV20250900172	66	6	2025-09-20 23:00:00+07	1388000.00	0.00	111040.00	1499040.00	CASH	1798848	0	\N	2025-09-28 03:46:21.812472+07
163	INV20250900163	\N	3	2025-09-19 18:00:00+07	1634000.00	0.00	130720.00	1764720.00	CASH	0	0	\N	2025-09-28 03:46:21.775464+07
157	INV20250900157	151	6	2025-09-19 15:00:00+07	1400500.00	0.00	112040.00	1512540.00	CASH	1815048	0	\N	2025-09-28 03:46:21.750138+07
151	INV20250900151	87	3	2025-09-19 23:00:00+07	1395000.00	0.00	111600.00	1506600.00	CASH	1807920	0	\N	2025-09-28 03:46:21.723981+07
169	INV20250900169	100	3	2025-09-20 02:00:00+07	800000.00	0.00	64000.00	864000.00	CARD	864000	0	\N	2025-09-28 03:46:21.799592+07
164	INV20250900164	\N	3	2025-09-19 16:00:00+07	1500000.00	0.00	120000.00	1620000.00	CASH	0	0	\N	2025-09-28 03:46:21.780598+07
158	INV20250900158	10	6	2025-09-20 01:00:00+07	1722000.00	0.00	137760.00	1859760.00	CARD	2231712	0	\N	2025-09-28 03:46:21.75648+07
176	INV20250900176	117	3	2025-09-21 01:00:00+07	2300000.00	0.00	184000.00	2484000.00	CARD	3726000	0	\N	2025-09-28 03:46:21.831823+07
152	INV20250900152	71	6	2025-09-19 18:00:00+07	3976000.00	0.00	318080.00	4294080.00	CASH	8588160	0	\N	2025-09-28 03:46:21.727872+07
153	INV20250900153	\N	6	2025-09-19 22:00:00+07	275000.00	0.00	22000.00	297000.00	CASH	0	0	\N	2025-09-28 03:46:21.735702+07
159	INV20250900159	\N	3	2025-09-19 19:00:00+07	1500000.00	0.00	120000.00	1620000.00	CASH	0	0	\N	2025-09-28 03:46:21.761337+07
173	INV20250900173	49	6	2025-09-21 02:00:00+07	1022000.00	0.00	81760.00	1103760.00	CASH	1103760	0	\N	2025-09-28 03:46:21.817642+07
160	INV20250900160	68	6	2025-09-20 02:00:00+07	1660000.00	0.00	132800.00	1792800.00	CASH	3585600	0	\N	2025-09-28 03:46:21.762793+07
165	INV20250900165	159	3	2025-09-19 20:00:00+07	2464000.00	0.00	197120.00	2661120.00	CASH	3991680	0	\N	2025-09-28 03:46:21.782505+07
154	INV20250900154	56	6	2025-09-19 15:00:00+07	3837000.00	0.00	306960.00	4143960.00	CASH	6215940	0	\N	2025-09-28 03:46:21.736847+07
185	INV20250900185	56	6	2025-09-20 23:00:00+07	1632000.00	0.00	130560.00	1762560.00	CASH	2643840	0	\N	2025-09-28 03:46:21.864397+07
177	INV20250900177	\N	3	2025-09-20 20:00:00+07	1890000.00	0.00	151200.00	2041200.00	CARD	0	0	\N	2025-09-28 03:46:21.834118+07
166	INV20250900166	46	3	2025-09-19 18:00:00+07	2360000.00	0.00	188800.00	2548800.00	CASH	5097600	0	\N	2025-09-28 03:46:21.787475+07
155	INV20250900155	142	3	2025-09-19 16:00:00+07	2508000.00	0.00	200640.00	2708640.00	CASH	5417280	0	\N	2025-09-28 03:46:21.743608+07
161	INV20250900161	81	3	2025-09-19 18:00:00+07	2904000.00	0.00	232320.00	3136320.00	CASH	6272640	0	\N	2025-09-28 03:46:21.764992+07
170	INV20250900170	\N	3	2025-09-19 18:00:00+07	6900000.00	0.00	552000.00	7452000.00	CASH	0	0	\N	2025-09-28 03:46:21.801392+07
156	INV20250900156	\N	6	2025-09-20 01:00:00+07	2365000.00	0.00	189200.00	2554200.00	CASH	0	0	\N	2025-09-28 03:46:21.747954+07
181	INV20250900181	145	3	2025-09-21 01:00:00+07	1797000.00	0.00	143760.00	1940760.00	CASH	2328912	0	\N	2025-09-28 03:46:21.846448+07
167	INV20250900167	22	3	2025-09-19 17:00:00+07	2175000.00	0.00	174000.00	2349000.00	CASH	4698000	0	\N	2025-09-28 03:46:21.789534+07
162	INV20250900162	22	3	2025-09-20 00:00:00+07	3050000.00	0.00	244000.00	3294000.00	CASH	6588000	0	\N	2025-09-28 03:46:21.771503+07
174	INV20250900174	194	6	2025-09-20 18:00:00+07	1284000.00	0.00	102720.00	1386720.00	CASH	1664064	0	\N	2025-09-28 03:46:21.82139+07
171	INV20250900171	107	6	2025-09-19 23:00:00+07	1720000.00	0.00	137600.00	1857600.00	CARD	2229120	0	\N	2025-09-28 03:46:21.807762+07
178	INV20250900178	\N	6	2025-09-20 16:00:00+07	3500000.00	0.00	280000.00	3780000.00	CASH	0	0	\N	2025-09-28 03:46:21.835642+07
183	INV20250900183	\N	3	2025-09-21 00:00:00+07	4967000.00	0.00	397360.00	5364360.00	CARD	0	0	\N	2025-09-28 03:46:21.856902+07
196	INV20250900196	38	6	2025-09-23 21:00:00+07	280000.00	0.00	22400.00	302400.00	CASH	302400	0	\N	2025-09-28 03:46:21.927034+07
188	INV20250900188	\N	3	2025-09-20 18:00:00+07	3930000.00	0.00	314400.00	4244400.00	CASH	0	0	\N	2025-09-28 03:46:21.880572+07
184	INV20250900184	\N	6	2025-09-21 01:00:00+07	1560000.00	0.00	124800.00	1684800.00	CASH	0	0	\N	2025-09-28 03:46:21.861653+07
179	INV20250900179	6	6	2025-09-20 20:00:00+07	8884000.00	0.00	710720.00	9594720.00	CASH	19189440	0	\N	2025-09-28 03:46:21.837872+07
175	INV20250900175	41	3	2025-09-21 00:00:00+07	2568500.00	0.00	205480.00	2773980.00	CARD	3328776	0	\N	2025-09-28 03:46:21.825732+07
192	INV20250900192	\N	3	2025-09-22 15:00:00+07	1869000.00	0.00	149520.00	2018520.00	CARD	0	0	\N	2025-09-28 03:46:21.911542+07
182	INV20250900182	98	6	2025-09-20 23:00:00+07	6383000.00	0.00	510640.00	6893640.00	CASH	13787280	0	\N	2025-09-28 03:46:21.850059+07
180	INV20250900180	90	3	2025-09-20 23:00:00+07	2625000.00	0.00	210000.00	2835000.00	CASH	3402000	0	\N	2025-09-28 03:46:21.843385+07
190	INV20250900190	23	3	2025-09-20 22:00:00+07	5480000.00	0.00	438400.00	5918400.00	CASH	8877600	0	\N	2025-09-28 03:46:21.892039+07
186	INV20250900186	\N	3	2025-09-20 21:00:00+07	2325000.00	0.00	186000.00	2511000.00	CASH	0	0	\N	2025-09-28 03:46:21.869991+07
187	INV20250900187	42	6	2025-09-20 23:00:00+07	9395000.00	0.00	751600.00	10146600.00	CASH	15219900	0	\N	2025-09-28 03:46:21.872868+07
189	INV20250900189	\N	3	2025-09-21 01:00:00+07	5770000.00	0.00	461600.00	6231600.00	CASH	0	0	\N	2025-09-28 03:46:21.885429+07
191	INV20250900191	122	3	2025-09-21 01:00:00+07	10712000.00	0.00	856960.00	11568960.00	CARD	23137920	0	\N	2025-09-28 03:46:21.896946+07
194	INV20250900194	25	3	2025-09-24 00:00:00+07	1800000.00	0.00	144000.00	1944000.00	CASH	2916000	0	\N	2025-09-28 03:46:21.917564+07
195	INV20250900195	60	3	2025-09-24 01:00:00+07	9180000.00	0.00	734400.00	9914400.00	CARD	19828800	0	\N	2025-09-28 03:46:21.920495+07
197	INV20250900197	27	6	2025-09-23 20:00:00+07	4006000.00	0.00	320480.00	4326480.00	CASH	5191776	0	\N	2025-09-28 03:46:21.928514+07
198	INV20250900198	8	6	2025-09-23 20:00:00+07	2400500.00	0.00	192040.00	2592540.00	CASH	5185080	0	\N	2025-09-28 03:46:21.934217+07
206	INV20250900206	121	3	2025-09-23 19:00:00+07	130000.00	0.00	10400.00	140400.00	CASH	168480	0	\N	2025-09-28 03:46:21.969734+07
207	INV20250900207	182	6	2025-09-23 17:00:00+07	4548500.00	0.00	363880.00	4912380.00	CASH	5894856	0	\N	2025-09-28 03:46:21.971134+07
199	INV20250900199	62	3	2025-09-23 17:00:00+07	9319000.00	0.00	745520.00	10064520.00	CASH	20129040	0	\N	2025-09-28 03:46:21.940349+07
200	INV20250900200	\N	3	2025-09-23 19:00:00+07	1152000.00	0.00	92160.00	1244160.00	CARD	0	0	\N	2025-09-28 03:46:21.947388+07
201	INV20250900201	162	6	2025-09-23 23:00:00+07	900000.00	0.00	72000.00	972000.00	CASH	972000	0	\N	2025-09-28 03:46:21.950387+07
208	INV20250900208	\N	3	2025-09-24 19:00:00+07	8632000.00	0.00	690560.00	9322560.00	CASH	0	0	\N	2025-09-28 03:46:21.975328+07
202	INV20250900202	3	6	2025-09-23 22:00:00+07	7540000.00	0.00	603200.00	8143200.00	CARD	12214800	0	\N	2025-09-28 03:46:21.951791+07
203	INV20250900203	\N	3	2025-09-23 17:00:00+07	1325000.00	0.00	106000.00	1431000.00	CASH	0	0	\N	2025-09-28 03:46:21.956303+07
204	INV20250900204	62	3	2025-09-23 19:00:00+07	5435000.00	0.00	434800.00	5869800.00	CASH	14674500	0	\N	2025-09-28 03:46:21.958288+07
205	INV20250900205	7	3	2025-09-23 21:00:00+07	1060000.00	0.00	84800.00	1144800.00	CASH	1144800	0	\N	2025-09-28 03:46:21.966029+07
\.


--
-- TOC entry 5350 (class 0 OID 36894)
-- Dependencies: 245
-- Data for Name: shelf_batch_inventory; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.shelf_batch_inventory (shelf_batch_id, shelf_id, product_id, batch_code, quantity, expiry_date, stocked_date, import_price, current_price, discount_percent, is_near_expiry, created_at, updated_at) FROM stdin;
29	2	17	BATCH202509010017	39	2025-12-01	2025-09-02 07:00:00+07	350000.00	550000.00	0.00	f	2025-09-28 03:46:20.959298+07	2025-09-28 03:46:21.661895+07
27	4	62	BATCH202509010062	95	2025-12-01	2025-09-02 07:00:00+07	22000.00	35000.00	0.00	f	2025-09-28 03:46:20.956711+07	2025-09-28 03:46:21.683698+07
74	5	79	BATCH202509010079	131	2025-12-01	2025-09-02 07:00:00+07	80000.00	120000.00	0.00	f	2025-09-28 03:46:21.012773+07	2025-09-28 03:46:21.708386+07
42	4	56	BATCH202509010056	22	2025-12-01	2025-09-02 07:00:00+07	120000.00	180000.00	0.00	f	2025-09-28 03:46:20.9732+07	2025-09-28 03:46:21.752908+07
25	3	40	BATCH202509010040	85	2025-12-01	2025-09-02 07:00:00+07	90000.00	150000.00	0.00	f	2025-09-28 03:46:20.955174+07	2025-09-28 03:46:21.781274+07
38	1	12	BATCH202509010012	54	2025-12-01	2025-09-02 07:00:00+07	35000.00	55000.00	0.00	f	2025-09-28 03:46:20.968541+07	2025-09-28 03:46:21.794412+07
10	3	42	BATCH202509010042	88	2025-12-01	2025-09-02 07:00:00+07	30000.00	55000.00	0.00	f	2025-09-28 03:46:20.939777+07	2025-09-28 03:46:21.811362+07
54	5	84	BATCH202509010084	60	2025-12-01	2025-09-02 07:00:00+07	280000.00	400000.00	0.00	f	2025-09-28 03:46:20.989156+07	2025-09-28 03:46:21.832698+07
12	10	48	BATCH202509010048	20	2025-12-01	2025-09-02 07:00:00+07	180000.00	300000.00	0.00	f	2025-09-28 03:46:20.942338+07	2025-09-28 03:46:21.844184+07
34	1	11	BATCH202509010011	52	2025-12-01	2025-09-02 07:00:00+07	8000.00	12000.00	0.00	f	2025-09-28 03:46:20.964938+07	2025-09-28 03:46:21.867101+07
22	7	68	BATCH202509010068	55	2025-12-01	2025-09-02 07:00:00+07	25000.00	40000.00	0.00	f	2025-09-28 03:46:20.952574+07	2025-09-28 03:46:21.867611+07
11	7	64	BATCH202509010064	40	2025-12-01	2025-09-02 07:00:00+07	15000.00	25000.00	0.00	f	2025-09-28 03:46:20.940797+07	2025-09-28 03:46:21.870289+07
8	7	66	BATCH202509010066	67	2025-12-01	2025-09-02 07:00:00+07	12000.00	20000.00	0.00	f	2025-09-28 03:46:20.936641+07	2025-09-28 03:46:21.896182+07
70	5	82	BATCH202509010082	63	2025-12-01	2025-09-02 07:00:00+07	200000.00	290000.00	0.00	f	2025-09-28 03:46:21.008678+07	2025-09-28 03:46:21.904948+07
44	3	38	BATCH202509010038	68	2025-12-01	2025-09-02 07:00:00+07	35000.00	60000.00	0.00	f	2025-09-28 03:46:20.975771+07	2025-09-28 03:46:21.912752+07
77	1	15	BATCH202509010015	130	2025-12-01	2025-09-02 07:00:00+07	280000.00	450000.00	0.00	f	2025-09-28 03:46:21.016414+07	2025-09-28 03:46:21.913266+07
30	2	27	BATCH202509010027	75	2025-12-01	2025-09-02 07:00:00+07	55000.00	90000.00	0.00	f	2025-09-28 03:46:20.960321+07	2025-09-28 03:46:21.91656+07
64	1	8	BATCH202509010008	110	2025-12-01	2025-09-02 07:00:00+07	8000.00	12000.00	0.00	f	2025-09-28 03:46:20.998886+07	2025-09-28 03:46:21.820227+07
21	4	57	BATCH202509010057	82	2025-12-01	2025-09-02 07:00:00+07	85000.00	115000.00	0.00	f	2025-09-28 03:46:20.951554+07	2025-09-28 03:46:21.82961+07
31	4	59	BATCH202509010059	111	2025-12-01	2025-09-02 07:00:00+07	8000.00	12000.00	0.00	f	2025-09-28 03:46:20.960834+07	2025-09-28 03:46:21.855368+07
7	8	93	BATCH202509010093	132	2025-12-01	2025-09-02 07:00:00+07	120000.00	190000.00	0.00	f	2025-09-28 03:46:20.935615+07	2025-09-28 03:46:21.861104+07
37	1	4	BATCH202509010004	35	2025-12-01	2025-09-02 07:00:00+07	5000.00	8000.00	0.00	f	2025-09-28 03:46:20.968024+07	2025-09-28 03:46:21.892757+07
66	2	18	BATCH202509010018	121	2025-12-01	2025-09-02 07:00:00+07	45000.00	75000.00	0.00	f	2025-09-28 03:46:21.000428+07	2025-09-28 03:46:21.898236+07
62	10	46	BATCH202509010046	83	2025-12-01	2025-09-02 07:00:00+07	380000.00	650000.00	0.00	f	2025-09-28 03:46:20.995808+07	2025-09-28 03:46:21.899822+07
13	3	36	BATCH202509010036	64	2025-12-01	2025-09-02 07:00:00+07	350000.00	580000.00	0.00	f	2025-09-28 03:46:20.943362+07	2025-09-28 03:46:21.909126+07
15	5	81	BATCH202509010081	93	2025-12-01	2025-09-02 07:00:00+07	175000.00	250000.00	0.00	f	2025-09-28 03:46:20.945913+07	2025-09-28 03:46:21.918926+07
68	2	22	BATCH202509010022	55	2025-12-01	2025-09-02 07:00:00+07	80000.00	130000.00	0.00	f	2025-09-28 03:46:21.004059+07	2025-09-28 03:46:21.921552+07
24	2	26	BATCH202509010026	59	2025-12-01	2025-09-02 07:00:00+07	120000.00	200000.00	0.00	f	2025-09-28 03:46:20.954662+07	2025-09-28 03:46:21.922577+07
71	2	16	BATCH202509010016	51	2025-12-01	2025-09-02 07:00:00+07	150000.00	250000.00	0.00	f	2025-09-28 03:46:21.009694+07	2025-09-28 03:46:21.924745+07
58	1	1	BATCH202509010001	146	2025-12-01	2025-09-02 07:00:00+07	3000.00	5000.00	0.00	f	2025-09-28 03:46:20.993256+07	2025-09-28 03:46:21.926284+07
73	8	92	BATCH202509010092	71	2025-12-01	2025-09-02 07:00:00+07	180000.00	280000.00	0.00	f	2025-09-28 03:46:21.01175+07	2025-09-28 03:46:21.92783+07
17	2	23	BATCH202509010023	125	2025-12-01	2025-09-02 07:00:00+07	65000.00	110000.00	0.00	f	2025-09-28 03:46:20.947963+07	2025-09-28 03:46:21.935314+07
50	2	28	BATCH202509010028	45	2025-12-01	2025-09-02 07:00:00+07	85000.00	140000.00	0.00	f	2025-09-28 03:46:20.982954+07	2025-09-28 03:46:21.936344+07
4	4	63	BATCH202509010063	82	2025-12-01	2025-09-02 07:00:00+07	15000.00	25000.00	0.00	f	2025-09-28 03:46:20.931518+07	2025-09-28 03:46:21.937478+07
65	9	107	BATCH202509010107	140	2025-12-01	2025-09-02 07:00:00+07	150000.00	280000.00	0.00	f	2025-09-28 03:46:20.999408+07	2025-09-28 03:46:21.93909+07
43	1	5	BATCH202509010005	59	2025-12-01	2025-09-02 07:00:00+07	1500.00	3000.00	0.00	f	2025-09-28 03:46:20.974232+07	2025-09-28 03:46:21.94079+07
63	5	80	BATCH202509010080	57	2025-12-01	2025-09-02 07:00:00+07	180000.00	260000.00	0.00	f	2025-09-28 03:46:20.997851+07	2025-09-28 03:46:21.941309+07
9	9	106	BATCH202509010106	59	2025-12-01	2025-09-02 07:00:00+07	45000.00	80000.00	0.00	f	2025-09-28 03:46:20.938192+07	2025-09-28 03:46:21.942847+07
48	7	67	BATCH202509010067	104	2025-12-01	2025-09-02 07:00:00+07	35000.00	55000.00	0.00	f	2025-09-28 03:46:20.979884+07	2025-09-28 03:46:21.944499+07
6	10	50	BATCH202509010050	132	2025-12-01	2025-09-02 07:00:00+07	1200000.00	1950000.00	0.00	f	2025-09-28 03:46:20.934597+07	2025-09-28 03:46:21.945934+07
53	10	55	BATCH202509010055	90	2025-12-01	2025-09-02 07:00:00+07	85000.00	140000.00	0.00	f	2025-09-28 03:46:20.987088+07	2025-09-28 03:46:21.946442+07
32	4	61	BATCH202509010061	147	2025-12-01	2025-09-02 07:00:00+07	45000.00	70000.00	0.00	f	2025-09-28 03:46:20.962372+07	2025-09-28 03:46:21.947978+07
51	10	52	BATCH202509010052	62	2025-12-01	2025-09-02 07:00:00+07	320000.00	520000.00	0.00	f	2025-09-28 03:46:20.983981+07	2025-09-28 03:46:21.948493+07
76	1	2	BATCH202509010002	132	2025-12-01	2025-09-02 07:00:00+07	8000.00	12000.00	0.00	f	2025-09-28 03:46:21.015333+07	2025-09-28 03:46:21.949227+07
72	10	53	BATCH202509010053	85	2025-12-01	2025-09-02 07:00:00+07	280000.00	450000.00	0.00	f	2025-09-28 03:46:21.01071+07	2025-09-28 03:46:21.950801+07
59	1	6	BATCH202509010006	120	2025-12-01	2025-09-02 07:00:00+07	15000.00	25000.00	0.00	f	2025-09-28 03:46:20.994283+07	2025-09-28 03:46:21.952344+07
57	7	65	BATCH202509010065	110	2025-12-01	2025-09-02 07:00:00+07	18000.00	28000.00	0.00	f	2025-09-28 03:46:20.992219+07	2025-09-28 03:46:21.952859+07
49	2	25	BATCH202509010025	27	2025-12-01	2025-09-02 07:00:00+07	90000.00	150000.00	0.00	f	2025-09-28 03:46:20.981924+07	2025-09-28 03:46:21.955023+07
41	3	33	BATCH202509010033	136	2025-12-01	2025-09-02 07:00:00+07	25000.00	50000.00	0.00	f	2025-09-28 03:46:20.972689+07	2025-09-28 03:46:21.955754+07
1	10	49	BATCH202509010049	62	2025-12-01	2025-09-02 07:00:00+07	450000.00	750000.00	0.00	f	2025-09-28 03:46:20.926366+07	2025-09-28 03:46:21.956788+07
67	2	19	BATCH202509010019	37	2025-12-01	2025-09-02 07:00:00+07	120000.00	200000.00	0.00	f	2025-09-28 03:46:21.002008+07	2025-09-28 03:46:21.957295+07
47	3	41	BATCH202509010041	39	2025-12-01	2025-09-02 07:00:00+07	45000.00	75000.00	0.00	f	2025-09-28 03:46:20.978858+07	2025-09-28 03:46:21.957811+07
2	3	31	BATCH202509010031	134	2025-12-01	2025-09-02 07:00:00+07	200000.00	350000.00	0.00	f	2025-09-28 03:46:20.928933+07	2025-09-28 03:46:21.958842+07
18	2	29	BATCH202509010029	45	2025-12-01	2025-09-02 07:00:00+07	300000.00	480000.00	0.00	f	2025-09-28 03:46:20.949002+07	2025-09-28 03:46:21.959863+07
60	1	9	BATCH202509010009	144	2025-12-01	2025-09-02 07:00:00+07	3000.00	5000.00	0.00	f	2025-09-28 03:46:20.994792+07	2025-09-28 03:46:21.960381+07
23	2	24	BATCH202509010024	156	2025-12-01	2025-09-02 07:00:00+07	25000.00	45000.00	0.00	f	2025-09-28 03:46:20.953601+07	2025-09-28 03:46:21.960968+07
75	5	83	BATCH202509010083	48	2025-12-01	2025-09-02 07:00:00+07	180000.00	260000.00	0.00	f	2025-09-28 03:46:21.0138+07	2025-09-28 03:46:21.963102+07
35	9	105	BATCH202509010105	156	2025-12-01	2025-09-02 07:00:00+07	80000.00	150000.00	0.00	f	2025-09-28 03:46:20.96596+07	2025-09-28 03:46:21.966383+07
16	1	14	BATCH202509010014	112	2025-12-01	2025-09-02 07:00:00+07	150000.00	250000.00	0.00	f	2025-09-28 03:46:20.946935+07	2025-09-28 03:46:21.968001+07
45	4	58	BATCH202509010058	107	2025-12-01	2025-09-02 07:00:00+07	35000.00	52000.00	0.00	f	2025-09-28 03:46:20.976797+07	2025-09-28 03:46:21.97162+07
20	3	43	BATCH202509010043	26	2025-12-01	2025-09-02 07:00:00+07	15000.00	30000.00	0.00	f	2025-09-28 03:46:20.950536+07	2025-09-28 03:46:21.972128+07
46	1	3	BATCH202509010003	134	2025-12-01	2025-09-02 07:00:00+07	2000.00	3500.00	0.00	f	2025-09-28 03:46:20.977831+07	2025-09-28 03:46:21.973166+07
40	10	51	BATCH202509010051	100	2025-12-01	2025-09-02 07:00:00+07	650000.00	1100000.00	0.00	f	2025-09-28 03:46:20.971664+07	2025-09-28 03:46:21.973715+07
52	10	54	BATCH202509010054	104	2025-12-01	2025-09-02 07:00:00+07	95000.00	160000.00	0.00	f	2025-09-28 03:46:20.985004+07	2025-09-28 03:46:21.975969+07
26	3	45	BATCH202509010045	81	2025-12-01	2025-09-02 07:00:00+07	800000.00	1300000.00	0.00	f	2025-09-28 03:46:20.956197+07	2025-09-28 03:46:21.976481+07
56	3	44	BATCH202509010044	154	2025-12-01	2025-09-02 07:00:00+07	12000.00	20000.00	0.00	f	2025-09-28 03:46:20.990685+07	2025-09-28 03:46:21.978024+07
61	2	21	BATCH202509010021	56	2025-12-01	2025-09-02 07:00:00+07	180000.00	300000.00	0.00	f	2025-09-28 03:46:20.995301+07	2025-09-28 03:46:21.978535+07
33	1	7	BATCH202509010007	33	2025-12-01	2025-09-02 07:00:00+07	45000.00	65000.00	0.00	f	2025-09-28 03:46:20.963402+07	2025-09-28 03:46:21.963609+07
39	2	20	BATCH202509010020	36	2025-12-01	2025-09-02 07:00:00+07	35000.00	60000.00	0.00	f	2025-09-28 03:46:20.970627+07	2025-09-28 03:46:21.964316+07
55	3	32	BATCH202509010032	91	2025-12-01	2025-09-02 07:00:00+07	180000.00	300000.00	0.00	f	2025-09-28 03:46:20.990176+07	2025-09-28 03:46:21.965363+07
3	3	34	BATCH202509010034	120	2025-12-01	2025-09-02 07:00:00+07	150000.00	250000.00	0.00	f	2025-09-28 03:46:20.929959+07	2025-09-28 03:46:21.967487+07
14	8	91	BATCH202509010091	95	2025-12-01	2025-09-02 07:00:00+07	65000.00	110000.00	0.00	f	2025-09-28 03:46:20.944894+07	2025-09-28 03:46:21.968515+07
69	10	47	BATCH202509010047	46	2025-12-01	2025-09-02 07:00:00+07	250000.00	420000.00	0.00	f	2025-09-28 03:46:21.006103+07	2025-09-28 03:46:21.974226+07
19	3	35	BATCH202509010035	62	2025-12-01	2025-09-02 07:00:00+07	80000.00	130000.00	0.00	f	2025-09-28 03:46:20.950027+07	2025-09-28 03:46:21.976996+07
5	5	85	BATCH202509010085	23	2025-12-01	2025-09-02 07:00:00+07	120000.00	180000.00	0.00	f	2025-09-28 03:46:20.933056+07	2025-09-28 03:46:21.977506+07
36	5	86	BATCH202509010086	54	2025-12-01	2025-09-02 07:00:00+07	90000.00	135000.00	0.00	f	2025-09-28 03:46:20.966987+07	2025-09-28 03:46:21.979064+07
28	1	10	BATCH202509010010	19	2025-12-01	2025-09-02 07:00:00+07	12000.00	18000.00	0.00	f	2025-09-28 03:46:20.958259+07	2025-09-28 03:46:21.979573+07
\.


--
-- TOC entry 5348 (class 0 OID 36880)
-- Dependencies: 243
-- Data for Name: shelf_inventory; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.shelf_inventory (shelf_inventory_id, shelf_id, product_id, current_quantity, near_expiry_quantity, expired_quantity, earliest_expiry_date, latest_expiry_date, last_restocked, updated_at) FROM stdin;
31	2	17	39	0	0	\N	\N	2025-09-28 03:46:21.310916+07	2025-09-28 03:46:21.654679+07
29	4	62	95	0	0	\N	\N	2025-09-28 03:46:20.956784+07	2025-09-28 03:46:21.682114+07
80	5	79	131	0	0	\N	\N	2025-09-28 03:46:21.012618+07	2025-09-28 03:46:21.706096+07
46	4	56	22	0	0	\N	\N	2025-09-28 03:46:20.973247+07	2025-09-28 03:46:21.750138+07
27	3	40	85	0	0	\N	\N	2025-09-28 03:46:20.955228+07	2025-09-28 03:46:21.780598+07
41	1	12	54	0	0	\N	\N	2025-09-28 03:46:20.968598+07	2025-09-28 03:46:21.793934+07
11	3	42	88	0	0	\N	\N	2025-09-28 03:46:20.939655+07	2025-09-28 03:46:21.807762+07
70	1	8	110	0	0	\N	\N	2025-09-28 03:46:20.998528+07	2025-09-28 03:46:21.817642+07
23	4	57	82	0	0	\N	\N	2025-09-28 03:46:20.951362+07	2025-09-28 03:46:21.825732+07
60	5	84	60	0	0	\N	\N	2025-09-28 03:46:21.643107+07	2025-09-28 03:46:21.831823+07
13	10	48	20	0	0	\N	\N	2025-09-28 03:46:20.942094+07	2025-09-28 03:46:21.843385+07
33	4	59	111	0	0	\N	\N	2025-09-28 03:46:20.960903+07	2025-09-28 03:46:21.850059+07
7	8	93	132	0	0	\N	\N	2025-09-28 03:46:20.935385+07	2025-09-28 03:46:21.856902+07
37	1	11	52	0	0	\N	\N	2025-09-28 03:46:21.650651+07	2025-09-28 03:46:21.864397+07
24	7	68	55	0	0	\N	\N	2025-09-28 03:46:21.649709+07	2025-09-28 03:46:21.864397+07
12	7	64	40	0	0	\N	\N	2025-09-28 03:46:20.940546+07	2025-09-28 03:46:21.869991+07
40	1	4	35	0	0	\N	\N	2025-09-28 03:46:20.967683+07	2025-09-28 03:46:21.892039+07
8	7	66	67	0	0	\N	\N	2025-09-28 03:46:20.936468+07	2025-09-28 03:46:21.892039+07
72	2	18	121	0	0	\N	\N	2025-09-28 03:46:21.000157+07	2025-09-28 03:46:21.896946+07
68	10	46	83	0	0	\N	\N	2025-09-28 03:46:20.996017+07	2025-09-28 03:46:21.896946+07
76	5	82	63	0	0	\N	\N	2025-09-28 03:46:21.904809+07	2025-09-28 03:46:21.904809+07
14	3	36	64	0	0	\N	\N	2025-09-28 03:46:21.908932+07	2025-09-28 03:46:21.908932+07
48	3	38	68	0	0	\N	\N	2025-09-28 03:46:20.975588+07	2025-09-28 03:46:21.911542+07
83	1	15	130	0	0	\N	\N	2025-09-28 03:46:21.01609+07	2025-09-28 03:46:21.911542+07
32	2	27	75	0	0	\N	\N	2025-09-28 03:46:20.960105+07	2025-09-28 03:46:21.914487+07
17	5	81	93	0	0	\N	\N	2025-09-28 03:46:20.945738+07	2025-09-28 03:46:21.917564+07
74	2	22	55	0	0	\N	\N	2025-09-28 03:46:21.906876+07	2025-09-28 03:46:21.920495+07
26	2	26	59	0	0	\N	\N	2025-09-28 03:46:20.954375+07	2025-09-28 03:46:21.920495+07
77	2	16	51	0	0	\N	\N	2025-09-28 03:46:21.009692+07	2025-09-28 03:46:21.920495+07
64	1	1	146	0	0	\N	\N	2025-09-28 03:46:20.993256+07	2025-09-28 03:46:21.920495+07
79	8	92	71	0	0	\N	\N	2025-09-28 03:46:21.011685+07	2025-09-28 03:46:21.927034+07
19	2	23	125	0	0	\N	\N	2025-09-28 03:46:20.947773+07	2025-09-28 03:46:21.934217+07
54	2	28	45	0	0	\N	\N	2025-09-28 03:46:21.9109+07	2025-09-28 03:46:21.934217+07
4	4	63	82	0	0	\N	\N	2025-09-28 03:46:20.931203+07	2025-09-28 03:46:21.934217+07
71	9	107	140	0	0	\N	\N	2025-09-28 03:46:20.999438+07	2025-09-28 03:46:21.934217+07
47	1	5	59	0	0	\N	\N	2025-09-28 03:46:20.974251+07	2025-09-28 03:46:21.940349+07
69	5	80	57	0	0	\N	\N	2025-09-28 03:46:20.997483+07	2025-09-28 03:46:21.940349+07
9	9	106	59	0	0	\N	\N	2025-09-28 03:46:20.937975+07	2025-09-28 03:46:21.940349+07
52	7	67	104	0	0	\N	\N	2025-09-28 03:46:20.979842+07	2025-09-28 03:46:21.940349+07
6	10	50	132	0	0	\N	\N	2025-09-28 03:46:20.934062+07	2025-09-28 03:46:21.940349+07
57	10	55	90	0	0	\N	\N	2025-09-28 03:46:20.986439+07	2025-09-28 03:46:21.940349+07
35	4	61	147	0	0	\N	\N	2025-09-28 03:46:20.962356+07	2025-09-28 03:46:21.947388+07
55	10	52	62	0	0	\N	\N	2025-09-28 03:46:21.907775+07	2025-09-28 03:46:21.947388+07
82	1	2	132	0	0	\N	\N	2025-09-28 03:46:21.015025+07	2025-09-28 03:46:21.947388+07
78	10	53	85	0	0	\N	\N	2025-09-28 03:46:21.010731+07	2025-09-28 03:46:21.950387+07
65	1	6	120	0	0	\N	\N	2025-09-28 03:46:20.994004+07	2025-09-28 03:46:21.951791+07
63	7	65	110	0	0	\N	\N	2025-09-28 03:46:20.991701+07	2025-09-28 03:46:21.951791+07
53	2	25	27	0	0	\N	\N	2025-09-28 03:46:20.981653+07	2025-09-28 03:46:21.951791+07
45	3	33	136	0	0	\N	\N	2025-09-28 03:46:20.972432+07	2025-09-28 03:46:21.951791+07
1	10	49	62	0	0	\N	\N	2025-09-28 03:46:21.90999+07	2025-09-28 03:46:21.956303+07
73	2	19	37	0	0	\N	\N	2025-09-28 03:46:21.64485+07	2025-09-28 03:46:21.956303+07
51	3	41	39	0	0	\N	\N	2025-09-28 03:46:20.978702+07	2025-09-28 03:46:21.956303+07
2	3	31	134	0	0	\N	\N	2025-09-28 03:46:20.92822+07	2025-09-28 03:46:21.958288+07
20	2	29	45	0	0	\N	\N	2025-09-28 03:46:21.647257+07	2025-09-28 03:46:21.958288+07
66	1	9	144	0	0	\N	\N	2025-09-28 03:46:20.994726+07	2025-09-28 03:46:21.958288+07
25	2	24	156	0	0	\N	\N	2025-09-28 03:46:20.953313+07	2025-09-28 03:46:21.958288+07
81	5	83	48	0	0	\N	\N	2025-09-28 03:46:21.645986+07	2025-09-28 03:46:21.958288+07
36	1	7	33	0	0	\N	\N	2025-09-28 03:46:20.963232+07	2025-09-28 03:46:21.958288+07
43	2	20	36	0	0	\N	\N	2025-09-28 03:46:21.64845+07	2025-09-28 03:46:21.958288+07
61	3	32	91	0	0	\N	\N	2025-09-28 03:46:20.99003+07	2025-09-28 03:46:21.958288+07
38	9	105	156	0	0	\N	\N	2025-09-28 03:46:20.965662+07	2025-09-28 03:46:21.966029+07
3	3	34	120	0	0	\N	\N	2025-09-28 03:46:20.929647+07	2025-09-28 03:46:21.966029+07
18	1	14	112	0	0	\N	\N	2025-09-28 03:46:20.946604+07	2025-09-28 03:46:21.966029+07
16	8	91	95	0	0	\N	\N	2025-09-28 03:46:20.944613+07	2025-09-28 03:46:21.966029+07
49	4	58	107	0	0	\N	\N	2025-09-28 03:46:20.97654+07	2025-09-28 03:46:21.971134+07
22	3	43	26	0	0	\N	\N	2025-09-28 03:46:20.950573+07	2025-09-28 03:46:21.971134+07
50	1	3	134	0	0	\N	\N	2025-09-28 03:46:20.977554+07	2025-09-28 03:46:21.971134+07
44	10	51	100	0	0	\N	\N	2025-09-28 03:46:20.971574+07	2025-09-28 03:46:21.971134+07
75	10	47	46	0	0	\N	\N	2025-09-28 03:46:21.652249+07	2025-09-28 03:46:21.971134+07
56	10	54	104	0	0	\N	\N	2025-09-28 03:46:20.984918+07	2025-09-28 03:46:21.975328+07
28	3	45	81	0	0	\N	\N	2025-09-28 03:46:20.956007+07	2025-09-28 03:46:21.975328+07
21	3	35	62	0	0	\N	\N	2025-09-28 03:46:21.651441+07	2025-09-28 03:46:21.975328+07
5	5	85	23	0	0	\N	\N	2025-09-28 03:46:20.932673+07	2025-09-28 03:46:21.975328+07
62	3	44	154	0	0	\N	\N	2025-09-28 03:46:20.990773+07	2025-09-28 03:46:21.975328+07
67	2	21	56	0	0	\N	\N	2025-09-28 03:46:21.905986+07	2025-09-28 03:46:21.975328+07
39	5	86	54	0	0	\N	\N	2025-09-28 03:46:20.966811+07	2025-09-28 03:46:21.975328+07
30	1	10	19	0	0	\N	\N	2025-09-28 03:46:20.958004+07	2025-09-28 03:46:21.975328+07
\.


--
-- TOC entry 5346 (class 0 OID 36872)
-- Dependencies: 241
-- Data for Name: shelf_layout; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.shelf_layout (layout_id, shelf_id, product_id, position_code, max_quantity, created_at, updated_at) FROM stdin;
1	1	1	POS-1-1	200	2025-09-28 03:46:20.887714+07	2025-09-28 03:46:20.887263+07
2	1	2	POS-1-2	200	2025-09-28 03:46:20.889379+07	2025-09-28 03:46:20.88932+07
3	1	3	POS-1-3	200	2025-09-28 03:46:20.889881+07	2025-09-28 03:46:20.88983+07
4	1	4	POS-1-4	200	2025-09-28 03:46:20.890339+07	2025-09-28 03:46:20.890343+07
5	1	5	POS-1-5	200	2025-09-28 03:46:20.890802+07	2025-09-28 03:46:20.890343+07
6	1	6	POS-1-6	200	2025-09-28 03:46:20.891352+07	2025-09-28 03:46:20.891362+07
7	1	7	POS-1-7	200	2025-09-28 03:46:20.891774+07	2025-09-28 03:46:20.891362+07
8	1	8	POS-1-8	200	2025-09-28 03:46:20.892201+07	2025-09-28 03:46:20.89187+07
9	1	9	POS-1-9	200	2025-09-28 03:46:20.892622+07	2025-09-28 03:46:20.892379+07
10	1	10	POS-1-10	200	2025-09-28 03:46:20.893016+07	2025-09-28 03:46:20.892889+07
11	1	11	POS-1-11	200	2025-09-28 03:46:20.89343+07	2025-09-28 03:46:20.893441+07
12	1	12	POS-1-12	200	2025-09-28 03:46:20.893788+07	2025-09-28 03:46:20.893441+07
13	1	13	POS-1-13	200	2025-09-28 03:46:20.894098+07	2025-09-28 03:46:20.893953+07
14	1	14	POS-1-14	200	2025-09-28 03:46:20.894367+07	2025-09-28 03:46:20.893953+07
15	1	15	POS-1-15	200	2025-09-28 03:46:20.894648+07	2025-09-28 03:46:20.894463+07
16	2	16	POS-2-16	200	2025-09-28 03:46:20.894935+07	2025-09-28 03:46:20.894463+07
17	2	17	POS-2-17	200	2025-09-28 03:46:20.895241+07	2025-09-28 03:46:20.894972+07
18	2	18	POS-2-18	200	2025-09-28 03:46:20.895525+07	2025-09-28 03:46:20.895484+07
19	2	19	POS-2-19	200	2025-09-28 03:46:20.895763+07	2025-09-28 03:46:20.895484+07
20	2	20	POS-2-20	200	2025-09-28 03:46:20.896064+07	2025-09-28 03:46:20.895995+07
21	2	21	POS-2-21	200	2025-09-28 03:46:20.8963+07	2025-09-28 03:46:20.895995+07
22	2	22	POS-2-22	200	2025-09-28 03:46:20.896538+07	2025-09-28 03:46:20.896504+07
23	2	23	POS-2-23	200	2025-09-28 03:46:20.897019+07	2025-09-28 03:46:20.897016+07
24	2	24	POS-2-24	200	2025-09-28 03:46:20.897407+07	2025-09-28 03:46:20.897016+07
25	2	25	POS-2-25	200	2025-09-28 03:46:20.897854+07	2025-09-28 03:46:20.897533+07
26	2	26	POS-2-26	200	2025-09-28 03:46:20.898274+07	2025-09-28 03:46:20.898055+07
27	2	27	POS-2-27	200	2025-09-28 03:46:20.898655+07	2025-09-28 03:46:20.898573+07
28	2	28	POS-2-28	200	2025-09-28 03:46:20.899014+07	2025-09-28 03:46:20.898573+07
29	2	29	POS-2-29	200	2025-09-28 03:46:20.899355+07	2025-09-28 03:46:20.899085+07
30	2	30	POS-2-30	200	2025-09-28 03:46:20.899706+07	2025-09-28 03:46:20.899599+07
31	3	31	POS-3-31	200	2025-09-28 03:46:20.900086+07	2025-09-28 03:46:20.900109+07
32	3	32	POS-3-32	200	2025-09-28 03:46:20.900386+07	2025-09-28 03:46:20.900109+07
33	3	33	POS-3-33	200	2025-09-28 03:46:20.900743+07	2025-09-28 03:46:20.900622+07
34	3	34	POS-3-34	200	2025-09-28 03:46:20.901032+07	2025-09-28 03:46:20.900622+07
35	3	35	POS-3-35	200	2025-09-28 03:46:20.90138+07	2025-09-28 03:46:20.901134+07
36	3	36	POS-3-36	200	2025-09-28 03:46:20.901702+07	2025-09-28 03:46:20.901645+07
37	3	37	POS-3-37	200	2025-09-28 03:46:20.90201+07	2025-09-28 03:46:20.901645+07
38	3	38	POS-3-38	200	2025-09-28 03:46:20.902322+07	2025-09-28 03:46:20.902155+07
39	3	39	POS-3-39	200	2025-09-28 03:46:20.90269+07	2025-09-28 03:46:20.90267+07
40	3	40	POS-3-40	200	2025-09-28 03:46:20.903059+07	2025-09-28 03:46:20.90267+07
41	3	41	POS-3-41	200	2025-09-28 03:46:20.903385+07	2025-09-28 03:46:20.903181+07
42	3	42	POS-3-42	200	2025-09-28 03:46:20.903783+07	2025-09-28 03:46:20.903695+07
43	3	43	POS-3-43	200	2025-09-28 03:46:20.904121+07	2025-09-28 03:46:20.903695+07
44	3	44	POS-3-44	200	2025-09-28 03:46:20.904485+07	2025-09-28 03:46:20.90421+07
45	3	45	POS-3-45	200	2025-09-28 03:46:20.905049+07	2025-09-28 03:46:20.904723+07
46	10	46	POS-10-46	200	2025-09-28 03:46:20.905407+07	2025-09-28 03:46:20.905236+07
47	10	47	POS-10-47	200	2025-09-28 03:46:20.905709+07	2025-09-28 03:46:20.905236+07
48	10	48	POS-10-48	200	2025-09-28 03:46:20.906+07	2025-09-28 03:46:20.905748+07
49	10	49	POS-10-49	200	2025-09-28 03:46:20.906324+07	2025-09-28 03:46:20.906258+07
50	10	50	POS-10-50	200	2025-09-28 03:46:20.906635+07	2025-09-28 03:46:20.906258+07
51	10	51	POS-10-51	200	2025-09-28 03:46:20.906988+07	2025-09-28 03:46:20.906771+07
52	10	52	POS-10-52	200	2025-09-28 03:46:20.907315+07	2025-09-28 03:46:20.907284+07
53	10	53	POS-10-53	200	2025-09-28 03:46:20.907636+07	2025-09-28 03:46:20.907284+07
54	10	54	POS-10-54	200	2025-09-28 03:46:20.908049+07	2025-09-28 03:46:20.907803+07
55	10	55	POS-10-55	200	2025-09-28 03:46:20.908413+07	2025-09-28 03:46:20.908326+07
56	4	56	POS-4-56	200	2025-09-28 03:46:20.909013+07	2025-09-28 03:46:20.908874+07
57	4	57	POS-4-57	200	2025-09-28 03:46:20.909413+07	2025-09-28 03:46:20.909389+07
58	4	58	POS-4-58	200	2025-09-28 03:46:20.909865+07	2025-09-28 03:46:20.909389+07
59	4	59	POS-4-59	200	2025-09-28 03:46:20.910363+07	2025-09-28 03:46:20.909901+07
60	4	60	POS-4-60	200	2025-09-28 03:46:20.910678+07	2025-09-28 03:46:20.910412+07
61	4	61	POS-4-61	200	2025-09-28 03:46:20.910992+07	2025-09-28 03:46:20.910922+07
62	4	62	POS-4-62	200	2025-09-28 03:46:20.911279+07	2025-09-28 03:46:20.910922+07
63	4	63	POS-4-63	200	2025-09-28 03:46:20.911545+07	2025-09-28 03:46:20.911429+07
64	7	64	POS-7-64	200	2025-09-28 03:46:20.911803+07	2025-09-28 03:46:20.911429+07
65	7	65	POS-7-65	200	2025-09-28 03:46:20.912088+07	2025-09-28 03:46:20.911938+07
66	7	66	POS-7-66	200	2025-09-28 03:46:20.912357+07	2025-09-28 03:46:20.911938+07
67	7	67	POS-7-67	200	2025-09-28 03:46:20.91261+07	2025-09-28 03:46:20.912446+07
68	7	68	POS-7-68	200	2025-09-28 03:46:20.912862+07	2025-09-28 03:46:20.912446+07
69	5	79	POS-5-79	200	2025-09-28 03:46:20.914454+07	2025-09-28 03:46:20.913977+07
70	5	80	POS-5-80	200	2025-09-28 03:46:20.914858+07	2025-09-28 03:46:20.914489+07
71	5	81	POS-5-81	200	2025-09-28 03:46:20.915266+07	2025-09-28 03:46:20.915002+07
72	5	82	POS-5-82	200	2025-09-28 03:46:20.915623+07	2025-09-28 03:46:20.915515+07
73	5	83	POS-5-83	200	2025-09-28 03:46:20.915895+07	2025-09-28 03:46:20.915515+07
74	5	84	POS-5-84	200	2025-09-28 03:46:20.916205+07	2025-09-28 03:46:20.916026+07
75	5	85	POS-5-85	200	2025-09-28 03:46:20.916528+07	2025-09-28 03:46:20.916538+07
76	5	86	POS-5-86	200	2025-09-28 03:46:20.916839+07	2025-09-28 03:46:20.916538+07
77	8	91	POS-8-91	200	2025-09-28 03:46:20.917403+07	2025-09-28 03:46:20.91706+07
78	8	92	POS-8-92	200	2025-09-28 03:46:20.917705+07	2025-09-28 03:46:20.917574+07
79	8	93	POS-8-93	200	2025-09-28 03:46:20.917976+07	2025-09-28 03:46:20.917574+07
80	8	94	POS-8-94	200	2025-09-28 03:46:20.918226+07	2025-09-28 03:46:20.918087+07
81	9	105	POS-9-105	200	2025-09-28 03:46:20.919163+07	2025-09-28 03:46:20.91917+07
82	9	106	POS-9-106	200	2025-09-28 03:46:20.919559+07	2025-09-28 03:46:20.91917+07
83	9	107	POS-9-107	200	2025-09-28 03:46:20.919918+07	2025-09-28 03:46:20.919688+07
\.


--
-- TOC entry 5362 (class 0 OID 36962)
-- Dependencies: 257
-- Data for Name: stock_transfers; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.stock_transfers (transfer_id, transfer_code, product_id, from_warehouse_id, to_shelf_id, quantity, transfer_date, employee_id, batch_code, expiry_date, import_price, selling_price, notes, created_at) FROM stdin;
1	ST2025090001	49	1	10	47	2025-09-02 07:00:00+07	5	BATCH202509010049	2025-12-01	450000.00	750000.00	\N	2025-09-28 03:46:20.921424+07
2	ST2025090002	31	1	3	186	2025-09-02 07:00:00+07	5	BATCH202509010031	2025-12-01	200000.00	350000.00	\N	2025-09-28 03:46:20.92822+07
3	ST2025090003	34	1	3	193	2025-09-02 07:00:00+07	5	BATCH202509010034	2025-12-01	150000.00	250000.00	\N	2025-09-28 03:46:20.929647+07
4	ST2025090004	63	1	4	137	2025-09-02 07:00:00+07	5	BATCH202509010063	2025-12-01	15000.00	25000.00	\N	2025-09-28 03:46:20.931203+07
5	ST2025090005	85	1	5	96	2025-09-02 07:00:00+07	5	BATCH202509010085	2025-12-01	120000.00	180000.00	\N	2025-09-28 03:46:20.932673+07
6	ST2025090006	50	1	10	178	2025-09-02 07:00:00+07	5	BATCH202509010050	2025-12-01	1200000.00	1950000.00	\N	2025-09-28 03:46:20.934062+07
7	ST2025090007	93	1	8	192	2025-09-02 07:00:00+07	5	BATCH202509010093	2025-12-01	120000.00	190000.00	\N	2025-09-28 03:46:20.935385+07
8	ST2025090008	66	1	7	114	2025-09-02 07:00:00+07	5	BATCH202509010066	2025-12-01	12000.00	20000.00	\N	2025-09-28 03:46:20.936468+07
9	ST2025090009	106	1	9	111	2025-09-02 07:00:00+07	5	BATCH202509010106	2025-12-01	45000.00	80000.00	\N	2025-09-28 03:46:20.937975+07
11	ST2025090011	42	1	3	128	2025-09-02 07:00:00+07	5	BATCH202509010042	2025-12-01	30000.00	55000.00	\N	2025-09-28 03:46:20.939655+07
12	ST2025090012	64	1	7	71	2025-09-02 07:00:00+07	5	BATCH202509010064	2025-12-01	15000.00	25000.00	\N	2025-09-28 03:46:20.940546+07
13	ST2025090013	48	1	10	41	2025-09-02 07:00:00+07	5	BATCH202509010048	2025-12-01	180000.00	300000.00	\N	2025-09-28 03:46:20.942094+07
14	ST2025090014	36	1	3	70	2025-09-02 07:00:00+07	5	BATCH202509010036	2025-12-01	350000.00	580000.00	\N	2025-09-28 03:46:20.943078+07
16	ST2025090016	91	1	8	166	2025-09-02 07:00:00+07	5	BATCH202509010091	2025-12-01	65000.00	110000.00	\N	2025-09-28 03:46:20.944613+07
17	ST2025090017	81	1	5	148	2025-09-02 07:00:00+07	5	BATCH202509010081	2025-12-01	175000.00	250000.00	\N	2025-09-28 03:46:20.945738+07
18	ST2025090018	14	1	1	151	2025-09-02 07:00:00+07	5	BATCH202509010014	2025-12-01	150000.00	250000.00	\N	2025-09-28 03:46:20.946604+07
19	ST2025090019	23	1	2	156	2025-09-02 07:00:00+07	5	BATCH202509010023	2025-12-01	65000.00	110000.00	\N	2025-09-28 03:46:20.947773+07
20	ST2025090020	29	1	2	34	2025-09-02 07:00:00+07	5	BATCH202509010029	2025-12-01	300000.00	480000.00	\N	2025-09-28 03:46:20.948789+07
21	ST2025090021	35	1	3	65	2025-09-02 07:00:00+07	5	BATCH202509010035	2025-12-01	80000.00	130000.00	\N	2025-09-28 03:46:20.949686+07
22	ST2025090022	43	1	3	52	2025-09-02 07:00:00+07	5	BATCH202509010043	2025-12-01	15000.00	30000.00	\N	2025-09-28 03:46:20.950573+07
23	ST2025090023	57	1	4	130	2025-09-02 07:00:00+07	5	BATCH202509010057	2025-12-01	85000.00	115000.00	\N	2025-09-28 03:46:20.951362+07
24	ST2025090024	68	1	7	47	2025-09-02 07:00:00+07	5	BATCH202509010068	2025-12-01	25000.00	40000.00	\N	2025-09-28 03:46:20.952165+07
25	ST2025090025	24	1	2	187	2025-09-02 07:00:00+07	5	BATCH202509010024	2025-12-01	25000.00	45000.00	\N	2025-09-28 03:46:20.953313+07
26	ST2025090026	26	1	2	117	2025-09-02 07:00:00+07	5	BATCH202509010026	2025-12-01	120000.00	200000.00	\N	2025-09-28 03:46:20.954375+07
27	ST2025090027	40	1	3	117	2025-09-02 07:00:00+07	5	BATCH202509010040	2025-12-01	90000.00	150000.00	\N	2025-09-28 03:46:20.955228+07
28	ST2025090028	45	1	3	111	2025-09-02 07:00:00+07	5	BATCH202509010045	2025-12-01	800000.00	1300000.00	\N	2025-09-28 03:46:20.956007+07
29	ST2025090029	62	1	4	128	2025-09-02 07:00:00+07	5	BATCH202509010062	2025-12-01	22000.00	35000.00	\N	2025-09-28 03:46:20.956784+07
30	ST2025090030	10	1	1	73	2025-09-02 07:00:00+07	5	BATCH202509010010	2025-12-01	12000.00	18000.00	\N	2025-09-28 03:46:20.958004+07
31	ST2025090031	17	1	2	49	2025-09-02 07:00:00+07	5	BATCH202509010017	2025-12-01	350000.00	550000.00	\N	2025-09-28 03:46:20.958961+07
32	ST2025090032	27	1	2	131	2025-09-02 07:00:00+07	5	BATCH202509010027	2025-12-01	55000.00	90000.00	\N	2025-09-28 03:46:20.960105+07
33	ST2025090033	59	1	4	156	2025-09-02 07:00:00+07	5	BATCH202509010059	2025-12-01	8000.00	12000.00	\N	2025-09-28 03:46:20.960903+07
35	ST2025090035	61	1	4	198	2025-09-02 07:00:00+07	5	BATCH202509010061	2025-12-01	45000.00	70000.00	\N	2025-09-28 03:46:20.962356+07
36	ST2025090036	7	1	1	55	2025-09-02 07:00:00+07	5	BATCH202509010007	2025-12-01	45000.00	65000.00	\N	2025-09-28 03:46:20.963232+07
37	ST2025090037	11	1	1	33	2025-09-02 07:00:00+07	5	BATCH202509010011	2025-12-01	8000.00	12000.00	\N	2025-09-28 03:46:20.964501+07
38	ST2025090038	105	1	9	193	2025-09-02 07:00:00+07	5	BATCH202509010105	2025-12-01	80000.00	150000.00	\N	2025-09-28 03:46:20.965662+07
39	ST2025090039	86	1	5	99	2025-09-02 07:00:00+07	5	BATCH202509010086	2025-12-01	90000.00	135000.00	\N	2025-09-28 03:46:20.966811+07
40	ST2025090040	4	1	1	87	2025-09-02 07:00:00+07	5	BATCH202509010004	2025-12-01	5000.00	8000.00	\N	2025-09-28 03:46:20.967683+07
41	ST2025090041	12	1	1	114	2025-09-02 07:00:00+07	5	BATCH202509010012	2025-12-01	35000.00	55000.00	\N	2025-09-28 03:46:20.968598+07
43	ST2025090043	20	1	2	48	2025-09-02 07:00:00+07	5	BATCH202509010020	2025-12-01	35000.00	60000.00	\N	2025-09-28 03:46:20.970566+07
44	ST2025090044	51	1	10	132	2025-09-02 07:00:00+07	5	BATCH202509010051	2025-12-01	650000.00	1100000.00	\N	2025-09-28 03:46:20.971574+07
45	ST2025090045	33	1	3	163	2025-09-02 07:00:00+07	5	BATCH202509010033	2025-12-01	25000.00	50000.00	\N	2025-09-28 03:46:20.972432+07
46	ST2025090046	56	1	4	64	2025-09-02 07:00:00+07	5	BATCH202509010056	2025-12-01	120000.00	180000.00	\N	2025-09-28 03:46:20.973247+07
47	ST2025090047	5	1	1	130	2025-09-02 07:00:00+07	5	BATCH202509010005	2025-12-01	1500.00	3000.00	\N	2025-09-28 03:46:20.974251+07
48	ST2025090048	38	1	3	134	2025-09-02 07:00:00+07	5	BATCH202509010038	2025-12-01	35000.00	60000.00	\N	2025-09-28 03:46:20.975588+07
49	ST2025090049	58	1	4	160	2025-09-02 07:00:00+07	5	BATCH202509010058	2025-12-01	35000.00	52000.00	\N	2025-09-28 03:46:20.97654+07
50	ST2025090050	3	1	1	185	2025-09-02 07:00:00+07	5	BATCH202509010003	2025-12-01	2000.00	3500.00	\N	2025-09-28 03:46:20.977554+07
51	ST2025090051	41	1	3	74	2025-09-02 07:00:00+07	5	BATCH202509010041	2025-12-01	45000.00	75000.00	\N	2025-09-28 03:46:20.978702+07
52	ST2025090052	67	1	7	166	2025-09-02 07:00:00+07	5	BATCH202509010067	2025-12-01	35000.00	55000.00	\N	2025-09-28 03:46:20.979842+07
53	ST2025090053	25	1	2	91	2025-09-02 07:00:00+07	5	BATCH202509010025	2025-12-01	90000.00	150000.00	\N	2025-09-28 03:46:20.981653+07
54	ST2025090054	28	1	2	52	2025-09-02 07:00:00+07	5	BATCH202509010028	2025-12-01	85000.00	140000.00	\N	2025-09-28 03:46:20.982934+07
55	ST2025090055	52	1	10	56	2025-09-02 07:00:00+07	5	BATCH202509010052	2025-12-01	320000.00	520000.00	\N	2025-09-28 03:46:20.983798+07
56	ST2025090056	54	1	10	156	2025-09-02 07:00:00+07	5	BATCH202509010054	2025-12-01	95000.00	160000.00	\N	2025-09-28 03:46:20.984918+07
57	ST2025090057	55	1	10	153	2025-09-02 07:00:00+07	5	BATCH202509010055	2025-12-01	85000.00	140000.00	\N	2025-09-28 03:46:20.986439+07
60	ST2025090060	84	1	5	45	2025-09-02 07:00:00+07	5	BATCH202509010084	2025-12-01	280000.00	400000.00	\N	2025-09-28 03:46:20.989199+07
61	ST2025090061	32	1	3	166	2025-09-02 07:00:00+07	5	BATCH202509010032	2025-12-01	180000.00	300000.00	\N	2025-09-28 03:46:20.99003+07
62	ST2025090062	44	1	3	190	2025-09-02 07:00:00+07	5	BATCH202509010044	2025-12-01	12000.00	20000.00	\N	2025-09-28 03:46:20.990773+07
63	ST2025090063	65	1	7	141	2025-09-02 07:00:00+07	5	BATCH202509010065	2025-12-01	18000.00	28000.00	\N	2025-09-28 03:46:20.991701+07
64	ST2025090064	1	1	1	174	2025-09-02 07:00:00+07	5	BATCH202509010001	2025-12-01	3000.00	5000.00	\N	2025-09-28 03:46:20.993256+07
65	ST2025090065	6	1	1	155	2025-09-02 07:00:00+07	5	BATCH202509010006	2025-12-01	15000.00	25000.00	\N	2025-09-28 03:46:20.994004+07
66	ST2025090066	9	1	1	195	2025-09-02 07:00:00+07	5	BATCH202509010009	2025-12-01	3000.00	5000.00	\N	2025-09-28 03:46:20.994726+07
67	ST2025090067	21	1	2	51	2025-09-02 07:00:00+07	5	BATCH202509010021	2025-12-01	180000.00	300000.00	\N	2025-09-28 03:46:20.995381+07
68	ST2025090068	46	1	10	123	2025-09-02 07:00:00+07	5	BATCH202509010046	2025-12-01	380000.00	650000.00	\N	2025-09-28 03:46:20.996017+07
69	ST2025090069	80	1	5	96	2025-09-02 07:00:00+07	5	BATCH202509010080	2025-12-01	180000.00	260000.00	\N	2025-09-28 03:46:20.997483+07
70	ST2025090070	8	1	1	143	2025-09-02 07:00:00+07	5	BATCH202509010008	2025-12-01	8000.00	12000.00	\N	2025-09-28 03:46:20.998528+07
71	ST2025090071	107	1	9	187	2025-09-02 07:00:00+07	5	BATCH202509010107	2025-12-01	150000.00	280000.00	\N	2025-09-28 03:46:20.999438+07
72	ST2025090072	18	1	2	161	2025-09-02 07:00:00+07	5	BATCH202509010018	2025-12-01	45000.00	75000.00	\N	2025-09-28 03:46:21.000157+07
73	ST2025090073	19	1	2	41	2025-09-02 07:00:00+07	5	BATCH202509010019	2025-12-01	120000.00	200000.00	\N	2025-09-28 03:46:21.001617+07
74	ST2025090074	22	1	2	56	2025-09-02 07:00:00+07	5	BATCH202509010022	2025-12-01	80000.00	130000.00	\N	2025-09-28 03:46:21.003449+07
75	ST2025090075	47	1	10	38	2025-09-02 07:00:00+07	5	BATCH202509010047	2025-12-01	250000.00	420000.00	\N	2025-09-28 03:46:21.005839+07
76	ST2025090076	82	1	5	64	2025-09-02 07:00:00+07	5	BATCH202509010082	2025-12-01	200000.00	290000.00	\N	2025-09-28 03:46:21.008383+07
77	ST2025090077	16	1	2	93	2025-09-02 07:00:00+07	5	BATCH202509010016	2025-12-01	150000.00	250000.00	\N	2025-09-28 03:46:21.009692+07
78	ST2025090078	53	1	10	128	2025-09-02 07:00:00+07	5	BATCH202509010053	2025-12-01	280000.00	450000.00	\N	2025-09-28 03:46:21.010731+07
79	ST2025090079	92	1	8	130	2025-09-02 07:00:00+07	5	BATCH202509010092	2025-12-01	180000.00	280000.00	\N	2025-09-28 03:46:21.011685+07
80	ST2025090080	79	1	5	181	2025-09-02 07:00:00+07	5	BATCH202509010079	2025-12-01	80000.00	120000.00	\N	2025-09-28 03:46:21.012618+07
81	ST2025090081	83	1	5	59	2025-09-02 07:00:00+07	5	BATCH202509010083	2025-12-01	180000.00	260000.00	\N	2025-09-28 03:46:21.013538+07
82	ST2025090082	2	1	1	155	2025-09-02 07:00:00+07	5	BATCH202509010002	2025-12-01	8000.00	12000.00	\N	2025-09-28 03:46:21.015025+07
83	ST2025090083	15	1	1	157	2025-09-02 07:00:00+07	5	BATCH202509010015	2025-12-01	280000.00	450000.00	\N	2025-09-28 03:46:21.01609+07
84	ST2025090084	17	1	2	50	2025-09-08 07:00:00+07	5	BATCH202509010017	2025-12-01	350000.00	550000.00	\N	2025-09-28 03:46:21.310916+07
85	ST2025090085	84	1	5	50	2025-09-15 07:00:00+07	5	BATCH202509010084	2025-12-01	280000.00	400000.00	\N	2025-09-28 03:46:21.643107+07
86	ST2025090086	19	1	2	50	2025-09-15 07:00:00+07	5	BATCH202509010019	2025-12-01	120000.00	200000.00	\N	2025-09-28 03:46:21.64485+07
87	ST2025090087	83	1	5	50	2025-09-15 07:00:00+07	5	BATCH202509010083	2025-12-01	180000.00	260000.00	\N	2025-09-28 03:46:21.645986+07
88	ST2025090088	29	1	2	50	2025-09-15 07:00:00+07	5	BATCH202509010029	2025-12-01	300000.00	480000.00	\N	2025-09-28 03:46:21.647257+07
89	ST2025090089	20	1	2	50	2025-09-15 07:00:00+07	5	BATCH202509010020	2025-12-01	35000.00	60000.00	\N	2025-09-28 03:46:21.64845+07
90	ST2025090090	68	1	7	50	2025-09-15 07:00:00+07	5	BATCH202509010068	2025-12-01	25000.00	40000.00	\N	2025-09-28 03:46:21.649709+07
91	ST2025090091	11	1	1	50	2025-09-15 07:00:00+07	5	BATCH202509010011	2025-12-01	8000.00	12000.00	\N	2025-09-28 03:46:21.650651+07
92	ST2025090092	35	1	3	50	2025-09-15 07:00:00+07	5	BATCH202509010035	2025-12-01	80000.00	130000.00	\N	2025-09-28 03:46:21.651441+07
93	ST2025090093	47	1	10	50	2025-09-15 07:00:00+07	5	BATCH202509010047	2025-12-01	250000.00	420000.00	\N	2025-09-28 03:46:21.652249+07
94	ST2025090094	82	1	5	50	2025-09-22 07:00:00+07	5	BATCH202509010082	2025-12-01	200000.00	290000.00	\N	2025-09-28 03:46:21.904809+07
95	ST2025090095	21	1	2	50	2025-09-22 07:00:00+07	5	BATCH202509010021	2025-12-01	180000.00	300000.00	\N	2025-09-28 03:46:21.905986+07
96	ST2025090096	22	1	2	50	2025-09-22 07:00:00+07	5	BATCH202509010022	2025-12-01	80000.00	130000.00	\N	2025-09-28 03:46:21.906876+07
97	ST2025090097	52	1	10	50	2025-09-22 07:00:00+07	5	BATCH202509010052	2025-12-01	320000.00	520000.00	\N	2025-09-28 03:46:21.907775+07
98	ST2025090098	36	1	3	50	2025-09-22 07:00:00+07	5	BATCH202509010036	2025-12-01	350000.00	580000.00	\N	2025-09-28 03:46:21.908932+07
99	ST2025090099	49	1	10	50	2025-09-22 07:00:00+07	5	BATCH202509010049	2025-12-01	450000.00	750000.00	\N	2025-09-28 03:46:21.90999+07
100	ST2025090100	28	1	2	50	2025-09-22 07:00:00+07	5	BATCH202509010028	2025-12-01	85000.00	140000.00	\N	2025-09-28 03:46:21.9109+07
\.


--
-- TOC entry 5326 (class 0 OID 36741)
-- Dependencies: 221
-- Data for Name: suppliers; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.suppliers (supplier_id, supplier_code, supplier_name, contact_person, phone, email, address, tax_code, bank_account, is_active, created_at, updated_at) FROM stdin;
1	SUP001	Công ty TNHH Thực phẩm Sài Gòn	Nguyễn Văn A	0901234567	contact@sgfood.vn	123 Nguyễn Văn Cừ, Q5, TP.HCM	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.786298+07
2	SUP002	Công ty CP Điện tử Việt Nam	Trần Thị B	0912345678	sales@vnelec.com	456 Lý Thường Kiệt, Q10, TP.HCM	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.786298+07
3	SUP003	Công ty TNHH Văn phòng phẩm Á Châu	Lê Văn C	0923456789	info@acoffice.vn	789 Cách Mạng Tháng 8, Q3, TP.HCM	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.786298+07
4	SUP004	Công ty CP Đồ gia dụng Minh Long	Phạm Thị D	0934567890	contact@minhlong.vn	321 Võ Văn Tần, Q3, TP.HCM	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.786298+07
5	SUP005	Công ty TNHH Nước giải khát Tân Hiệp Phát	Hoàng Văn E	0945678901	sales@thp.vn	654 Quốc lộ 1A, Bình Dương	\N	\N	t	2025-09-28 03:46:20.781594+07	2025-09-28 03:46:20.786298+07
\.


--
-- TOC entry 5328 (class 0 OID 36753)
-- Dependencies: 223
-- Data for Name: warehouse; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.warehouse (warehouse_id, warehouse_code, warehouse_name, location, manager_name, capacity, created_at) FROM stdin;
1	WH001	Kho chính	Tầng hầm B1	\N	10000	2025-09-28 03:46:20.781594+07
2	WH002	Kho phụ	Tầng hầm B2	\N	5000	2025-09-28 03:46:20.781594+07
\.


--
-- TOC entry 5344 (class 0 OID 36861)
-- Dependencies: 239
-- Data for Name: warehouse_inventory; Type: TABLE DATA; Schema: supermarket; Owner: postgres
--

COPY supermarket.warehouse_inventory (inventory_id, warehouse_id, product_id, batch_code, quantity, import_date, expiry_date, import_price, created_at, updated_at) FROM stdin;
15	1	30	BATCH202509010030	469	2025-09-01	2025-12-01	450000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.854436+07
32	1	37	BATCH202509010037	488	2025-09-01	2025-12-01	120000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.859059+07
34	1	39	BATCH202509010039	496	2025-09-01	2025-12-01	65000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.860084+07
42	1	94	BATCH202509010094	437	2025-09-01	2025-12-01	150000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.86267+07
43	1	95	BATCH202509010095	164	2025-09-01	2025-12-01	35000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.86267+07
44	1	96	BATCH202509010096	451	2025-09-01	2025-12-01	180000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.86267+07
49	1	60	BATCH202509010060	485	2025-09-01	2025-12-01	18000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.864717+07
58	1	69	BATCH202509010069	428	2025-09-01	2025-12-01	65000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.867275+07
59	1	70	BATCH202509010070	167	2025-09-01	2025-12-01	85000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.867793+07
60	1	71	BATCH202509010071	119	2025-09-01	2025-12-01	120000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.867793+07
61	1	72	BATCH202509010072	202	2025-09-01	2025-12-01	55000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.868312+07
62	1	73	BATCH202509010073	262	2025-09-01	2025-12-01	30000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.868312+07
63	1	74	BATCH202509010074	497	2025-09-01	2025-12-01	28000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.868312+07
64	1	75	BATCH202509010075	200	2025-09-01	2025-12-01	35000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.868821+07
67	1	98	BATCH202509010098	163	2025-09-01	2025-12-01	85000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.869845+07
68	1	99	BATCH202509010099	246	2025-09-01	2025-12-01	25000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.870356+07
69	1	76	BATCH202509010076	369	2025-09-01	2025-12-01	220000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:20.870868+07
70	1	77	BATCH202509010077	225	2025-09-01	2025-12-01	280000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:20.871378+07
26	1	31	BATCH202509010031	195	2025-09-01	2025-12-01	200000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.92822+07
29	1	34	BATCH202509010034	228	2025-09-01	2025-12-01	150000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.929647+07
52	1	63	BATCH202509010063	153	2025-09-01	2025-12-01	15000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.931203+07
20	1	50	BATCH202509010050	193	2025-09-01	2025-12-01	1200000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.934062+07
41	1	93	BATCH202509010093	219	2025-09-01	2025-12-01	120000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.935385+07
55	1	66	BATCH202509010066	192	2025-09-01	2025-12-01	12000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.936468+07
37	1	42	BATCH202509010042	207	2025-09-01	2025-12-01	30000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.939655+07
53	1	64	BATCH202509010064	139	2025-09-01	2025-12-01	15000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.940546+07
18	1	48	BATCH202509010048	84	2025-09-01	2025-12-01	180000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.942094+07
13	1	28	BATCH202509010028	11	2025-09-01	2025-12-01	85000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.9109+07
65	1	91	BATCH202509010091	250	2025-09-01	2025-12-01	65000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.944613+07
8	1	23	BATCH202509010023	185	2025-09-01	2025-12-01	65000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.947773+07
17	1	47	BATCH202509010047	40	2025-09-01	2025-12-01	250000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.652249+07
38	1	43	BATCH202509010043	88	2025-09-01	2025-12-01	15000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.950573+07
46	1	57	BATCH202509010057	145	2025-09-01	2025-12-01	85000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.951362+07
30	1	35	BATCH202509010035	61	2025-09-01	2025-12-01	80000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:21.651441+07
9	1	24	BATCH202509010024	257	2025-09-01	2025-12-01	25000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.953313+07
11	1	26	BATCH202509010026	224	2025-09-01	2025-12-01	120000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.954375+07
35	1	40	BATCH202509010040	188	2025-09-01	2025-12-01	90000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.955228+07
40	1	45	BATCH202509010045	142	2025-09-01	2025-12-01	800000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.956007+07
51	1	62	BATCH202509010062	152	2025-09-01	2025-12-01	22000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.956784+07
4	1	19	BATCH202509010019	18	2025-09-01	2025-12-01	120000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.64485+07
12	1	27	BATCH202509010027	290	2025-09-01	2025-12-01	55000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.960105+07
48	1	59	BATCH202509010059	160	2025-09-01	2025-12-01	8000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.960903+07
50	1	61	BATCH202509010061	227	2025-09-01	2025-12-01	45000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.962356+07
57	1	68	BATCH202509010068	15	2025-09-01	2025-12-01	25000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:21.649709+07
21	1	51	BATCH202509010051	231	2025-09-01	2025-12-01	650000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.971574+07
28	1	33	BATCH202509010033	168	2025-09-01	2025-12-01	25000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.972432+07
45	1	56	BATCH202509010056	119	2025-09-01	2025-12-01	120000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.973247+07
33	1	38	BATCH202509010038	157	2025-09-01	2025-12-01	35000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.975588+07
47	1	58	BATCH202509010058	334	2025-09-01	2025-12-01	35000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.97654+07
36	1	41	BATCH202509010041	95	2025-09-01	2025-12-01	45000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.978702+07
56	1	67	BATCH202509010067	219	2025-09-01	2025-12-01	35000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.979842+07
10	1	25	BATCH202509010025	167	2025-09-01	2025-12-01	90000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.981653+07
31	1	36	BATCH202509010036	69	2025-09-01	2025-12-01	350000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:21.908932+07
24	1	54	BATCH202509010054	237	2025-09-01	2025-12-01	95000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.984918+07
25	1	55	BATCH202509010055	337	2025-09-01	2025-12-01	85000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.986439+07
27	1	32	BATCH202509010032	214	2025-09-01	2025-12-01	180000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.99003+07
39	1	44	BATCH202509010044	294	2025-09-01	2025-12-01	12000.00	2025-09-28 03:46:20.857513+07	2025-09-28 03:46:20.990773+07
7	1	22	BATCH202509010022	24	2025-09-01	2025-12-01	80000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.906876+07
16	1	46	BATCH202509010046	161	2025-09-01	2025-12-01	380000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:20.996017+07
3	1	18	BATCH202509010018	219	2025-09-01	2025-12-01	45000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.000157+07
5	1	20	BATCH202509010020	9	2025-09-01	2025-12-01	35000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.64845+07
22	1	52	BATCH202509010052	68	2025-09-01	2025-12-01	320000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.907775+07
6	1	21	BATCH202509010021	21	2025-09-01	2025-12-01	180000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.905986+07
1	1	16	BATCH202509010016	161	2025-09-01	2025-12-01	150000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.009692+07
23	1	53	BATCH202509010053	213	2025-09-01	2025-12-01	280000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.010731+07
66	1	92	BATCH202509010092	195	2025-09-01	2025-12-01	180000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:21.011685+07
2	1	17	BATCH202509010017	40	2025-09-01	2025-12-01	350000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.310916+07
71	1	78	BATCH202509010078	295	2025-09-01	2025-12-01	120000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:20.871378+07
80	1	87	BATCH202509010087	435	2025-09-01	2025-12-01	85000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:20.874956+07
81	1	88	BATCH202509010088	132	2025-09-01	2025-12-01	140000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:20.875467+07
82	1	89	BATCH202509010089	417	2025-09-01	2025-12-01	150000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:20.875467+07
83	1	90	BATCH202509010090	279	2025-09-01	2025-12-01	160000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:20.875978+07
96	1	13	BATCH202509010013	457	2025-09-01	2025-12-01	5000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.879608+07
99	1	97	BATCH202509010097	383	2025-09-01	2025-12-01	250000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.881139+07
100	1	100	BATCH202509010100	331	2025-09-01	2025-12-01	55000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.881651+07
101	1	101	BATCH202509010101	174	2025-09-01	2025-12-01	200000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.881651+07
102	1	102	BATCH202509010102	259	2025-09-01	2025-12-01	120000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.882164+07
103	1	103	BATCH202509010103	239	2025-09-01	2025-12-01	180000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.882164+07
104	1	104	BATCH202509010104	469	2025-09-01	2025-12-01	120000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.882673+07
78	1	85	BATCH202509010085	165	2025-09-01	2025-12-01	120000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:20.932673+07
106	1	106	BATCH202509010106	212	2025-09-01	2025-12-01	45000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.937975+07
74	1	81	BATCH202509010081	321	2025-09-01	2025-12-01	175000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:20.945738+07
97	1	14	BATCH202509010014	189	2025-09-01	2025-12-01	150000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.946604+07
93	1	10	BATCH202509010010	151	2025-09-01	2025-12-01	12000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.958004+07
90	1	7	BATCH202509010007	61	2025-09-01	2025-12-01	45000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.963232+07
105	1	105	BATCH202509010105	258	2025-09-01	2025-12-01	80000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.965662+07
79	1	86	BATCH202509010086	116	2025-09-01	2025-12-01	90000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:20.966811+07
87	1	4	BATCH202509010004	196	2025-09-01	2025-12-01	5000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.967683+07
95	1	12	BATCH202509010012	158	2025-09-01	2025-12-01	35000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.968598+07
85	1	2	BATCH202509010002	219	2025-09-01	2025-12-01	8000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:21.015025+07
88	1	5	BATCH202509010005	199	2025-09-01	2025-12-01	1500.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.974251+07
86	1	3	BATCH202509010003	301	2025-09-01	2025-12-01	2000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.977554+07
54	1	65	BATCH202509010065	309	2025-09-01	2025-12-01	18000.00	2025-09-28 03:46:20.863607+07	2025-09-28 03:46:20.991701+07
84	1	1	BATCH202509010001	236	2025-09-01	2025-12-01	3000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.993256+07
89	1	6	BATCH202509010006	309	2025-09-01	2025-12-01	15000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.994004+07
92	1	9	BATCH202509010009	200	2025-09-01	2025-12-01	3000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.994726+07
73	1	80	BATCH202509010080	136	2025-09-01	2025-12-01	180000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:20.997483+07
91	1	8	BATCH202509010008	196	2025-09-01	2025-12-01	8000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.998528+07
107	1	107	BATCH202509010107	235	2025-09-01	2025-12-01	150000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:20.999438+07
72	1	79	BATCH202509010079	281	2025-09-01	2025-12-01	80000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:21.012618+07
98	1	15	BATCH202509010015	308	2025-09-01	2025-12-01	280000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:21.01609+07
108	1	17	BATCH202509140017	160	2025-09-16	2025-12-14	350000.00	2025-09-28 03:46:21.641287+07	2025-09-28 03:46:21.641389+07
77	1	84	BATCH202509010084	37	2025-09-01	2025-12-01	280000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:21.643107+07
76	1	83	BATCH202509010083	49	2025-09-01	2025-12-01	180000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:21.645986+07
14	1	29	BATCH202509010029	17	2025-09-01	2025-12-01	300000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.647257+07
94	1	11	BATCH202509010011	27	2025-09-01	2025-12-01	8000.00	2025-09-28 03:46:20.876586+07	2025-09-28 03:46:21.650651+07
75	1	82	BATCH202509010082	28	2025-09-01	2025-12-01	200000.00	2025-09-28 03:46:20.87102+07	2025-09-28 03:46:21.904809+07
19	1	49	BATCH202509010049	3	2025-09-01	2025-12-01	450000.00	2025-09-28 03:46:20.845113+07	2025-09-28 03:46:21.90999+07
\.


--
-- TOC entry 5421 (class 0 OID 0)
-- Dependencies: 258
-- Name: activity_logs_log_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.activity_logs_log_id_seq', 423, true);


--
-- TOC entry 5422 (class 0 OID 0)
-- Dependencies: 236
-- Name: customers_customer_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.customers_customer_id_seq', 200, true);


--
-- TOC entry 5423 (class 0 OID 0)
-- Dependencies: 230
-- Name: discount_rules_rule_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.discount_rules_rule_id_seq', 12, true);


--
-- TOC entry 5424 (class 0 OID 0)
-- Dependencies: 232
-- Name: display_shelves_shelf_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.display_shelves_shelf_id_seq', 10, true);


--
-- TOC entry 5425 (class 0 OID 0)
-- Dependencies: 246
-- Name: employee_work_hours_work_hour_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.employee_work_hours_work_hour_id_seq', 126, true);


--
-- TOC entry 5426 (class 0 OID 0)
-- Dependencies: 234
-- Name: employees_employee_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.employees_employee_id_seq', 6, true);


--
-- TOC entry 5427 (class 0 OID 0)
-- Dependencies: 226
-- Name: membership_levels_level_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.membership_levels_level_id_seq', 5, true);


--
-- TOC entry 5428 (class 0 OID 0)
-- Dependencies: 224
-- Name: positions_position_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.positions_position_id_seq', 6, true);


--
-- TOC entry 5429 (class 0 OID 0)
-- Dependencies: 218
-- Name: product_categories_category_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.product_categories_category_id_seq', 17, true);


--
-- TOC entry 5430 (class 0 OID 0)
-- Dependencies: 228
-- Name: products_product_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.products_product_id_seq', 107, true);


--
-- TOC entry 5431 (class 0 OID 0)
-- Dependencies: 254
-- Name: purchase_order_details_detail_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.purchase_order_details_detail_id_seq', 108, true);


--
-- TOC entry 5432 (class 0 OID 0)
-- Dependencies: 250
-- Name: purchase_orders_order_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.purchase_orders_order_id_seq', 6, true);


--
-- TOC entry 5433 (class 0 OID 0)
-- Dependencies: 252
-- Name: sales_invoice_details_detail_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.sales_invoice_details_detail_id_seq', 1204, true);


--
-- TOC entry 5434 (class 0 OID 0)
-- Dependencies: 248
-- Name: sales_invoices_invoice_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.sales_invoices_invoice_id_seq', 208, true);


--
-- TOC entry 5435 (class 0 OID 0)
-- Dependencies: 244
-- Name: shelf_batch_inventory_shelf_batch_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.shelf_batch_inventory_shelf_batch_id_seq', 77, true);


--
-- TOC entry 5436 (class 0 OID 0)
-- Dependencies: 242
-- Name: shelf_inventory_shelf_inventory_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.shelf_inventory_shelf_inventory_id_seq', 100, true);


--
-- TOC entry 5437 (class 0 OID 0)
-- Dependencies: 240
-- Name: shelf_layout_layout_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.shelf_layout_layout_id_seq', 83, true);


--
-- TOC entry 5438 (class 0 OID 0)
-- Dependencies: 256
-- Name: stock_transfers_transfer_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.stock_transfers_transfer_id_seq', 100, true);


--
-- TOC entry 5439 (class 0 OID 0)
-- Dependencies: 220
-- Name: suppliers_supplier_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.suppliers_supplier_id_seq', 5, true);


--
-- TOC entry 5440 (class 0 OID 0)
-- Dependencies: 238
-- Name: warehouse_inventory_inventory_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.warehouse_inventory_inventory_id_seq', 108, true);


--
-- TOC entry 5441 (class 0 OID 0)
-- Dependencies: 222
-- Name: warehouse_warehouse_id_seq; Type: SEQUENCE SET; Schema: supermarket; Owner: postgres
--

SELECT pg_catalog.setval('supermarket.warehouse_warehouse_id_seq', 2, true);


--
-- TOC entry 5091 (class 2606 OID 36993)
-- Name: activity_logs activity_logs_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.activity_logs
    ADD CONSTRAINT activity_logs_pkey PRIMARY KEY (log_id);


--
-- TOC entry 5028 (class 2606 OID 36848)
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (customer_id);


--
-- TOC entry 5011 (class 2606 OID 36808)
-- Name: discount_rules discount_rules_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.discount_rules
    ADD CONSTRAINT discount_rules_pkey PRIMARY KEY (rule_id);


--
-- TOC entry 5015 (class 2606 OID 36816)
-- Name: display_shelves display_shelves_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.display_shelves
    ADD CONSTRAINT display_shelves_pkey PRIMARY KEY (shelf_id);


--
-- TOC entry 5065 (class 2606 OID 36910)
-- Name: employee_work_hours employee_work_hours_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employee_work_hours
    ADD CONSTRAINT employee_work_hours_pkey PRIMARY KEY (work_hour_id);


--
-- TOC entry 5019 (class 2606 OID 36829)
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (employee_id);


--
-- TOC entry 4999 (class 2606 OID 36781)
-- Name: membership_levels membership_levels_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.membership_levels
    ADD CONSTRAINT membership_levels_pkey PRIMARY KEY (level_id);


--
-- TOC entry 4995 (class 2606 OID 36769)
-- Name: positions positions_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.positions
    ADD CONSTRAINT positions_pkey PRIMARY KEY (position_id);


--
-- TOC entry 4983 (class 2606 OID 36737)
-- Name: product_categories product_categories_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.product_categories
    ADD CONSTRAINT product_categories_pkey PRIMARY KEY (category_id);


--
-- TOC entry 5005 (class 2606 OID 36795)
-- Name: products products_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (product_id);


--
-- TOC entry 5084 (class 2606 OID 36960)
-- Name: purchase_order_details purchase_order_details_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_order_details
    ADD CONSTRAINT purchase_order_details_pkey PRIMARY KEY (detail_id);


--
-- TOC entry 5077 (class 2606 OID 36940)
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (order_id);


--
-- TOC entry 5082 (class 2606 OID 36952)
-- Name: sales_invoice_details sales_invoice_details_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoice_details
    ADD CONSTRAINT sales_invoice_details_pkey PRIMARY KEY (detail_id);


--
-- TOC entry 5073 (class 2606 OID 36926)
-- Name: sales_invoices sales_invoices_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoices
    ADD CONSTRAINT sales_invoices_pkey PRIMARY KEY (invoice_id);


--
-- TOC entry 5061 (class 2606 OID 36903)
-- Name: shelf_batch_inventory shelf_batch_inventory_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_batch_inventory
    ADD CONSTRAINT shelf_batch_inventory_pkey PRIMARY KEY (shelf_batch_id);


--
-- TOC entry 5053 (class 2606 OID 36892)
-- Name: shelf_inventory shelf_inventory_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_inventory
    ADD CONSTRAINT shelf_inventory_pkey PRIMARY KEY (shelf_inventory_id);


--
-- TOC entry 5045 (class 2606 OID 36878)
-- Name: shelf_layout shelf_layout_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_layout
    ADD CONSTRAINT shelf_layout_pkey PRIMARY KEY (layout_id);


--
-- TOC entry 5087 (class 2606 OID 36971)
-- Name: stock_transfers stock_transfers_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers
    ADD CONSTRAINT stock_transfers_pkey PRIMARY KEY (transfer_id);


--
-- TOC entry 4987 (class 2606 OID 36749)
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (supplier_id);


--
-- TOC entry 5032 (class 2606 OID 36850)
-- Name: customers uni_customers_customer_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.customers
    ADD CONSTRAINT uni_customers_customer_code UNIQUE (customer_code);


--
-- TOC entry 5034 (class 2606 OID 36854)
-- Name: customers uni_customers_membership_card_no; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.customers
    ADD CONSTRAINT uni_customers_membership_card_no UNIQUE (membership_card_no);


--
-- TOC entry 5036 (class 2606 OID 36852)
-- Name: customers uni_customers_phone; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.customers
    ADD CONSTRAINT uni_customers_phone UNIQUE (phone);


--
-- TOC entry 5017 (class 2606 OID 36818)
-- Name: display_shelves uni_display_shelves_shelf_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.display_shelves
    ADD CONSTRAINT uni_display_shelves_shelf_code UNIQUE (shelf_code);


--
-- TOC entry 5022 (class 2606 OID 36833)
-- Name: employees uni_employees_email; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employees
    ADD CONSTRAINT uni_employees_email UNIQUE (email);


--
-- TOC entry 5024 (class 2606 OID 36831)
-- Name: employees uni_employees_employee_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employees
    ADD CONSTRAINT uni_employees_employee_code UNIQUE (employee_code);


--
-- TOC entry 5026 (class 2606 OID 36835)
-- Name: employees uni_employees_id_card; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employees
    ADD CONSTRAINT uni_employees_id_card UNIQUE (id_card);


--
-- TOC entry 5001 (class 2606 OID 36783)
-- Name: membership_levels uni_membership_levels_level_name; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.membership_levels
    ADD CONSTRAINT uni_membership_levels_level_name UNIQUE (level_name);


--
-- TOC entry 4997 (class 2606 OID 36771)
-- Name: positions uni_positions_position_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.positions
    ADD CONSTRAINT uni_positions_position_code UNIQUE (position_code);


--
-- TOC entry 4985 (class 2606 OID 36739)
-- Name: product_categories uni_product_categories_category_name; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.product_categories
    ADD CONSTRAINT uni_product_categories_category_name UNIQUE (category_name);


--
-- TOC entry 5007 (class 2606 OID 36799)
-- Name: products uni_products_barcode; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.products
    ADD CONSTRAINT uni_products_barcode UNIQUE (barcode);


--
-- TOC entry 5009 (class 2606 OID 36797)
-- Name: products uni_products_product_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.products
    ADD CONSTRAINT uni_products_product_code UNIQUE (product_code);


--
-- TOC entry 5079 (class 2606 OID 36942)
-- Name: purchase_orders uni_purchase_orders_order_no; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_orders
    ADD CONSTRAINT uni_purchase_orders_order_no UNIQUE (order_no);


--
-- TOC entry 5075 (class 2606 OID 36928)
-- Name: sales_invoices uni_sales_invoices_invoice_no; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoices
    ADD CONSTRAINT uni_sales_invoices_invoice_no UNIQUE (invoice_no);


--
-- TOC entry 5089 (class 2606 OID 36973)
-- Name: stock_transfers uni_stock_transfers_transfer_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers
    ADD CONSTRAINT uni_stock_transfers_transfer_code UNIQUE (transfer_code);


--
-- TOC entry 4989 (class 2606 OID 36751)
-- Name: suppliers uni_suppliers_supplier_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.suppliers
    ADD CONSTRAINT uni_suppliers_supplier_code UNIQUE (supplier_code);


--
-- TOC entry 4991 (class 2606 OID 36760)
-- Name: warehouse uni_warehouse_warehouse_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse
    ADD CONSTRAINT uni_warehouse_warehouse_code UNIQUE (warehouse_code);


--
-- TOC entry 5041 (class 2606 OID 36995)
-- Name: warehouse_inventory unique_batch; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse_inventory
    ADD CONSTRAINT unique_batch UNIQUE (warehouse_id, product_id, batch_code);


--
-- TOC entry 5013 (class 2606 OID 37007)
-- Name: discount_rules unique_category_days; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.discount_rules
    ADD CONSTRAINT unique_category_days UNIQUE (category_id, days_before_expiry);


--
-- TOC entry 5067 (class 2606 OID 37005)
-- Name: employee_work_hours unique_employee_date; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employee_work_hours
    ADD CONSTRAINT unique_employee_date UNIQUE (employee_id, work_date);


--
-- TOC entry 5063 (class 2606 OID 37003)
-- Name: shelf_batch_inventory unique_shelf_batch; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_batch_inventory
    ADD CONSTRAINT unique_shelf_batch UNIQUE (shelf_id, product_id, batch_code);


--
-- TOC entry 5047 (class 2606 OID 36997)
-- Name: shelf_layout unique_shelf_position; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_layout
    ADD CONSTRAINT unique_shelf_position UNIQUE (shelf_id, position_code);


--
-- TOC entry 5049 (class 2606 OID 36999)
-- Name: shelf_layout unique_shelf_product; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_layout
    ADD CONSTRAINT unique_shelf_product UNIQUE (shelf_id, product_id);


--
-- TOC entry 5055 (class 2606 OID 37001)
-- Name: shelf_inventory unique_shelf_product_inv; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_inventory
    ADD CONSTRAINT unique_shelf_product_inv UNIQUE (shelf_id, product_id);


--
-- TOC entry 5043 (class 2606 OID 36870)
-- Name: warehouse_inventory warehouse_inventory_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse_inventory
    ADD CONSTRAINT warehouse_inventory_pkey PRIMARY KEY (inventory_id);


--
-- TOC entry 4993 (class 2606 OID 36758)
-- Name: warehouse warehouse_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse
    ADD CONSTRAINT warehouse_pkey PRIMARY KEY (warehouse_id);


--
-- TOC entry 5029 (class 1259 OID 37148)
-- Name: idx_customer_membership; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_customer_membership ON supermarket.customers USING btree (membership_level_id);


--
-- TOC entry 5030 (class 1259 OID 37149)
-- Name: idx_customer_spending; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_customer_spending ON supermarket.customers USING btree (total_spending);


--
-- TOC entry 5020 (class 1259 OID 37147)
-- Name: idx_employee_position; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_employee_position ON supermarket.employees USING btree (position_id);


--
-- TOC entry 5002 (class 1259 OID 37134)
-- Name: idx_products_category; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_products_category ON supermarket.products USING btree (category_id);


--
-- TOC entry 5003 (class 1259 OID 37135)
-- Name: idx_products_supplier; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_products_supplier ON supermarket.products USING btree (supplier_id);


--
-- TOC entry 5080 (class 1259 OID 37146)
-- Name: idx_sales_details_product; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_sales_details_product ON supermarket.sales_invoice_details USING btree (product_id);


--
-- TOC entry 5068 (class 1259 OID 37144)
-- Name: idx_sales_invoice_customer; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_sales_invoice_customer ON supermarket.sales_invoices USING btree (customer_id);


--
-- TOC entry 5069 (class 1259 OID 37143)
-- Name: idx_sales_invoice_date; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_sales_invoice_date ON supermarket.sales_invoices USING btree (invoice_date);


--
-- TOC entry 5070 (class 1259 OID 37244)
-- Name: idx_sales_invoice_date_range; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_sales_invoice_date_range ON supermarket.sales_invoices USING btree (invoice_date DESC);


--
-- TOC entry 5071 (class 1259 OID 37145)
-- Name: idx_sales_invoice_employee; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_sales_invoice_employee ON supermarket.sales_invoices USING btree (employee_id);


--
-- TOC entry 5056 (class 1259 OID 37142)
-- Name: idx_shelf_batch_code; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_shelf_batch_code ON supermarket.shelf_batch_inventory USING btree (batch_code);


--
-- TOC entry 5057 (class 1259 OID 37141)
-- Name: idx_shelf_batch_expiry; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_shelf_batch_expiry ON supermarket.shelf_batch_inventory USING btree (expiry_date);


--
-- TOC entry 5058 (class 1259 OID 37245)
-- Name: idx_shelf_batch_expiry_active; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_shelf_batch_expiry_active ON supermarket.shelf_batch_inventory USING btree (expiry_date) WHERE (quantity > 0);


--
-- TOC entry 5059 (class 1259 OID 37140)
-- Name: idx_shelf_batch_product; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_shelf_batch_product ON supermarket.shelf_batch_inventory USING btree (product_id);


--
-- TOC entry 5050 (class 1259 OID 37138)
-- Name: idx_shelf_inv_product; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_shelf_inv_product ON supermarket.shelf_inventory USING btree (product_id);


--
-- TOC entry 5051 (class 1259 OID 37139)
-- Name: idx_shelf_inv_quantity; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_shelf_inv_quantity ON supermarket.shelf_inventory USING btree (current_quantity);


--
-- TOC entry 5085 (class 1259 OID 36984)
-- Name: idx_stock_transfers_batch_code; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_stock_transfers_batch_code ON supermarket.stock_transfers USING btree (batch_code);


--
-- TOC entry 5037 (class 1259 OID 37246)
-- Name: idx_warehouse_batch_expiry; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_warehouse_batch_expiry ON supermarket.warehouse_inventory USING btree (expiry_date, batch_code);


--
-- TOC entry 5038 (class 1259 OID 37137)
-- Name: idx_warehouse_inv_expiry; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_warehouse_inv_expiry ON supermarket.warehouse_inventory USING btree (expiry_date);


--
-- TOC entry 5039 (class 1259 OID 37136)
-- Name: idx_warehouse_inv_product; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_warehouse_inv_product ON supermarket.warehouse_inventory USING btree (product_id);


--
-- TOC entry 5138 (class 2620 OID 37166)
-- Name: warehouse_inventory tr_apply_expiry_discounts; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_apply_expiry_discounts AFTER INSERT OR UPDATE OF expiry_date ON supermarket.warehouse_inventory FOR EACH ROW EXECUTE FUNCTION supermarket.apply_expiry_discounts();


--
-- TOC entry 5158 (class 2620 OID 37161)
-- Name: sales_invoice_details tr_calculate_detail_subtotal; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_calculate_detail_subtotal BEFORE INSERT OR UPDATE ON supermarket.sales_invoice_details FOR EACH ROW EXECUTE FUNCTION supermarket.calculate_detail_subtotal();


--
-- TOC entry 5139 (class 2620 OID 37157)
-- Name: warehouse_inventory tr_calculate_expiry_date; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_calculate_expiry_date BEFORE INSERT OR UPDATE ON supermarket.warehouse_inventory FOR EACH ROW EXECUTE FUNCTION supermarket.calculate_expiry_date();


--
-- TOC entry 5159 (class 2620 OID 37162)
-- Name: sales_invoice_details tr_calculate_invoice_totals; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_calculate_invoice_totals AFTER INSERT OR DELETE OR UPDATE ON supermarket.sales_invoice_details FOR EACH ROW EXECUTE FUNCTION supermarket.calculate_invoice_totals();


--
-- TOC entry 5162 (class 2620 OID 37163)
-- Name: purchase_order_details tr_calculate_purchase_detail_subtotal; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_calculate_purchase_detail_subtotal BEFORE INSERT OR UPDATE ON supermarket.purchase_order_details FOR EACH ROW EXECUTE FUNCTION supermarket.calculate_purchase_detail_subtotal();


--
-- TOC entry 5151 (class 2620 OID 37165)
-- Name: employee_work_hours tr_calculate_work_hours; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_calculate_work_hours BEFORE INSERT OR UPDATE ON supermarket.employee_work_hours FOR EACH ROW EXECUTE FUNCTION supermarket.calculate_work_hours();


--
-- TOC entry 5145 (class 2620 OID 37158)
-- Name: shelf_inventory tr_check_low_stock; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_check_low_stock AFTER UPDATE ON supermarket.shelf_inventory FOR EACH ROW EXECUTE FUNCTION supermarket.check_low_stock();


--
-- TOC entry 5135 (class 2620 OID 37160)
-- Name: customers tr_check_membership_upgrade; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_check_membership_upgrade AFTER UPDATE OF total_spending ON supermarket.customers FOR EACH ROW EXECUTE FUNCTION supermarket.check_membership_upgrade();


--
-- TOC entry 5150 (class 2620 OID 37171)
-- Name: shelf_batch_inventory tr_log_expiry_alert; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_log_expiry_alert AFTER INSERT OR UPDATE ON supermarket.shelf_batch_inventory FOR EACH ROW EXECUTE FUNCTION supermarket.log_expiry_alert();


--
-- TOC entry 5146 (class 2620 OID 37170)
-- Name: shelf_inventory tr_log_low_stock_alert; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_log_low_stock_alert AFTER UPDATE ON supermarket.shelf_inventory FOR EACH ROW EXECUTE FUNCTION supermarket.log_low_stock_alert();


--
-- TOC entry 5127 (class 2620 OID 37167)
-- Name: products tr_log_product_activity; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_log_product_activity AFTER INSERT OR DELETE OR UPDATE ON supermarket.products FOR EACH ROW EXECUTE FUNCTION supermarket.log_product_activity();


--
-- TOC entry 5153 (class 2620 OID 37169)
-- Name: sales_invoices tr_log_sales_activity; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_log_sales_activity AFTER INSERT ON supermarket.sales_invoices FOR EACH ROW EXECUTE FUNCTION supermarket.log_sales_activity();


--
-- TOC entry 5165 (class 2620 OID 37168)
-- Name: stock_transfers tr_log_stock_transfer_activity; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_log_stock_transfer_activity AFTER INSERT ON supermarket.stock_transfers FOR EACH ROW EXECUTE FUNCTION supermarket.log_stock_transfer_activity();


--
-- TOC entry 5160 (class 2620 OID 37156)
-- Name: sales_invoice_details tr_process_sales_stock_deduction; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_process_sales_stock_deduction AFTER INSERT ON supermarket.sales_invoice_details FOR EACH ROW EXECUTE FUNCTION supermarket.process_sales_stock_deduction();


--
-- TOC entry 5166 (class 2620 OID 37155)
-- Name: stock_transfers tr_process_stock_transfer; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_process_stock_transfer AFTER INSERT ON supermarket.stock_transfers FOR EACH ROW EXECUTE FUNCTION supermarket.process_stock_transfer();


--
-- TOC entry 5120 (class 2620 OID 37185)
-- Name: product_categories tr_set_created_timestamp_categories; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_categories BEFORE INSERT ON supermarket.product_categories FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5136 (class 2620 OID 37182)
-- Name: customers tr_set_created_timestamp_customers; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_customers BEFORE INSERT ON supermarket.customers FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5131 (class 2620 OID 37188)
-- Name: discount_rules tr_set_created_timestamp_discount_rules; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_discount_rules BEFORE INSERT ON supermarket.discount_rules FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5132 (class 2620 OID 37189)
-- Name: display_shelves tr_set_created_timestamp_display_shelves; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_display_shelves BEFORE INSERT ON supermarket.display_shelves FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5152 (class 2620 OID 37196)
-- Name: employee_work_hours tr_set_created_timestamp_employee_work_hours; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_employee_work_hours BEFORE INSERT ON supermarket.employee_work_hours FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5133 (class 2620 OID 37183)
-- Name: employees tr_set_created_timestamp_employees; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_employees BEFORE INSERT ON supermarket.employees FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5126 (class 2620 OID 37187)
-- Name: membership_levels tr_set_created_timestamp_membership_levels; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_membership_levels BEFORE INSERT ON supermarket.membership_levels FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5125 (class 2620 OID 37186)
-- Name: positions tr_set_created_timestamp_positions; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_positions BEFORE INSERT ON supermarket.positions FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5128 (class 2620 OID 37181)
-- Name: products tr_set_created_timestamp_products; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_products BEFORE INSERT ON supermarket.products FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5163 (class 2620 OID 37192)
-- Name: purchase_order_details tr_set_created_timestamp_purchase_order_details; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_purchase_order_details BEFORE INSERT ON supermarket.purchase_order_details FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5156 (class 2620 OID 37191)
-- Name: purchase_orders tr_set_created_timestamp_purchase_orders; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_purchase_orders BEFORE INSERT ON supermarket.purchase_orders FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5161 (class 2620 OID 37194)
-- Name: sales_invoice_details tr_set_created_timestamp_sales_invoice_details; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_sales_invoice_details BEFORE INSERT ON supermarket.sales_invoice_details FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5154 (class 2620 OID 37193)
-- Name: sales_invoices tr_set_created_timestamp_sales_invoices; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_sales_invoices BEFORE INSERT ON supermarket.sales_invoices FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5142 (class 2620 OID 37198)
-- Name: shelf_layout tr_set_created_timestamp_shelf_layout; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_shelf_layout BEFORE INSERT ON supermarket.shelf_layout FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5167 (class 2620 OID 37195)
-- Name: stock_transfers tr_set_created_timestamp_stock_transfers; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_stock_transfers BEFORE INSERT ON supermarket.stock_transfers FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5122 (class 2620 OID 37184)
-- Name: suppliers tr_set_created_timestamp_suppliers; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_suppliers BEFORE INSERT ON supermarket.suppliers FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5124 (class 2620 OID 37190)
-- Name: warehouse tr_set_created_timestamp_warehouse; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_warehouse BEFORE INSERT ON supermarket.warehouse FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5140 (class 2620 OID 37197)
-- Name: warehouse_inventory tr_set_created_timestamp_warehouse_inventory; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_set_created_timestamp_warehouse_inventory BEFORE INSERT ON supermarket.warehouse_inventory FOR EACH ROW EXECUTE FUNCTION supermarket.set_created_timestamp();


--
-- TOC entry 5155 (class 2620 OID 37159)
-- Name: sales_invoices tr_update_customer_metrics; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_update_customer_metrics BEFORE INSERT OR UPDATE ON supermarket.sales_invoices FOR EACH ROW EXECUTE FUNCTION supermarket.update_customer_metrics();


--
-- TOC entry 5164 (class 2620 OID 37164)
-- Name: purchase_order_details tr_update_purchase_order_total_insert; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_update_purchase_order_total_insert AFTER INSERT OR DELETE OR UPDATE ON supermarket.purchase_order_details FOR EACH ROW EXECUTE FUNCTION supermarket.update_purchase_order_total();


--
-- TOC entry 5121 (class 2620 OID 37176)
-- Name: product_categories tr_update_timestamp_categories; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_update_timestamp_categories BEFORE UPDATE ON supermarket.product_categories FOR EACH ROW EXECUTE FUNCTION supermarket.update_timestamp();


--
-- TOC entry 5137 (class 2620 OID 37173)
-- Name: customers tr_update_timestamp_customers; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_update_timestamp_customers BEFORE UPDATE ON supermarket.customers FOR EACH ROW EXECUTE FUNCTION supermarket.update_timestamp();


--
-- TOC entry 5134 (class 2620 OID 37174)
-- Name: employees tr_update_timestamp_employees; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_update_timestamp_employees BEFORE UPDATE ON supermarket.employees FOR EACH ROW EXECUTE FUNCTION supermarket.update_timestamp();


--
-- TOC entry 5129 (class 2620 OID 37172)
-- Name: products tr_update_timestamp_products; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_update_timestamp_products BEFORE UPDATE ON supermarket.products FOR EACH ROW EXECUTE FUNCTION supermarket.update_timestamp();


--
-- TOC entry 5157 (class 2620 OID 37177)
-- Name: purchase_orders tr_update_timestamp_purchase_orders; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_update_timestamp_purchase_orders BEFORE UPDATE ON supermarket.purchase_orders FOR EACH ROW EXECUTE FUNCTION supermarket.update_timestamp();


--
-- TOC entry 5147 (class 2620 OID 37179)
-- Name: shelf_inventory tr_update_timestamp_shelf_inventory; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_update_timestamp_shelf_inventory BEFORE UPDATE ON supermarket.shelf_inventory FOR EACH ROW EXECUTE FUNCTION supermarket.update_timestamp();


--
-- TOC entry 5143 (class 2620 OID 37180)
-- Name: shelf_layout tr_update_timestamp_shelf_layout; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_update_timestamp_shelf_layout BEFORE UPDATE ON supermarket.shelf_layout FOR EACH ROW EXECUTE FUNCTION supermarket.update_timestamp();


--
-- TOC entry 5123 (class 2620 OID 37175)
-- Name: suppliers tr_update_timestamp_suppliers; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_update_timestamp_suppliers BEFORE UPDATE ON supermarket.suppliers FOR EACH ROW EXECUTE FUNCTION supermarket.update_timestamp();


--
-- TOC entry 5141 (class 2620 OID 37178)
-- Name: warehouse_inventory tr_update_timestamp_warehouse_inventory; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_update_timestamp_warehouse_inventory BEFORE UPDATE ON supermarket.warehouse_inventory FOR EACH ROW EXECUTE FUNCTION supermarket.update_timestamp();


--
-- TOC entry 5130 (class 2620 OID 37150)
-- Name: products tr_validate_product_price; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_validate_product_price BEFORE INSERT OR UPDATE ON supermarket.products FOR EACH ROW EXECUTE FUNCTION supermarket.validate_product_price();


--
-- TOC entry 5148 (class 2620 OID 37151)
-- Name: shelf_inventory tr_validate_shelf_capacity; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_validate_shelf_capacity BEFORE INSERT OR UPDATE ON supermarket.shelf_inventory FOR EACH ROW EXECUTE FUNCTION supermarket.validate_shelf_capacity();


--
-- TOC entry 5149 (class 2620 OID 37153)
-- Name: shelf_inventory tr_validate_shelf_category_inventory; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_validate_shelf_category_inventory BEFORE INSERT OR UPDATE ON supermarket.shelf_inventory FOR EACH ROW EXECUTE FUNCTION supermarket.validate_shelf_category_consistency();


--
-- TOC entry 5144 (class 2620 OID 37152)
-- Name: shelf_layout tr_validate_shelf_category_layout; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_validate_shelf_category_layout BEFORE INSERT OR UPDATE ON supermarket.shelf_layout FOR EACH ROW EXECUTE FUNCTION supermarket.validate_shelf_category_consistency();


--
-- TOC entry 5168 (class 2620 OID 37154)
-- Name: stock_transfers tr_validate_stock_transfer; Type: TRIGGER; Schema: supermarket; Owner: postgres
--

CREATE TRIGGER tr_validate_stock_transfer BEFORE INSERT ON supermarket.stock_transfers FOR EACH ROW EXECUTE FUNCTION supermarket.validate_stock_transfer();


--
-- TOC entry 5097 (class 2606 OID 36855)
-- Name: customers fk_customers_membership_level; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.customers
    ADD CONSTRAINT fk_customers_membership_level FOREIGN KEY (membership_level_id) REFERENCES supermarket.membership_levels(level_id);


--
-- TOC entry 5094 (class 2606 OID 37018)
-- Name: discount_rules fk_discount_rules_category; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.discount_rules
    ADD CONSTRAINT fk_discount_rules_category FOREIGN KEY (category_id) REFERENCES supermarket.product_categories(category_id);


--
-- TOC entry 5095 (class 2606 OID 37023)
-- Name: display_shelves fk_display_shelves_category; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.display_shelves
    ADD CONSTRAINT fk_display_shelves_category FOREIGN KEY (category_id) REFERENCES supermarket.product_categories(category_id);


--
-- TOC entry 5107 (class 2606 OID 37073)
-- Name: employee_work_hours fk_employee_work_hours_employee; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employee_work_hours
    ADD CONSTRAINT fk_employee_work_hours_employee FOREIGN KEY (employee_id) REFERENCES supermarket.employees(employee_id);


--
-- TOC entry 5096 (class 2606 OID 37068)
-- Name: employees fk_employees_position; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employees
    ADD CONSTRAINT fk_employees_position FOREIGN KEY (position_id) REFERENCES supermarket.positions(position_id);


--
-- TOC entry 5092 (class 2606 OID 37008)
-- Name: products fk_products_category; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.products
    ADD CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES supermarket.product_categories(category_id);


--
-- TOC entry 5093 (class 2606 OID 37013)
-- Name: products fk_products_supplier; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.products
    ADD CONSTRAINT fk_products_supplier FOREIGN KEY (supplier_id) REFERENCES supermarket.suppliers(supplier_id);


--
-- TOC entry 5114 (class 2606 OID 37108)
-- Name: purchase_order_details fk_purchase_order_details_order; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_order_details
    ADD CONSTRAINT fk_purchase_order_details_order FOREIGN KEY (order_id) REFERENCES supermarket.purchase_orders(order_id);


--
-- TOC entry 5115 (class 2606 OID 37113)
-- Name: purchase_order_details fk_purchase_order_details_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_order_details
    ADD CONSTRAINT fk_purchase_order_details_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- TOC entry 5110 (class 2606 OID 37103)
-- Name: purchase_orders fk_purchase_orders_employee; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_orders
    ADD CONSTRAINT fk_purchase_orders_employee FOREIGN KEY (employee_id) REFERENCES supermarket.employees(employee_id);


--
-- TOC entry 5111 (class 2606 OID 37098)
-- Name: purchase_orders fk_purchase_orders_supplier; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_orders
    ADD CONSTRAINT fk_purchase_orders_supplier FOREIGN KEY (supplier_id) REFERENCES supermarket.suppliers(supplier_id);


--
-- TOC entry 5112 (class 2606 OID 37088)
-- Name: sales_invoice_details fk_sales_invoice_details_invoice; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoice_details
    ADD CONSTRAINT fk_sales_invoice_details_invoice FOREIGN KEY (invoice_id) REFERENCES supermarket.sales_invoices(invoice_id);


--
-- TOC entry 5113 (class 2606 OID 37093)
-- Name: sales_invoice_details fk_sales_invoice_details_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoice_details
    ADD CONSTRAINT fk_sales_invoice_details_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- TOC entry 5108 (class 2606 OID 37078)
-- Name: sales_invoices fk_sales_invoices_customer; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoices
    ADD CONSTRAINT fk_sales_invoices_customer FOREIGN KEY (customer_id) REFERENCES supermarket.customers(customer_id);


--
-- TOC entry 5109 (class 2606 OID 37083)
-- Name: sales_invoices fk_sales_invoices_employee; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoices
    ADD CONSTRAINT fk_sales_invoices_employee FOREIGN KEY (employee_id) REFERENCES supermarket.employees(employee_id);


--
-- TOC entry 5104 (class 2606 OID 37053)
-- Name: shelf_batch_inventory fk_shelf_batch_inventory_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_batch_inventory
    ADD CONSTRAINT fk_shelf_batch_inventory_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- TOC entry 5105 (class 2606 OID 37048)
-- Name: shelf_batch_inventory fk_shelf_batch_inventory_shelf; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_batch_inventory
    ADD CONSTRAINT fk_shelf_batch_inventory_shelf FOREIGN KEY (shelf_id) REFERENCES supermarket.display_shelves(shelf_id);


--
-- TOC entry 5106 (class 2606 OID 37128)
-- Name: shelf_batch_inventory fk_shelf_batch_inventory_shelf_inventory; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_batch_inventory
    ADD CONSTRAINT fk_shelf_batch_inventory_shelf_inventory FOREIGN KEY (shelf_id, product_id) REFERENCES supermarket.shelf_inventory(shelf_id, product_id);


--
-- TOC entry 5102 (class 2606 OID 37043)
-- Name: shelf_inventory fk_shelf_inventory_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_inventory
    ADD CONSTRAINT fk_shelf_inventory_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- TOC entry 5103 (class 2606 OID 37038)
-- Name: shelf_inventory fk_shelf_inventory_shelf; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_inventory
    ADD CONSTRAINT fk_shelf_inventory_shelf FOREIGN KEY (shelf_id) REFERENCES supermarket.display_shelves(shelf_id);


--
-- TOC entry 5100 (class 2606 OID 37033)
-- Name: shelf_layout fk_shelf_layout_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_layout
    ADD CONSTRAINT fk_shelf_layout_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- TOC entry 5101 (class 2606 OID 37028)
-- Name: shelf_layout fk_shelf_layout_shelf; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_layout
    ADD CONSTRAINT fk_shelf_layout_shelf FOREIGN KEY (shelf_id) REFERENCES supermarket.display_shelves(shelf_id);


--
-- TOC entry 5116 (class 2606 OID 37123)
-- Name: stock_transfers fk_stock_transfers_employee; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers
    ADD CONSTRAINT fk_stock_transfers_employee FOREIGN KEY (employee_id) REFERENCES supermarket.employees(employee_id);


--
-- TOC entry 5117 (class 2606 OID 36974)
-- Name: stock_transfers fk_stock_transfers_from_warehouse; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers
    ADD CONSTRAINT fk_stock_transfers_from_warehouse FOREIGN KEY (from_warehouse_id) REFERENCES supermarket.warehouse(warehouse_id);


--
-- TOC entry 5118 (class 2606 OID 37118)
-- Name: stock_transfers fk_stock_transfers_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers
    ADD CONSTRAINT fk_stock_transfers_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- TOC entry 5119 (class 2606 OID 36979)
-- Name: stock_transfers fk_stock_transfers_to_shelf; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers
    ADD CONSTRAINT fk_stock_transfers_to_shelf FOREIGN KEY (to_shelf_id) REFERENCES supermarket.display_shelves(shelf_id);


--
-- TOC entry 5098 (class 2606 OID 37063)
-- Name: warehouse_inventory fk_warehouse_inventory_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse_inventory
    ADD CONSTRAINT fk_warehouse_inventory_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- TOC entry 5099 (class 2606 OID 37058)
-- Name: warehouse_inventory fk_warehouse_inventory_warehouse; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse_inventory
    ADD CONSTRAINT fk_warehouse_inventory_warehouse FOREIGN KEY (warehouse_id) REFERENCES supermarket.warehouse(warehouse_id);


--
-- TOC entry 5370 (class 0 OID 0)
-- Dependencies: 259
-- Name: TABLE activity_logs; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.activity_logs TO PUBLIC;


--
-- TOC entry 5372 (class 0 OID 0)
-- Dependencies: 237
-- Name: TABLE customers; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.customers TO PUBLIC;


--
-- TOC entry 5374 (class 0 OID 0)
-- Dependencies: 231
-- Name: TABLE discount_rules; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.discount_rules TO PUBLIC;


--
-- TOC entry 5376 (class 0 OID 0)
-- Dependencies: 233
-- Name: TABLE display_shelves; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.display_shelves TO PUBLIC;


--
-- TOC entry 5378 (class 0 OID 0)
-- Dependencies: 247
-- Name: TABLE employee_work_hours; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.employee_work_hours TO PUBLIC;


--
-- TOC entry 5380 (class 0 OID 0)
-- Dependencies: 235
-- Name: TABLE employees; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.employees TO PUBLIC;


--
-- TOC entry 5382 (class 0 OID 0)
-- Dependencies: 227
-- Name: TABLE membership_levels; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.membership_levels TO PUBLIC;


--
-- TOC entry 5384 (class 0 OID 0)
-- Dependencies: 225
-- Name: TABLE positions; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.positions TO PUBLIC;


--
-- TOC entry 5386 (class 0 OID 0)
-- Dependencies: 219
-- Name: TABLE product_categories; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.product_categories TO PUBLIC;


--
-- TOC entry 5388 (class 0 OID 0)
-- Dependencies: 229
-- Name: TABLE products; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.products TO PUBLIC;


--
-- TOC entry 5390 (class 0 OID 0)
-- Dependencies: 255
-- Name: TABLE purchase_order_details; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.purchase_order_details TO PUBLIC;


--
-- TOC entry 5392 (class 0 OID 0)
-- Dependencies: 251
-- Name: TABLE purchase_orders; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.purchase_orders TO PUBLIC;


--
-- TOC entry 5394 (class 0 OID 0)
-- Dependencies: 253
-- Name: TABLE sales_invoice_details; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.sales_invoice_details TO PUBLIC;


--
-- TOC entry 5396 (class 0 OID 0)
-- Dependencies: 249
-- Name: TABLE sales_invoices; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.sales_invoices TO PUBLIC;


--
-- TOC entry 5398 (class 0 OID 0)
-- Dependencies: 245
-- Name: TABLE shelf_batch_inventory; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.shelf_batch_inventory TO PUBLIC;


--
-- TOC entry 5400 (class 0 OID 0)
-- Dependencies: 243
-- Name: TABLE shelf_inventory; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.shelf_inventory TO PUBLIC;


--
-- TOC entry 5402 (class 0 OID 0)
-- Dependencies: 241
-- Name: TABLE shelf_layout; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.shelf_layout TO PUBLIC;


--
-- TOC entry 5404 (class 0 OID 0)
-- Dependencies: 257
-- Name: TABLE stock_transfers; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.stock_transfers TO PUBLIC;


--
-- TOC entry 5406 (class 0 OID 0)
-- Dependencies: 221
-- Name: TABLE suppliers; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.suppliers TO PUBLIC;


--
-- TOC entry 5408 (class 0 OID 0)
-- Dependencies: 264
-- Name: TABLE v_expiring_products; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_expiring_products TO PUBLIC;


--
-- TOC entry 5409 (class 0 OID 0)
-- Dependencies: 239
-- Name: TABLE warehouse_inventory; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.warehouse_inventory TO PUBLIC;


--
-- TOC entry 5410 (class 0 OID 0)
-- Dependencies: 262
-- Name: TABLE v_low_shelf_products; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_low_shelf_products TO PUBLIC;


--
-- TOC entry 5411 (class 0 OID 0)
-- Dependencies: 261
-- Name: TABLE v_low_stock_products; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_low_stock_products TO PUBLIC;


--
-- TOC entry 5412 (class 0 OID 0)
-- Dependencies: 260
-- Name: TABLE v_product_overview; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_product_overview TO PUBLIC;


--
-- TOC entry 5413 (class 0 OID 0)
-- Dependencies: 265
-- Name: TABLE v_product_revenue; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_product_revenue TO PUBLIC;


--
-- TOC entry 5414 (class 0 OID 0)
-- Dependencies: 268
-- Name: TABLE v_shelf_status; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_shelf_status TO PUBLIC;


--
-- TOC entry 5415 (class 0 OID 0)
-- Dependencies: 266
-- Name: TABLE v_supplier_revenue; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_supplier_revenue TO PUBLIC;


--
-- TOC entry 5416 (class 0 OID 0)
-- Dependencies: 267
-- Name: TABLE v_vip_customers; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_vip_customers TO PUBLIC;


--
-- TOC entry 5417 (class 0 OID 0)
-- Dependencies: 263
-- Name: TABLE v_warehouse_empty_products; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_warehouse_empty_products TO PUBLIC;


--
-- TOC entry 5418 (class 0 OID 0)
-- Dependencies: 223
-- Name: TABLE warehouse; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.warehouse TO PUBLIC;


-- Completed on 2025-09-28 16:49:47

--
-- PostgreSQL database dump complete
--

\unrestrict LhHbHuD9pTkZ4A9eUbMRNvk4KBWbtlutniI6IEJBs3r4siZmq1Ny9XnoFX6Iuv6

