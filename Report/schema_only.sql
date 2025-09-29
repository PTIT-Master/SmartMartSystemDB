--
-- PostgreSQL database dump
--

\restrict u2bowLLK6CjDSi6FJNROU0MkNWfPecjvsr18OHkr09SaqcnVB1F7xSeIkw4UcoF

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

-- Started on 2025-09-28 21:09:39

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
-- TOC entry 5329 (class 0 OID 0)
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
-- TOC entry 5331 (class 0 OID 0)
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
-- TOC entry 5333 (class 0 OID 0)
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
-- TOC entry 5335 (class 0 OID 0)
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
-- TOC entry 5337 (class 0 OID 0)
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
-- TOC entry 5339 (class 0 OID 0)
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
-- TOC entry 5341 (class 0 OID 0)
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
-- TOC entry 5343 (class 0 OID 0)
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
-- TOC entry 5345 (class 0 OID 0)
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
-- TOC entry 5347 (class 0 OID 0)
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
-- TOC entry 5349 (class 0 OID 0)
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
-- TOC entry 5351 (class 0 OID 0)
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
-- TOC entry 5353 (class 0 OID 0)
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
-- TOC entry 5355 (class 0 OID 0)
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
-- TOC entry 5357 (class 0 OID 0)
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
-- TOC entry 5359 (class 0 OID 0)
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
-- TOC entry 5361 (class 0 OID 0)
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
-- TOC entry 5363 (class 0 OID 0)
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
-- TOC entry 5365 (class 0 OID 0)
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
-- TOC entry 5377 (class 0 OID 0)
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
-- TOC entry 5378 (class 0 OID 0)
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
-- TOC entry 5328 (class 0 OID 0)
-- Dependencies: 259
-- Name: TABLE activity_logs; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.activity_logs TO PUBLIC;


--
-- TOC entry 5330 (class 0 OID 0)
-- Dependencies: 237
-- Name: TABLE customers; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.customers TO PUBLIC;


--
-- TOC entry 5332 (class 0 OID 0)
-- Dependencies: 231
-- Name: TABLE discount_rules; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.discount_rules TO PUBLIC;


--
-- TOC entry 5334 (class 0 OID 0)
-- Dependencies: 233
-- Name: TABLE display_shelves; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.display_shelves TO PUBLIC;


--
-- TOC entry 5336 (class 0 OID 0)
-- Dependencies: 247
-- Name: TABLE employee_work_hours; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.employee_work_hours TO PUBLIC;


--
-- TOC entry 5338 (class 0 OID 0)
-- Dependencies: 235
-- Name: TABLE employees; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.employees TO PUBLIC;


--
-- TOC entry 5340 (class 0 OID 0)
-- Dependencies: 227
-- Name: TABLE membership_levels; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.membership_levels TO PUBLIC;


--
-- TOC entry 5342 (class 0 OID 0)
-- Dependencies: 225
-- Name: TABLE positions; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.positions TO PUBLIC;


--
-- TOC entry 5344 (class 0 OID 0)
-- Dependencies: 219
-- Name: TABLE product_categories; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.product_categories TO PUBLIC;


--
-- TOC entry 5346 (class 0 OID 0)
-- Dependencies: 229
-- Name: TABLE products; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.products TO PUBLIC;


--
-- TOC entry 5348 (class 0 OID 0)
-- Dependencies: 255
-- Name: TABLE purchase_order_details; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.purchase_order_details TO PUBLIC;


--
-- TOC entry 5350 (class 0 OID 0)
-- Dependencies: 251
-- Name: TABLE purchase_orders; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.purchase_orders TO PUBLIC;


--
-- TOC entry 5352 (class 0 OID 0)
-- Dependencies: 253
-- Name: TABLE sales_invoice_details; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.sales_invoice_details TO PUBLIC;


--
-- TOC entry 5354 (class 0 OID 0)
-- Dependencies: 249
-- Name: TABLE sales_invoices; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.sales_invoices TO PUBLIC;


--
-- TOC entry 5356 (class 0 OID 0)
-- Dependencies: 245
-- Name: TABLE shelf_batch_inventory; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.shelf_batch_inventory TO PUBLIC;


--
-- TOC entry 5358 (class 0 OID 0)
-- Dependencies: 243
-- Name: TABLE shelf_inventory; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.shelf_inventory TO PUBLIC;


--
-- TOC entry 5360 (class 0 OID 0)
-- Dependencies: 241
-- Name: TABLE shelf_layout; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.shelf_layout TO PUBLIC;


--
-- TOC entry 5362 (class 0 OID 0)
-- Dependencies: 257
-- Name: TABLE stock_transfers; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.stock_transfers TO PUBLIC;


--
-- TOC entry 5364 (class 0 OID 0)
-- Dependencies: 221
-- Name: TABLE suppliers; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.suppliers TO PUBLIC;


--
-- TOC entry 5366 (class 0 OID 0)
-- Dependencies: 264
-- Name: TABLE v_expiring_products; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_expiring_products TO PUBLIC;


--
-- TOC entry 5367 (class 0 OID 0)
-- Dependencies: 239
-- Name: TABLE warehouse_inventory; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.warehouse_inventory TO PUBLIC;


--
-- TOC entry 5368 (class 0 OID 0)
-- Dependencies: 262
-- Name: TABLE v_low_shelf_products; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_low_shelf_products TO PUBLIC;


--
-- TOC entry 5369 (class 0 OID 0)
-- Dependencies: 261
-- Name: TABLE v_low_stock_products; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_low_stock_products TO PUBLIC;


--
-- TOC entry 5370 (class 0 OID 0)
-- Dependencies: 260
-- Name: TABLE v_product_overview; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_product_overview TO PUBLIC;


--
-- TOC entry 5371 (class 0 OID 0)
-- Dependencies: 265
-- Name: TABLE v_product_revenue; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_product_revenue TO PUBLIC;


--
-- TOC entry 5372 (class 0 OID 0)
-- Dependencies: 268
-- Name: TABLE v_shelf_status; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_shelf_status TO PUBLIC;


--
-- TOC entry 5373 (class 0 OID 0)
-- Dependencies: 266
-- Name: TABLE v_supplier_revenue; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_supplier_revenue TO PUBLIC;


--
-- TOC entry 5374 (class 0 OID 0)
-- Dependencies: 267
-- Name: TABLE v_vip_customers; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_vip_customers TO PUBLIC;


--
-- TOC entry 5375 (class 0 OID 0)
-- Dependencies: 263
-- Name: TABLE v_warehouse_empty_products; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.v_warehouse_empty_products TO PUBLIC;


--
-- TOC entry 5376 (class 0 OID 0)
-- Dependencies: 223
-- Name: TABLE warehouse; Type: ACL; Schema: supermarket; Owner: postgres
--

GRANT SELECT ON TABLE supermarket.warehouse TO PUBLIC;


-- Completed on 2025-09-28 21:09:39

--
-- PostgreSQL database dump complete
--

\unrestrict u2bowLLK6CjDSi6FJNROU0MkNWfPecjvsr18OHkr09SaqcnVB1F7xSeIkw4UcoF

