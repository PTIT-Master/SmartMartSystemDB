-- =====================================================
-- SUPERMARKET RETAIL MANAGEMENT SYSTEM DATABASE
-- PostgreSQL Database Schema (BCNF Normalized)
-- File: 01_schema.sql
-- Content: Tables, Indexes, Constraints, and Basic Triggers
-- =====================================================

-- Drop existing tables if they exist
DROP SCHEMA IF EXISTS supermarket CASCADE;
CREATE SCHEMA supermarket;
SET search_path TO supermarket;

-- =====================================================
-- 1. PRODUCT CATEGORIES TABLE
-- =====================================================
CREATE TABLE product_categories (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- 2. SUPPLIERS TABLE
-- =====================================================
CREATE TABLE suppliers (
    supplier_id SERIAL PRIMARY KEY,
    supplier_code VARCHAR(20) NOT NULL UNIQUE,
    supplier_name VARCHAR(200) NOT NULL,
    contact_person VARCHAR(100),
    phone VARCHAR(20),
    email VARCHAR(100),
    address TEXT,
    tax_code VARCHAR(20),
    bank_account VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- 3. PRODUCTS TABLE
-- =====================================================
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    product_code VARCHAR(50) NOT NULL UNIQUE,
    product_name VARCHAR(200) NOT NULL,
    category_id INTEGER NOT NULL,
    supplier_id INTEGER NOT NULL,
    unit VARCHAR(20) NOT NULL, -- Unit of measurement
    import_price DECIMAL(12,2) NOT NULL CHECK (import_price > 0),
    selling_price DECIMAL(12,2) NOT NULL,
    shelf_life_days INTEGER, -- Shelf life in days
    low_stock_threshold INTEGER DEFAULT 10, -- Threshold for low stock warning
    barcode VARCHAR(50) UNIQUE,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_category FOREIGN KEY (category_id) 
        REFERENCES product_categories(category_id) ON DELETE RESTRICT,
    CONSTRAINT fk_supplier FOREIGN KEY (supplier_id) 
        REFERENCES suppliers(supplier_id) ON DELETE RESTRICT,
    CONSTRAINT check_price CHECK (selling_price > import_price)
);

-- =====================================================
-- 4. DISCOUNT RULES TABLE
-- =====================================================
CREATE TABLE discount_rules (
    rule_id SERIAL PRIMARY KEY,
    category_id INTEGER NOT NULL,
    days_before_expiry INTEGER NOT NULL,
    discount_percentage DECIMAL(5,2) NOT NULL CHECK (discount_percentage BETWEEN 0 AND 100),
    rule_name VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_discount_category FOREIGN KEY (category_id) 
        REFERENCES product_categories(category_id) ON DELETE CASCADE,
    CONSTRAINT unique_category_days UNIQUE (category_id, days_before_expiry)
);

-- =====================================================
-- 5. WAREHOUSE TABLE
-- =====================================================
CREATE TABLE warehouse (
    warehouse_id SERIAL PRIMARY KEY,
    warehouse_code VARCHAR(20) NOT NULL UNIQUE,
    warehouse_name VARCHAR(100) NOT NULL,
    location VARCHAR(200),
    manager_name VARCHAR(100),
    capacity INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- 6. WAREHOUSE INVENTORY TABLE
-- =====================================================
CREATE TABLE warehouse_inventory (
    inventory_id SERIAL PRIMARY KEY,
    warehouse_id INTEGER NOT NULL DEFAULT 1,
    product_id INTEGER NOT NULL,
    batch_code VARCHAR(50) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    import_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date DATE,
    import_price DECIMAL(12,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_warehouse FOREIGN KEY (warehouse_id) 
        REFERENCES warehouse(warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_product_warehouse FOREIGN KEY (product_id) 
        REFERENCES products(product_id) ON DELETE RESTRICT,
    CONSTRAINT unique_batch UNIQUE (warehouse_id, product_id, batch_code)
);

-- =====================================================
-- 7. DISPLAY SHELVES TABLE
-- =====================================================
CREATE TABLE display_shelves (
    shelf_id SERIAL PRIMARY KEY,
    shelf_code VARCHAR(20) NOT NULL UNIQUE,
    shelf_name VARCHAR(100) NOT NULL,
    category_id INTEGER NOT NULL,
    location VARCHAR(100),
    max_capacity INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_shelf_category FOREIGN KEY (category_id) 
        REFERENCES product_categories(category_id) ON DELETE RESTRICT
);

-- =====================================================
-- 8. SHELF LAYOUT TABLE (Product placement on shelves)
-- =====================================================
CREATE TABLE shelf_layout (
    layout_id SERIAL PRIMARY KEY,
    shelf_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    position_code VARCHAR(20) NOT NULL, -- Position on shelf (e.g., A1, B2)
    max_quantity INTEGER NOT NULL CHECK (max_quantity > 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_shelf_layout FOREIGN KEY (shelf_id) 
        REFERENCES display_shelves(shelf_id) ON DELETE CASCADE,
    CONSTRAINT fk_product_layout FOREIGN KEY (product_id) 
        REFERENCES products(product_id) ON DELETE CASCADE,
    CONSTRAINT unique_shelf_position UNIQUE (shelf_id, position_code),
    CONSTRAINT unique_shelf_product UNIQUE (shelf_id, product_id)
);

-- =====================================================
-- 9. SHELF INVENTORY TABLE (Current stock on shelves)
-- =====================================================
CREATE TABLE shelf_inventory (
    shelf_inventory_id SERIAL PRIMARY KEY,
    shelf_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    current_quantity INTEGER NOT NULL DEFAULT 0 CHECK (current_quantity >= 0),
    last_restocked TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_shelf_inv FOREIGN KEY (shelf_id) 
        REFERENCES display_shelves(shelf_id) ON DELETE CASCADE,
    CONSTRAINT fk_product_shelf_inv FOREIGN KEY (product_id) 
        REFERENCES products(product_id) ON DELETE CASCADE,
    CONSTRAINT unique_shelf_product_inv UNIQUE (shelf_id, product_id)
);

-- =====================================================
-- 10. POSITIONS TABLE (Employee positions)
-- =====================================================
CREATE TABLE positions (
    position_id SERIAL PRIMARY KEY,
    position_code VARCHAR(20) NOT NULL UNIQUE,
    position_name VARCHAR(100) NOT NULL,
    base_salary DECIMAL(12,2) NOT NULL CHECK (base_salary >= 0),
    hourly_rate DECIMAL(10,2) NOT NULL CHECK (hourly_rate >= 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- 11. EMPLOYEES TABLE
-- =====================================================
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    employee_code VARCHAR(20) NOT NULL UNIQUE,
    full_name VARCHAR(100) NOT NULL,
    position_id INTEGER NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(100) UNIQUE,
    address TEXT,
    hire_date DATE NOT NULL DEFAULT CURRENT_DATE,
    id_card VARCHAR(20) UNIQUE,
    bank_account VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_position FOREIGN KEY (position_id) 
        REFERENCES positions(position_id) ON DELETE RESTRICT
);

-- =====================================================
-- 12. EMPLOYEE WORK HOURS TABLE
-- =====================================================
CREATE TABLE employee_work_hours (
    work_hour_id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL,
    work_date DATE NOT NULL,
    check_in_time TIME,
    check_out_time TIME,
    total_hours DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE 
            WHEN check_in_time IS NOT NULL AND check_out_time IS NOT NULL 
            THEN EXTRACT(EPOCH FROM (check_out_time - check_in_time))/3600
            ELSE 0
        END
    ) STORED,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_employee_hours FOREIGN KEY (employee_id) 
        REFERENCES employees(employee_id) ON DELETE CASCADE,
    CONSTRAINT unique_employee_date UNIQUE (employee_id, work_date)
);

-- =====================================================
-- 13. CUSTOMER MEMBERSHIP LEVELS TABLE
-- =====================================================
CREATE TABLE membership_levels (
    level_id SERIAL PRIMARY KEY,
    level_name VARCHAR(50) NOT NULL UNIQUE,
    min_spending DECIMAL(12,2) NOT NULL DEFAULT 0,
    discount_percentage DECIMAL(5,2) DEFAULT 0,
    points_multiplier DECIMAL(3,2) DEFAULT 1.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- 14. CUSTOMERS TABLE
-- =====================================================
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    customer_code VARCHAR(20) UNIQUE,
    full_name VARCHAR(100),
    phone VARCHAR(20) UNIQUE,
    email VARCHAR(100),
    address TEXT,
    membership_card_no VARCHAR(20) UNIQUE,
    membership_level_id INTEGER,
    registration_date DATE DEFAULT CURRENT_DATE,
    total_spending DECIMAL(12,2) DEFAULT 0,
    loyalty_points INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_membership_level FOREIGN KEY (membership_level_id) 
        REFERENCES membership_levels(level_id) ON DELETE SET NULL
);

-- =====================================================
-- 15. SALES INVOICES TABLE
-- =====================================================
CREATE TABLE sales_invoices (
    invoice_id SERIAL PRIMARY KEY,
    invoice_no VARCHAR(30) NOT NULL UNIQUE,
    customer_id INTEGER,
    employee_id INTEGER NOT NULL,
    invoice_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    subtotal DECIMAL(12,2) NOT NULL DEFAULT 0,
    discount_amount DECIMAL(12,2) DEFAULT 0,
    tax_amount DECIMAL(12,2) DEFAULT 0,
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    payment_method VARCHAR(20) CHECK (payment_method IN ('CASH', 'CARD', 'TRANSFER', 'VOUCHER')),
    points_earned INTEGER DEFAULT 0,
    points_used INTEGER DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_customer_invoice FOREIGN KEY (customer_id) 
        REFERENCES customers(customer_id) ON DELETE SET NULL,
    CONSTRAINT fk_employee_invoice FOREIGN KEY (employee_id) 
        REFERENCES employees(employee_id) ON DELETE RESTRICT
);

-- =====================================================
-- 16. SALES INVOICE DETAILS TABLE
-- =====================================================
CREATE TABLE sales_invoice_details (
    detail_id SERIAL PRIMARY KEY,
    invoice_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(12,2) NOT NULL,
    discount_percentage DECIMAL(5,2) DEFAULT 0,
    discount_amount DECIMAL(12,2) DEFAULT 0,
    subtotal DECIMAL(12,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_invoice_detail FOREIGN KEY (invoice_id) 
        REFERENCES sales_invoices(invoice_id) ON DELETE CASCADE,
    CONSTRAINT fk_product_detail FOREIGN KEY (product_id) 
        REFERENCES products(product_id) ON DELETE RESTRICT
);

-- =====================================================
-- 17. PURCHASE ORDERS TABLE
-- =====================================================
CREATE TABLE purchase_orders (
    order_id SERIAL PRIMARY KEY,
    order_no VARCHAR(30) NOT NULL UNIQUE,
    supplier_id INTEGER NOT NULL,
    employee_id INTEGER NOT NULL,
    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    delivery_date DATE,
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'RECEIVED', 'CANCELLED')),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_supplier_order FOREIGN KEY (supplier_id) 
        REFERENCES suppliers(supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_employee_order FOREIGN KEY (employee_id) 
        REFERENCES employees(employee_id) ON DELETE RESTRICT
);

-- =====================================================
-- 18. PURCHASE ORDER DETAILS TABLE
-- =====================================================
CREATE TABLE purchase_order_details (
    detail_id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(12,2) NOT NULL,
    subtotal DECIMAL(12,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_order_detail FOREIGN KEY (order_id) 
        REFERENCES purchase_orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_product_order FOREIGN KEY (product_id) 
        REFERENCES products(product_id) ON DELETE RESTRICT
);

-- =====================================================
-- 19. STOCK TRANSFER LOG TABLE (Warehouse to Shelf)
-- =====================================================
CREATE TABLE stock_transfers (
    transfer_id SERIAL PRIMARY KEY,
    transfer_code VARCHAR(30) NOT NULL UNIQUE,
    product_id INTEGER NOT NULL,
    from_warehouse_id INTEGER NOT NULL,
    to_shelf_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    transfer_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    employee_id INTEGER NOT NULL,
    batch_code VARCHAR(50),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_product_transfer FOREIGN KEY (product_id) 
        REFERENCES products(product_id) ON DELETE RESTRICT,
    CONSTRAINT fk_warehouse_transfer FOREIGN KEY (from_warehouse_id) 
        REFERENCES warehouse(warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT fk_shelf_transfer FOREIGN KEY (to_shelf_id) 
        REFERENCES display_shelves(shelf_id) ON DELETE RESTRICT,
    CONSTRAINT fk_employee_transfer FOREIGN KEY (employee_id) 
        REFERENCES employees(employee_id) ON DELETE RESTRICT
);

-- =====================================================
-- INDEXES FOR PERFORMANCE
-- =====================================================
CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_supplier ON products(supplier_id);
CREATE INDEX idx_warehouse_inv_product ON warehouse_inventory(product_id);
CREATE INDEX idx_warehouse_inv_expiry ON warehouse_inventory(expiry_date);
CREATE INDEX idx_shelf_inv_product ON shelf_inventory(product_id);
CREATE INDEX idx_shelf_inv_quantity ON shelf_inventory(current_quantity);
CREATE INDEX idx_sales_invoice_date ON sales_invoices(invoice_date);
CREATE INDEX idx_sales_invoice_customer ON sales_invoices(customer_id);
CREATE INDEX idx_sales_invoice_employee ON sales_invoices(employee_id);
CREATE INDEX idx_sales_details_product ON sales_invoice_details(product_id);
CREATE INDEX idx_employee_position ON employees(position_id);
CREATE INDEX idx_customer_membership ON customers(membership_level_id);
CREATE INDEX idx_customer_spending ON customers(total_spending);

-- =====================================================
-- TRIGGERS FOR AUTOMATIC UPDATES
-- =====================================================

-- Trigger to update timestamp
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update timestamp trigger to relevant tables
CREATE TRIGGER update_products_timestamp BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_suppliers_timestamp BEFORE UPDATE ON suppliers
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_employees_timestamp BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_customers_timestamp BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_warehouse_inv_timestamp BEFORE UPDATE ON warehouse_inventory
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_shelf_inv_timestamp BEFORE UPDATE ON shelf_inventory
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- =====================================================
-- TRIGGER: Update shelf inventory after sale
-- =====================================================
CREATE OR REPLACE FUNCTION update_shelf_after_sale()
RETURNS TRIGGER AS $$
BEGIN
    -- Update shelf inventory quantity
    UPDATE shelf_inventory si
    SET current_quantity = current_quantity - NEW.quantity
    FROM products p, display_shelves ds, shelf_layout sl
    WHERE si.product_id = NEW.product_id
      AND si.product_id = p.product_id
      AND si.shelf_id = ds.shelf_id
      AND sl.shelf_id = ds.shelf_id
      AND sl.product_id = p.product_id;
    
    -- Check if restock is needed
    IF EXISTS (
        SELECT 1 FROM shelf_inventory si
        JOIN products p ON si.product_id = p.product_id
        WHERE si.product_id = NEW.product_id
          AND si.current_quantity < p.low_stock_threshold
    ) THEN
        RAISE NOTICE 'Low stock alert for product_id: %', NEW.product_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_shelf_after_sale
AFTER INSERT ON sales_invoice_details
FOR EACH ROW EXECUTE FUNCTION update_shelf_after_sale();

-- =====================================================
-- TRIGGER: Update customer total spending and level
-- =====================================================
CREATE OR REPLACE FUNCTION update_customer_spending()
RETURNS TRIGGER AS $$
BEGIN
    -- Update total spending
    UPDATE customers
    SET total_spending = total_spending + NEW.total_amount
    WHERE customer_id = NEW.customer_id;
    
    -- Update membership level based on spending
    UPDATE customers c
    SET membership_level_id = (
        SELECT level_id FROM membership_levels
        WHERE min_spending <= c.total_spending + NEW.total_amount
        ORDER BY min_spending DESC
        LIMIT 1
    )
    WHERE customer_id = NEW.customer_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_customer_spending
AFTER INSERT ON sales_invoices
FOR EACH ROW EXECUTE FUNCTION update_customer_spending();

-- =====================================================
-- TRIGGER: Validate stock transfer quantity
-- =====================================================
CREATE OR REPLACE FUNCTION validate_stock_transfer()
RETURNS TRIGGER AS $$
DECLARE
    available_qty INTEGER;
BEGIN
    -- Check available quantity in warehouse
    SELECT SUM(quantity) INTO available_qty
    FROM warehouse_inventory
    WHERE warehouse_id = NEW.from_warehouse_id
      AND product_id = NEW.product_id
      AND (NEW.batch_code IS NULL OR batch_code = NEW.batch_code);
    
    IF available_qty IS NULL OR available_qty < NEW.quantity THEN
        RAISE EXCEPTION 'Insufficient quantity in warehouse. Available: %, Requested: %', 
                        COALESCE(available_qty, 0), NEW.quantity;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validate_stock_transfer
BEFORE INSERT ON stock_transfers
FOR EACH ROW EXECUTE FUNCTION validate_stock_transfer();

-- =====================================================
-- VIEWS FOR REPORTING
-- =====================================================

-- View: Products near expiry
CREATE VIEW v_products_near_expiry AS
SELECT 
    w.warehouse_name,
    p.product_code,
    p.product_name,
    wi.batch_code,
    wi.quantity,
    wi.expiry_date,
    wi.import_date,
    CASE 
        WHEN wi.expiry_date - CURRENT_DATE <= 5 THEN 'CRITICAL'
        WHEN wi.expiry_date - CURRENT_DATE <= 10 THEN 'WARNING'
        ELSE 'OK'
    END as status
FROM warehouse_inventory wi
JOIN products p ON wi.product_id = p.product_id
JOIN warehouse w ON wi.warehouse_id = w.warehouse_id
WHERE wi.expiry_date IS NOT NULL
  AND wi.quantity > 0
ORDER BY wi.expiry_date;

-- View: Low stock products on shelves
CREATE VIEW v_low_stock_shelves AS
SELECT 
    ds.shelf_code,
    ds.shelf_name,
    p.product_code,
    p.product_name,
    si.current_quantity,
    p.low_stock_threshold,
    sl.max_quantity,
    CASE 
        WHEN si.current_quantity = 0 THEN 'OUT_OF_STOCK'
        WHEN si.current_quantity < p.low_stock_threshold THEN 'LOW_STOCK'
        ELSE 'SUFFICIENT'
    END as stock_status
FROM shelf_inventory si
JOIN products p ON si.product_id = p.product_id
JOIN display_shelves ds ON si.shelf_id = ds.shelf_id
JOIN shelf_layout sl ON sl.shelf_id = si.shelf_id AND sl.product_id = si.product_id
WHERE si.current_quantity < p.low_stock_threshold
ORDER BY si.current_quantity;

-- View: Employee monthly sales performance
CREATE VIEW v_employee_monthly_sales AS
SELECT 
    e.employee_code,
    e.full_name,
    DATE_TRUNC('month', si.invoice_date) as month,
    COUNT(DISTINCT si.invoice_id) as total_transactions,
    SUM(si.total_amount) as total_sales,
    AVG(si.total_amount) as avg_transaction_value
FROM employees e
JOIN sales_invoices si ON e.employee_id = si.employee_id
GROUP BY e.employee_id, e.employee_code, e.full_name, DATE_TRUNC('month', si.invoice_date)
ORDER BY month DESC, total_sales DESC;

-- View: Product sales ranking
CREATE VIEW v_product_sales_ranking AS
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    DATE_TRUNC('month', si.invoice_date) as month,
    SUM(sid.quantity) as total_quantity_sold,
    SUM(sid.subtotal) as total_revenue,
    COUNT(DISTINCT si.invoice_id) as transaction_count
FROM products p
JOIN product_categories pc ON p.category_id = pc.category_id
JOIN sales_invoice_details sid ON p.product_id = sid.product_id
JOIN sales_invoices si ON sid.invoice_id = si.invoice_id
GROUP BY p.product_id, p.product_code, p.product_name, pc.category_name, 
         DATE_TRUNC('month', si.invoice_date)
ORDER BY month DESC, total_revenue DESC;

-- =====================================================
-- END OF SCHEMA DEFINITION
-- =====================================================
-- Note: Sample data is in 04_insert_sample_data.sql
-- Note: Functions are in 02_functions.sql
-- Note: Views and queries are in 03_queries.sql