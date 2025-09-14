-- ============================================================================
-- SUPERMARKET DATABASE TRIGGERS
-- ============================================================================
-- This file contains all trigger functions and triggers for the supermarket
-- management system to handle validation and data processing at DB level
-- ============================================================================

-- Set the schema
SET search_path TO supermarket;

-- ============================================================================
-- 1. VALIDATION TRIGGERS
-- ============================================================================

-- 1.1 Product Price Validation Trigger
-- Ensures selling price is always higher than import price
CREATE OR REPLACE FUNCTION validate_product_price()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.selling_price <= NEW.import_price THEN
        RAISE EXCEPTION '%', format('Selling price (%s) must be higher than import price (%s)', 
                        NEW.selling_price, NEW.import_price);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 1.2 Shelf Capacity Validation
-- Ensures current quantity doesn't exceed max quantity for shelf layout
CREATE OR REPLACE FUNCTION validate_shelf_capacity()
RETURNS TRIGGER AS $$
DECLARE
    max_qty INTEGER;
BEGIN
    -- Get maximum quantity allowed for this shelf-product combination
    SELECT sl.max_quantity INTO max_qty
    FROM shelf_layout sl
    WHERE sl.shelf_id = NEW.shelf_id AND sl.product_id = NEW.product_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', format('Product %s is not configured for shelf %s', NEW.product_id, NEW.shelf_id);
    END IF;
    
    IF NEW.current_quantity > max_qty THEN
        RAISE EXCEPTION '%', format('Quantity (%s) exceeds maximum allowed (%s) for shelf %s', 
                        NEW.current_quantity, max_qty, NEW.shelf_id);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 1.3 Category Consistency Validation
-- Ensures products on shelves match the shelf's designated category
CREATE OR REPLACE FUNCTION validate_shelf_category_consistency()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- 1.4 Stock Transfer Validation
-- Validates stock availability before allowing transfers
CREATE OR REPLACE FUNCTION validate_stock_transfer()
RETURNS TRIGGER AS $$
DECLARE
    available_qty INTEGER;
    shelf_max_qty INTEGER;
    shelf_current_qty INTEGER;
BEGIN
    -- Check warehouse stock availability
    SELECT COALESCE(SUM(wi.quantity), 0) INTO available_qty
    FROM warehouse_inventory wi
    WHERE wi.warehouse_id = NEW.from_warehouse_id 
      AND wi.product_id = NEW.product_id;
    
    IF available_qty < NEW.quantity THEN
        RAISE EXCEPTION '%', format('Insufficient warehouse stock. Available: %s, Requested: %s', 
                        available_qty, NEW.quantity);
    END IF;
    
    -- Check shelf capacity
    SELECT sl.max_quantity INTO shelf_max_qty
    FROM shelf_layout sl
    WHERE sl.shelf_id = NEW.to_shelf_id AND sl.product_id = NEW.product_id;
    
    SELECT COALESCE(si.current_quantity, 0) INTO shelf_current_qty
    FROM shelf_inventory si
    WHERE si.shelf_id = NEW.to_shelf_id AND si.product_id = NEW.product_id;
    
    IF NOT FOUND OR shelf_max_qty IS NULL THEN
        RAISE EXCEPTION '%', format('Product %s is not configured for shelf %s', NEW.product_id, NEW.to_shelf_id);
    END IF;
    
    IF (shelf_current_qty + NEW.quantity) > shelf_max_qty THEN
        RAISE EXCEPTION '%', format('Transfer would exceed shelf capacity. Current: %s, Transfer: %s, Max: %s', 
                        shelf_current_qty, NEW.quantity, shelf_max_qty);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2. INVENTORY MANAGEMENT TRIGGERS
-- ============================================================================

-- 2.1 Auto-update Warehouse Inventory on Stock Transfer
CREATE OR REPLACE FUNCTION process_stock_transfer()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- 2.2 Sales Stock Deduction
-- Automatically deduct stock from shelf inventory when sales occur
CREATE OR REPLACE FUNCTION process_sales_stock_deduction()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- 2.3 Auto-calculate Expiry Date for Warehouse Inventory
CREATE OR REPLACE FUNCTION calculate_expiry_date()
RETURNS TRIGGER AS $$
BEGIN
    -- Calculate expiry date if not provided and product has shelf life
    IF NEW.expiry_date IS NULL THEN
        SELECT NEW.import_date + (p.shelf_life_days || ' days')::INTERVAL INTO NEW.expiry_date
        FROM products p
        WHERE p.product_id = NEW.product_id AND p.shelf_life_days IS NOT NULL;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2.4 Low Stock Alert Function
-- Creates notifications when stock falls below threshold
CREATE OR REPLACE FUNCTION check_low_stock()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 3. CUSTOMER MANAGEMENT TRIGGERS
-- ============================================================================

-- 3.1 Update Customer Total Spending and Loyalty Points
CREATE OR REPLACE FUNCTION update_customer_metrics()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- 3.2 Auto-upgrade Customer Membership Level
CREATE OR REPLACE FUNCTION check_membership_upgrade()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 4. FINANCIAL CALCULATION TRIGGERS
-- ============================================================================

-- 4.1 Auto-calculate Invoice Totals
CREATE OR REPLACE FUNCTION calculate_invoice_totals()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- 4.2 Auto-calculate Sales Invoice Detail Subtotal
CREATE OR REPLACE FUNCTION calculate_detail_subtotal()
RETURNS TRIGGER AS $$
BEGIN
    -- Calculate discount amount
    NEW.discount_amount := NEW.unit_price * NEW.quantity * (NEW.discount_percentage / 100);
    
    -- Calculate subtotal
    NEW.subtotal := (NEW.unit_price * NEW.quantity) - NEW.discount_amount;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4.3 Purchase Order Detail Subtotal Calculation
CREATE OR REPLACE FUNCTION calculate_purchase_detail_subtotal()
RETURNS TRIGGER AS $$
BEGIN
    NEW.subtotal := NEW.unit_price * NEW.quantity;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4.4 Update Purchase Order Total
CREATE OR REPLACE FUNCTION update_purchase_order_total()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. EMPLOYEE MANAGEMENT TRIGGERS
-- ============================================================================

-- 5.1 Auto-calculate Work Hours
CREATE OR REPLACE FUNCTION calculate_work_hours()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.check_in_time IS NOT NULL AND NEW.check_out_time IS NOT NULL THEN
        NEW.total_hours := EXTRACT(EPOCH FROM (NEW.check_out_time - NEW.check_in_time)) / 3600;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 6. PRICING MANAGEMENT TRIGGERS
-- ============================================================================

-- 6.1 Auto-apply Expiry Discounts
-- Updates product prices based on remaining shelf life and discount rules
CREATE OR REPLACE FUNCTION apply_expiry_discounts()
RETURNS TRIGGER AS $$
DECLARE
    days_until_expiry INTEGER;
    discount_rule RECORD;
    original_price NUMERIC(12,2);
    new_price NUMERIC(12,2);
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
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 7. AUDIT AND TIMESTAMP TRIGGERS
-- ============================================================================

-- 7.1 Auto-update timestamps
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7.2 Auto-set created_at timestamp
CREATE OR REPLACE FUNCTION set_created_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.created_at = CURRENT_TIMESTAMP;
    IF TG_OP = 'UPDATE' THEN
        NEW.updated_at = CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
