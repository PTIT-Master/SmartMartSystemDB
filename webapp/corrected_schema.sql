--
-- PostgreSQL database dump
--

\restrict 5FAp3M0McAUzLffeqa8DwZUqBq6dmZG3thDlsaIddDCA7pMemownWUVOR5YJ8wP

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

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
-- Name: supermarket; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA supermarket;


ALTER SCHEMA supermarket OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
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
-- Name: customers_customer_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.customers_customer_id_seq OWNED BY supermarket.customers.customer_id;


--
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
-- Name: discount_rules_rule_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.discount_rules_rule_id_seq OWNED BY supermarket.discount_rules.rule_id;


--
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
-- Name: display_shelves_shelf_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.display_shelves_shelf_id_seq OWNED BY supermarket.display_shelves.shelf_id;


--
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
-- Name: employee_work_hours_work_hour_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.employee_work_hours_work_hour_id_seq OWNED BY supermarket.employee_work_hours.work_hour_id;


--
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
-- Name: employees_employee_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.employees_employee_id_seq OWNED BY supermarket.employees.employee_id;


--
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
-- Name: membership_levels_level_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.membership_levels_level_id_seq OWNED BY supermarket.membership_levels.level_id;


--
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
-- Name: positions_position_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.positions_position_id_seq OWNED BY supermarket.positions.position_id;


--
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
-- Name: product_categories_category_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.product_categories_category_id_seq OWNED BY supermarket.product_categories.category_id;


--
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
-- Name: products_product_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.products_product_id_seq OWNED BY supermarket.products.product_id;


--
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
-- Name: purchase_order_details_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.purchase_order_details_detail_id_seq OWNED BY supermarket.purchase_order_details.detail_id;


--
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
-- Name: purchase_orders_order_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.purchase_orders_order_id_seq OWNED BY supermarket.purchase_orders.order_id;


--
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
-- Name: sales_invoice_details_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.sales_invoice_details_detail_id_seq OWNED BY supermarket.sales_invoice_details.detail_id;


--
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
-- Name: sales_invoices_invoice_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.sales_invoices_invoice_id_seq OWNED BY supermarket.sales_invoices.invoice_id;


--
-- Name: shelf_inventory; Type: TABLE; Schema: supermarket; Owner: postgres
--

CREATE TABLE supermarket.shelf_inventory (
    shelf_inventory_id bigint NOT NULL,
    shelf_id bigint NOT NULL,
    product_id bigint NOT NULL,
    current_quantity bigint DEFAULT 0 NOT NULL,
    last_restocked timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone,
    CONSTRAINT chk_shelf_inventory_current_quantity CHECK ((current_quantity >= 0))
);


ALTER TABLE supermarket.shelf_inventory OWNER TO postgres;

--
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
-- Name: shelf_inventory_shelf_inventory_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.shelf_inventory_shelf_inventory_id_seq OWNED BY supermarket.shelf_inventory.shelf_inventory_id;


--
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
-- Name: shelf_layout_layout_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.shelf_layout_layout_id_seq OWNED BY supermarket.shelf_layout.layout_id;


--
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
    batch_code character varying(50),
    notes text,
    created_at timestamp with time zone,
    CONSTRAINT chk_stock_transfers_quantity CHECK ((quantity > 0))
);


ALTER TABLE supermarket.stock_transfers OWNER TO postgres;

--
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
-- Name: stock_transfers_transfer_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.stock_transfers_transfer_id_seq OWNED BY supermarket.stock_transfers.transfer_id;


--
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
-- Name: suppliers_supplier_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.suppliers_supplier_id_seq OWNED BY supermarket.suppliers.supplier_id;


--
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
-- Name: warehouse_inventory_inventory_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.warehouse_inventory_inventory_id_seq OWNED BY supermarket.warehouse_inventory.inventory_id;


--
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
-- Name: warehouse_warehouse_id_seq; Type: SEQUENCE OWNED BY; Schema: supermarket; Owner: postgres
--

ALTER SEQUENCE supermarket.warehouse_warehouse_id_seq OWNED BY supermarket.warehouse.warehouse_id;


--
-- Name: customers customer_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.customers ALTER COLUMN customer_id SET DEFAULT nextval('supermarket.customers_customer_id_seq'::regclass);


--
-- Name: discount_rules rule_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.discount_rules ALTER COLUMN rule_id SET DEFAULT nextval('supermarket.discount_rules_rule_id_seq'::regclass);


--
-- Name: display_shelves shelf_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.display_shelves ALTER COLUMN shelf_id SET DEFAULT nextval('supermarket.display_shelves_shelf_id_seq'::regclass);


--
-- Name: employee_work_hours work_hour_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employee_work_hours ALTER COLUMN work_hour_id SET DEFAULT nextval('supermarket.employee_work_hours_work_hour_id_seq'::regclass);


--
-- Name: employees employee_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employees ALTER COLUMN employee_id SET DEFAULT nextval('supermarket.employees_employee_id_seq'::regclass);


--
-- Name: membership_levels level_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.membership_levels ALTER COLUMN level_id SET DEFAULT nextval('supermarket.membership_levels_level_id_seq'::regclass);


--
-- Name: positions position_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.positions ALTER COLUMN position_id SET DEFAULT nextval('supermarket.positions_position_id_seq'::regclass);


--
-- Name: product_categories category_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.product_categories ALTER COLUMN category_id SET DEFAULT nextval('supermarket.product_categories_category_id_seq'::regclass);


--
-- Name: products product_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.products ALTER COLUMN product_id SET DEFAULT nextval('supermarket.products_product_id_seq'::regclass);


--
-- Name: purchase_order_details detail_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_order_details ALTER COLUMN detail_id SET DEFAULT nextval('supermarket.purchase_order_details_detail_id_seq'::regclass);


--
-- Name: purchase_orders order_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_orders ALTER COLUMN order_id SET DEFAULT nextval('supermarket.purchase_orders_order_id_seq'::regclass);


--
-- Name: sales_invoice_details detail_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoice_details ALTER COLUMN detail_id SET DEFAULT nextval('supermarket.sales_invoice_details_detail_id_seq'::regclass);


--
-- Name: sales_invoices invoice_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoices ALTER COLUMN invoice_id SET DEFAULT nextval('supermarket.sales_invoices_invoice_id_seq'::regclass);


--
-- Name: shelf_inventory shelf_inventory_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_inventory ALTER COLUMN shelf_inventory_id SET DEFAULT nextval('supermarket.shelf_inventory_shelf_inventory_id_seq'::regclass);


--
-- Name: shelf_layout layout_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_layout ALTER COLUMN layout_id SET DEFAULT nextval('supermarket.shelf_layout_layout_id_seq'::regclass);


--
-- Name: stock_transfers transfer_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers ALTER COLUMN transfer_id SET DEFAULT nextval('supermarket.stock_transfers_transfer_id_seq'::regclass);


--
-- Name: suppliers supplier_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.suppliers ALTER COLUMN supplier_id SET DEFAULT nextval('supermarket.suppliers_supplier_id_seq'::regclass);


--
-- Name: warehouse warehouse_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse ALTER COLUMN warehouse_id SET DEFAULT nextval('supermarket.warehouse_warehouse_id_seq'::regclass);


--
-- Name: warehouse_inventory inventory_id; Type: DEFAULT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse_inventory ALTER COLUMN inventory_id SET DEFAULT nextval('supermarket.warehouse_inventory_inventory_id_seq'::regclass);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (customer_id);


--
-- Name: discount_rules discount_rules_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.discount_rules
    ADD CONSTRAINT discount_rules_pkey PRIMARY KEY (rule_id);


--
-- Name: display_shelves display_shelves_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.display_shelves
    ADD CONSTRAINT display_shelves_pkey PRIMARY KEY (shelf_id);


--
-- Name: employee_work_hours employee_work_hours_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employee_work_hours
    ADD CONSTRAINT employee_work_hours_pkey PRIMARY KEY (work_hour_id);


--
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (employee_id);


--
-- Name: membership_levels membership_levels_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.membership_levels
    ADD CONSTRAINT membership_levels_pkey PRIMARY KEY (level_id);


--
-- Name: positions positions_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.positions
    ADD CONSTRAINT positions_pkey PRIMARY KEY (position_id);


--
-- Name: product_categories product_categories_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.product_categories
    ADD CONSTRAINT product_categories_pkey PRIMARY KEY (category_id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (product_id);


--
-- Name: purchase_order_details purchase_order_details_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_order_details
    ADD CONSTRAINT purchase_order_details_pkey PRIMARY KEY (detail_id);


--
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (order_id);


--
-- Name: sales_invoice_details sales_invoice_details_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoice_details
    ADD CONSTRAINT sales_invoice_details_pkey PRIMARY KEY (detail_id);


--
-- Name: sales_invoices sales_invoices_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoices
    ADD CONSTRAINT sales_invoices_pkey PRIMARY KEY (invoice_id);


--
-- Name: shelf_inventory shelf_inventory_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_inventory
    ADD CONSTRAINT shelf_inventory_pkey PRIMARY KEY (shelf_inventory_id);


--
-- Name: shelf_layout shelf_layout_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_layout
    ADD CONSTRAINT shelf_layout_pkey PRIMARY KEY (layout_id);


--
-- Name: stock_transfers stock_transfers_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers
    ADD CONSTRAINT stock_transfers_pkey PRIMARY KEY (transfer_id);


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (supplier_id);


--
-- Name: customers uni_customers_customer_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.customers
    ADD CONSTRAINT uni_customers_customer_code UNIQUE (customer_code);


--
-- Name: customers uni_customers_membership_card_no; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.customers
    ADD CONSTRAINT uni_customers_membership_card_no UNIQUE (membership_card_no);


--
-- Name: customers uni_customers_phone; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.customers
    ADD CONSTRAINT uni_customers_phone UNIQUE (phone);


--
-- Name: display_shelves uni_display_shelves_shelf_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.display_shelves
    ADD CONSTRAINT uni_display_shelves_shelf_code UNIQUE (shelf_code);


--
-- Name: employees uni_employees_email; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employees
    ADD CONSTRAINT uni_employees_email UNIQUE (email);


--
-- Name: employees uni_employees_employee_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employees
    ADD CONSTRAINT uni_employees_employee_code UNIQUE (employee_code);


--
-- Name: employees uni_employees_id_card; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employees
    ADD CONSTRAINT uni_employees_id_card UNIQUE (id_card);


--
-- Name: membership_levels uni_membership_levels_level_name; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.membership_levels
    ADD CONSTRAINT uni_membership_levels_level_name UNIQUE (level_name);


--
-- Name: positions uni_positions_position_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.positions
    ADD CONSTRAINT uni_positions_position_code UNIQUE (position_code);


--
-- Name: product_categories uni_product_categories_category_name; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.product_categories
    ADD CONSTRAINT uni_product_categories_category_name UNIQUE (category_name);


--
-- Name: products uni_products_barcode; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.products
    ADD CONSTRAINT uni_products_barcode UNIQUE (barcode);


--
-- Name: products uni_products_product_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.products
    ADD CONSTRAINT uni_products_product_code UNIQUE (product_code);


--
-- Name: purchase_orders uni_purchase_orders_order_no; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_orders
    ADD CONSTRAINT uni_purchase_orders_order_no UNIQUE (order_no);


--
-- Name: sales_invoices uni_sales_invoices_invoice_no; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoices
    ADD CONSTRAINT uni_sales_invoices_invoice_no UNIQUE (invoice_no);


--
-- Name: stock_transfers uni_stock_transfers_transfer_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers
    ADD CONSTRAINT uni_stock_transfers_transfer_code UNIQUE (transfer_code);


--
-- Name: suppliers uni_suppliers_supplier_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.suppliers
    ADD CONSTRAINT uni_suppliers_supplier_code UNIQUE (supplier_code);


--
-- Name: warehouse uni_warehouse_warehouse_code; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse
    ADD CONSTRAINT uni_warehouse_warehouse_code UNIQUE (warehouse_code);


--
-- Name: warehouse_inventory unique_batch; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse_inventory
    ADD CONSTRAINT unique_batch UNIQUE (warehouse_id, product_id, batch_code);


--
-- Name: discount_rules unique_category_days; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.discount_rules
    ADD CONSTRAINT unique_category_days UNIQUE (category_id, days_before_expiry);


--
-- Name: employee_work_hours unique_employee_date; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employee_work_hours
    ADD CONSTRAINT unique_employee_date UNIQUE (employee_id, work_date);


--
-- Name: shelf_layout unique_shelf_position; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_layout
    ADD CONSTRAINT unique_shelf_position UNIQUE (shelf_id, position_code);


--
-- Name: shelf_layout unique_shelf_product; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_layout
    ADD CONSTRAINT unique_shelf_product UNIQUE (shelf_id, product_id);


--
-- Name: shelf_inventory unique_shelf_product_inv; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_inventory
    ADD CONSTRAINT unique_shelf_product_inv UNIQUE (shelf_id, product_id);


--
-- Name: warehouse_inventory warehouse_inventory_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse_inventory
    ADD CONSTRAINT warehouse_inventory_pkey PRIMARY KEY (inventory_id);


--
-- Name: warehouse warehouse_pkey; Type: CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse
    ADD CONSTRAINT warehouse_pkey PRIMARY KEY (warehouse_id);


--
-- Name: idx_customer_membership; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_customer_membership ON supermarket.customers USING btree (membership_level_id);


--
-- Name: idx_customer_spending; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_customer_spending ON supermarket.customers USING btree (total_spending);


--
-- Name: idx_employee_position; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_employee_position ON supermarket.employees USING btree (position_id);


--
-- Name: idx_products_category; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_products_category ON supermarket.products USING btree (category_id);


--
-- Name: idx_products_supplier; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_products_supplier ON supermarket.products USING btree (supplier_id);


--
-- Name: idx_sales_details_product; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_sales_details_product ON supermarket.sales_invoice_details USING btree (product_id);


--
-- Name: idx_sales_invoice_customer; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_sales_invoice_customer ON supermarket.sales_invoices USING btree (customer_id);


--
-- Name: idx_sales_invoice_date; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_sales_invoice_date ON supermarket.sales_invoices USING btree (invoice_date);


--
-- Name: idx_sales_invoice_employee; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_sales_invoice_employee ON supermarket.sales_invoices USING btree (employee_id);


--
-- Name: idx_shelf_inv_product; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_shelf_inv_product ON supermarket.shelf_inventory USING btree (product_id);


--
-- Name: idx_shelf_inv_quantity; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_shelf_inv_quantity ON supermarket.shelf_inventory USING btree (current_quantity);


--
-- Name: idx_warehouse_inv_expiry; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_warehouse_inv_expiry ON supermarket.warehouse_inventory USING btree (expiry_date);


--
-- Name: idx_warehouse_inv_product; Type: INDEX; Schema: supermarket; Owner: postgres
--

CREATE INDEX idx_warehouse_inv_product ON supermarket.warehouse_inventory USING btree (product_id);


--
-- Name: customers fk_customers_membership_level; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.customers
    ADD CONSTRAINT fk_customers_membership_level FOREIGN KEY (membership_level_id) REFERENCES supermarket.membership_levels(level_id);


--
-- Name: discount_rules fk_discount_rules_category; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.discount_rules
    ADD CONSTRAINT fk_discount_rules_category FOREIGN KEY (category_id) REFERENCES supermarket.product_categories(category_id);


--
-- Name: display_shelves fk_display_shelves_category; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.display_shelves
    ADD CONSTRAINT fk_display_shelves_category FOREIGN KEY (category_id) REFERENCES supermarket.product_categories(category_id);


--
-- Name: employee_work_hours fk_employee_work_hours_employee; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employee_work_hours
    ADD CONSTRAINT fk_employee_work_hours_employee FOREIGN KEY (employee_id) REFERENCES supermarket.employees(employee_id);


--
-- Name: employees fk_employees_position; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.employees
    ADD CONSTRAINT fk_employees_position FOREIGN KEY (position_id) REFERENCES supermarket.positions(position_id);


--
-- Name: products fk_products_category; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.products
    ADD CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES supermarket.product_categories(category_id);


--
-- Name: products fk_products_supplier; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.products
    ADD CONSTRAINT fk_products_supplier FOREIGN KEY (supplier_id) REFERENCES supermarket.suppliers(supplier_id);


--
-- Name: purchase_order_details fk_purchase_order_details_order; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_order_details
    ADD CONSTRAINT fk_purchase_order_details_order FOREIGN KEY (order_id) REFERENCES supermarket.purchase_orders(order_id);


--
-- Name: purchase_order_details fk_purchase_order_details_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_order_details
    ADD CONSTRAINT fk_purchase_order_details_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- Name: purchase_orders fk_purchase_orders_employee; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_orders
    ADD CONSTRAINT fk_purchase_orders_employee FOREIGN KEY (employee_id) REFERENCES supermarket.employees(employee_id);


--
-- Name: purchase_orders fk_purchase_orders_supplier; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.purchase_orders
    ADD CONSTRAINT fk_purchase_orders_supplier FOREIGN KEY (supplier_id) REFERENCES supermarket.suppliers(supplier_id);


--
-- Name: sales_invoice_details fk_sales_invoice_details_invoice; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoice_details
    ADD CONSTRAINT fk_sales_invoice_details_invoice FOREIGN KEY (invoice_id) REFERENCES supermarket.sales_invoices(invoice_id);


--
-- Name: sales_invoice_details fk_sales_invoice_details_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoice_details
    ADD CONSTRAINT fk_sales_invoice_details_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- Name: sales_invoices fk_sales_invoices_customer; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoices
    ADD CONSTRAINT fk_sales_invoices_customer FOREIGN KEY (customer_id) REFERENCES supermarket.customers(customer_id);


--
-- Name: sales_invoices fk_sales_invoices_employee; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.sales_invoices
    ADD CONSTRAINT fk_sales_invoices_employee FOREIGN KEY (employee_id) REFERENCES supermarket.employees(employee_id);


--
-- Name: shelf_inventory fk_shelf_inventory_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_inventory
    ADD CONSTRAINT fk_shelf_inventory_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- Name: shelf_inventory fk_shelf_inventory_shelf; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_inventory
    ADD CONSTRAINT fk_shelf_inventory_shelf FOREIGN KEY (shelf_id) REFERENCES supermarket.display_shelves(shelf_id);


--
-- Name: shelf_layout fk_shelf_layout_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_layout
    ADD CONSTRAINT fk_shelf_layout_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- Name: shelf_layout fk_shelf_layout_shelf; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.shelf_layout
    ADD CONSTRAINT fk_shelf_layout_shelf FOREIGN KEY (shelf_id) REFERENCES supermarket.display_shelves(shelf_id);


--
-- Name: stock_transfers fk_stock_transfers_employee; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers
    ADD CONSTRAINT fk_stock_transfers_employee FOREIGN KEY (employee_id) REFERENCES supermarket.employees(employee_id);


--
-- Name: stock_transfers fk_stock_transfers_from_warehouse; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers
    ADD CONSTRAINT fk_stock_transfers_from_warehouse FOREIGN KEY (from_warehouse_id) REFERENCES supermarket.warehouse(warehouse_id);


--
-- Name: stock_transfers fk_stock_transfers_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers
    ADD CONSTRAINT fk_stock_transfers_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- Name: stock_transfers fk_stock_transfers_to_shelf; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.stock_transfers
    ADD CONSTRAINT fk_stock_transfers_to_shelf FOREIGN KEY (to_shelf_id) REFERENCES supermarket.display_shelves(shelf_id);


--
-- Name: warehouse_inventory fk_warehouse_inventory_product; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse_inventory
    ADD CONSTRAINT fk_warehouse_inventory_product FOREIGN KEY (product_id) REFERENCES supermarket.products(product_id);


--
-- Name: warehouse_inventory fk_warehouse_inventory_warehouse; Type: FK CONSTRAINT; Schema: supermarket; Owner: postgres
--

ALTER TABLE ONLY supermarket.warehouse_inventory
    ADD CONSTRAINT fk_warehouse_inventory_warehouse FOREIGN KEY (warehouse_id) REFERENCES supermarket.warehouse(warehouse_id);


--
-- PostgreSQL database dump complete
--

\unrestrict 5FAp3M0McAUzLffeqa8DwZUqBq6dmZG3thDlsaIddDCA7pMemownWUVOR5YJ8wP

