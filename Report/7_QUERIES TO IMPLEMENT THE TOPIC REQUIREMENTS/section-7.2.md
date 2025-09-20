# 7.2. QUERIES THEO DÕI TỒN KHO

Phần này trình bày các câu lệnh SQL để theo dõi và quản lý tồn kho theo các yêu cầu cụ thể của đề tài, bao gồm việc liệt kê hàng hóa theo nhiều tiêu chí khác nhau và phân tích tình trạng tồn kho.

## 7.2.1. Liệt kê hàng theo chủng loại/quầy hàng (sắp xếp theo số lượng)

### A. Liệt kê sản phẩm theo chủng loại - sắp xếp theo số lượng trên quầy

```sql
-- Query: Liệt kê các hàng hóa thuộc một chủng loại, sắp xếp theo số lượng tăng dần trên quầy
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    ds.shelf_code,
    ds.shelf_name,
    si.current_quantity as shelf_quantity,
    sl.max_quantity as shelf_capacity,
    ROUND((si.current_quantity::NUMERIC / sl.max_quantity * 100), 2) as capacity_usage_percent,
    p.low_stock_threshold,
    CASE 
        WHEN si.current_quantity = 0 THEN 'Hết hàng'
        WHEN si.current_quantity <= p.low_stock_threshold THEN 'Sắp hết'
        WHEN si.current_quantity >= sl.max_quantity * 0.8 THEN 'Đầy'
        ELSE 'Bình thường'
    END as stock_status
FROM supermarket.products p
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.shelf_inventory si ON p.product_id = si.product_id
INNER JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
INNER JOIN supermarket.shelf_layout sl ON si.shelf_id = sl.shelf_id 
                                        AND si.product_id = sl.product_id
WHERE 
    p.is_active = true
    AND pc.category_name = 'Food' -- Thay đổi category theo nhu cầu
ORDER BY si.current_quantity ASC, p.product_name ASC;
```

### B. Liệt kê sản phẩm theo quầy hàng cụ thể

```sql
-- Query: Liệt kê các sản phẩm trên một quầy hàng cụ thể
SELECT 
    ds.shelf_code,
    ds.shelf_name,
    pc.category_name,
    p.product_code,
    p.product_name,
    si.current_quantity as shelf_quantity,
    sl.max_quantity as shelf_capacity,
    sl.position_code as shelf_position,
    p.selling_price,
    -- Tính số lượng có thể bổ sung thêm
    (sl.max_quantity - si.current_quantity) as can_add_quantity,
    si.last_restocked
FROM supermarket.display_shelves ds
INNER JOIN supermarket.product_categories pc ON ds.category_id = pc.category_id
INNER JOIN supermarket.shelf_inventory si ON ds.shelf_id = si.shelf_id
INNER JOIN supermarket.products p ON si.product_id = p.product_id
INNER JOIN supermarket.shelf_layout sl ON ds.shelf_id = sl.shelf_id 
                                        AND p.product_id = sl.product_id
WHERE 
    ds.shelf_code = 'SHELF-FOOD-01' -- Thay đổi shelf_code theo nhu cầu
    AND p.is_active = true
ORDER BY si.current_quantity ASC, sl.position_code ASC;
```

### C. Liệt kê sản phẩm sắp xếp theo số lượng bán trong ngày

```sql
-- Query: Sản phẩm sắp xếp theo số lượng được mua trong ngày (hôm nay)
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    ds.shelf_name,
    si.current_quantity as current_shelf_stock,
    COALESCE(daily_sales.quantity_sold_today, 0) as sold_today,
    COALESCE(daily_sales.revenue_today, 0) as revenue_today,
    COALESCE(daily_sales.transaction_count, 0) as transactions_today,
    -- Tính tỷ lệ bán/tồn kho
    CASE 
        WHEN si.current_quantity > 0 THEN 
            ROUND((COALESCE(daily_sales.quantity_sold_today, 0)::NUMERIC / si.current_quantity * 100), 2)
        ELSE 0
    END as turnover_rate_percent
FROM supermarket.products p
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
LEFT JOIN supermarket.shelf_inventory si ON p.product_id = si.product_id
LEFT JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
LEFT JOIN (
    -- Subquery: Tính số lượng bán trong ngày
    SELECT 
        sid.product_id,
        SUM(sid.quantity) as quantity_sold_today,
        SUM(sid.subtotal) as revenue_today,
        COUNT(DISTINCT si.invoice_id) as transaction_count
    FROM supermarket.sales_invoice_details sid
    INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
    WHERE DATE(si.invoice_date) = CURRENT_DATE
    GROUP BY sid.product_id
) daily_sales ON p.product_id = daily_sales.product_id
WHERE 
    p.is_active = true
    AND pc.category_name = 'Food' -- Filter theo category
ORDER BY 
    COALESCE(daily_sales.quantity_sold_today, 0) DESC, 
    si.current_quantity ASC;
```

## 7.2.2. Hàng sắp hết trên quầy nhưng còn trong kho

```sql
-- Query: Liệt kê hàng hóa sắp hết trên quầy nhưng vẫn còn trong kho
-- Đáp ứng yêu cầu: "Liệt kê toàn bộ hàng hóa sắp hết trên quầy nhưng vẫn còn trong kho"
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    ds.shelf_code,
    ds.shelf_name,
    si.current_quantity as shelf_quantity,
    p.low_stock_threshold,
    wi.warehouse_quantity,
    -- Số lượng có thể bổ sung từ kho
    LEAST(wi.warehouse_quantity, sl.max_quantity - si.current_quantity) as can_replenish_qty,
    sl.max_quantity as shelf_capacity,
    -- Mức độ ưu tiên bổ sung (càng thấp càng ưu tiên cao)
    CASE 
        WHEN si.current_quantity = 0 THEN 1 -- Hết hàng hoàn toàn
        WHEN si.current_quantity <= p.low_stock_threshold * 0.5 THEN 2 -- Rất thấp
        WHEN si.current_quantity <= p.low_stock_threshold THEN 3 -- Thấp
        ELSE 4
    END as replenish_priority,
    si.last_restocked,
    CURRENT_DATE - si.last_restocked::DATE as days_since_restocked
FROM supermarket.shelf_inventory si
INNER JOIN supermarket.products p ON si.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
INNER JOIN supermarket.shelf_layout sl ON si.shelf_id = sl.shelf_id 
                                        AND si.product_id = sl.product_id
INNER JOIN (
    -- Subquery: Tính tổng tồn kho warehouse
    SELECT 
        product_id, 
        SUM(quantity) as warehouse_quantity
    FROM supermarket.warehouse_inventory
    WHERE quantity > 0
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
WHERE 
    p.is_active = true
    AND si.current_quantity <= p.low_stock_threshold -- Sắp hết trên quầy
    AND wi.warehouse_quantity > 0 -- Còn trong kho
ORDER BY 
    replenish_priority ASC,
    si.current_quantity ASC,
    days_since_restocked DESC;
```

### Sử dụng View đã tạo sẵn cho yêu cầu này

```sql
-- Sử dụng view v_low_stock_alert đã được định nghĩa trước
SELECT * FROM supermarket.v_low_stock_alert
ORDER BY 
    CASE alert_type
        WHEN 'Out of stock on shelf' THEN 1
        WHEN 'Low stock on shelf' THEN 2
        ELSE 3
    END,
    shelf_quantity ASC;
```

## 7.2.3. Hàng hết trong kho nhưng còn trên quầy

```sql
-- Query: Liệt kê sản phẩm đã hết hàng trong kho nhưng vẫn còn hàng trên quầy
-- Đáp ứng yêu cầu: "Liệt kê toàn bộ sản phẩm đã hết hàng trong kho nhưng vẫn còn hàng trên quầy"
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    s.supplier_name,
    s.phone as supplier_phone,
    ds.shelf_code,
    ds.shelf_name,
    si.current_quantity as remaining_on_shelf,
    -- Dự đoán số ngày bán hết (dựa trên lịch sử 7 ngày gần nhất)
    COALESCE(recent_sales.avg_daily_sales, 0) as avg_daily_sales_7days,
    CASE 
        WHEN COALESCE(recent_sales.avg_daily_sales, 0) > 0 THEN
            CEIL(si.current_quantity / recent_sales.avg_daily_sales)
        ELSE NULL
    END as estimated_days_until_empty,
    si.last_restocked,
    -- Thông tin đơn hàng mới nhất với supplier này
    latest_po.latest_order_date,
    latest_po.latest_order_status,
    -- Cảnh báo mức độ
    CASE 
        WHEN COALESCE(recent_sales.avg_daily_sales, 0) = 0 THEN 'NO_SALES_DATA'
        WHEN si.current_quantity / COALESCE(recent_sales.avg_daily_sales, 1) <= 3 THEN 'CRITICAL' -- <= 3 ngày
        WHEN si.current_quantity / COALESCE(recent_sales.avg_daily_sales, 1) <= 7 THEN 'HIGH' -- <= 7 ngày  
        WHEN si.current_quantity / COALESCE(recent_sales.avg_daily_sales, 1) <= 14 THEN 'MEDIUM' -- <= 14 ngày
        ELSE 'LOW'
    END as alert_level
FROM supermarket.products p
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.suppliers s ON p.supplier_id = s.supplier_id
INNER JOIN supermarket.shelf_inventory si ON p.product_id = si.product_id
INNER JOIN supermarket.display_shelves ds ON si.shelf_id = ds.shelf_id
LEFT JOIN (
    -- Subquery: Tính trung bình bán hàng 7 ngày gần nhất
    SELECT 
        sid.product_id,
        AVG(daily_sales.daily_quantity) as avg_daily_sales
    FROM supermarket.sales_invoice_details sid
    INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
    INNER JOIN (
        SELECT 
            sid2.product_id,
            DATE(si2.invoice_date) as sale_date,
            SUM(sid2.quantity) as daily_quantity
        FROM supermarket.sales_invoice_details sid2
        INNER JOIN supermarket.sales_invoices si2 ON sid2.invoice_id = si2.invoice_id
        WHERE si2.invoice_date >= CURRENT_DATE - INTERVAL '7 days'
        GROUP BY sid2.product_id, DATE(si2.invoice_date)
    ) daily_sales ON sid.product_id = daily_sales.product_id
    GROUP BY sid.product_id
) recent_sales ON p.product_id = recent_sales.product_id
LEFT JOIN (
    -- Subquery: Thông tin đơn hàng mới nhất từ supplier
    SELECT 
        po.supplier_id,
        MAX(po.order_date) as latest_order_date,
        (ARRAY_AGG(po.status ORDER BY po.order_date DESC))[1] as latest_order_status
    FROM supermarket.purchase_orders po
    GROUP BY po.supplier_id
) latest_po ON s.supplier_id = latest_po.supplier_id
WHERE 
    p.is_active = true
    AND si.current_quantity > 0 -- Còn hàng trên quầy
    AND NOT EXISTS (
        -- Không tồn tại trong warehouse hoặc quantity = 0
        SELECT 1 
        FROM supermarket.warehouse_inventory wi 
        WHERE wi.product_id = p.product_id AND wi.quantity > 0
    )
ORDER BY 
    CASE alert_level
        WHEN 'CRITICAL' THEN 1
        WHEN 'HIGH' THEN 2  
        WHEN 'MEDIUM' THEN 3
        WHEN 'LOW' THEN 4
        ELSE 5
    END,
    si.current_quantity ASC;
```

## 7.2.4. Sắp xếp theo tổng tồn kho (kho + quầy)

```sql
-- Query: Liệt kê hàng hóa sắp xếp theo tổng số lượng (warehouse + shelf)
-- Đáp ứng yêu cầu: "Liệt kê toàn bộ hàng hóa, sắp xếp theo thứ tự tăng dần số lượng tổng trên quầy lẫn trong kho"
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    s.supplier_name,
    -- Tồn kho warehouse
    COALESCE(wi.warehouse_quantity, 0) as warehouse_stock,
    -- Tồn kho shelf  
    COALESCE(si.shelf_quantity, 0) as shelf_stock,
    -- Tổng tồn kho
    COALESCE(wi.warehouse_quantity, 0) + COALESCE(si.shelf_quantity, 0) as total_stock,
    p.low_stock_threshold,
    -- Phân loại trạng thái
    CASE 
        WHEN COALESCE(wi.warehouse_quantity, 0) + COALESCE(si.shelf_quantity, 0) = 0 THEN 'HẾT HÀNG'
        WHEN COALESCE(wi.warehouse_quantity, 0) + COALESCE(si.shelf_quantity, 0) <= p.low_stock_threshold THEN 'SẮP HẾT'
        WHEN COALESCE(si.shelf_quantity, 0) = 0 AND COALESCE(wi.warehouse_quantity, 0) > 0 THEN 'HẾT QUẦY'
        WHEN COALESCE(wi.warehouse_quantity, 0) = 0 AND COALESCE(si.shelf_quantity, 0) > 0 THEN 'HẾT KHO'
        ELSE 'BÌNH THƯỜNG'
    END as stock_status,
    -- Thông tin giá cả
    p.import_price,
    p.selling_price,
    -- Giá trị tồn kho
    (COALESCE(wi.warehouse_quantity, 0) + COALESCE(si.shelf_quantity, 0)) * p.import_price as inventory_value,
    -- Thời gian cập nhật gần nhất
    GREATEST(
        COALESCE(wi.last_updated_warehouse, '1900-01-01'::timestamp),
        COALESCE(si.last_updated_shelf, '1900-01-01'::timestamp)
    ) as last_inventory_update
FROM supermarket.products p
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.suppliers s ON p.supplier_id = s.supplier_id
LEFT JOIN (
    -- Subquery: Tổng tồn kho warehouse theo product
    SELECT 
        product_id,
        SUM(quantity) as warehouse_quantity,
        MAX(updated_at) as last_updated_warehouse
    FROM supermarket.warehouse_inventory
    GROUP BY product_id
) wi ON p.product_id = wi.product_id
LEFT JOIN (
    -- Subquery: Tổng tồn kho shelf theo product  
    SELECT 
        product_id,
        SUM(current_quantity) as shelf_quantity,
        MAX(updated_at) as last_updated_shelf
    FROM supermarket.shelf_inventory
    GROUP BY product_id
) si ON p.product_id = si.product_id
WHERE p.is_active = true
ORDER BY 
    -- Sắp xếp theo tổng tồn kho tăng dần (như yêu cầu đề tài)
    (COALESCE(wi.warehouse_quantity, 0) + COALESCE(si.shelf_quantity, 0)) ASC,
    p.product_name ASC;
```

### Sử dụng View có sẵn cho query này

```sql
-- Sử dụng view v_product_inventory_summary đã được định nghĩa
SELECT 
    product_code,
    product_name,
    category_name,
    supplier_name,
    warehouse_quantity,
    shelf_quantity,
    total_quantity,
    low_stock_threshold,
    stock_status
FROM supermarket.v_product_inventory_summary
ORDER BY total_quantity ASC, product_name ASC;
```

## Query tổng hợp: Dashboard tồn kho

```sql
-- Query tổng hợp cho dashboard quản lý tồn kho
WITH inventory_summary AS (
    SELECT 
        pc.category_name,
        COUNT(p.product_id) as total_products,
        COUNT(CASE WHEN si.shelf_quantity > 0 OR wi.warehouse_quantity > 0 THEN 1 END) as products_in_stock,
        COUNT(CASE WHEN si.shelf_quantity = 0 AND wi.warehouse_quantity = 0 THEN 1 END) as products_out_of_stock,
        COUNT(CASE WHEN si.shelf_quantity <= p.low_stock_threshold AND wi.warehouse_quantity > 0 THEN 1 END) as products_need_replenish,
        COUNT(CASE WHEN si.shelf_quantity > 0 AND wi.warehouse_quantity = 0 THEN 1 END) as products_out_in_warehouse,
        SUM(COALESCE(si.shelf_quantity, 0) + COALESCE(wi.warehouse_quantity, 0)) as total_inventory_units,
        SUM((COALESCE(si.shelf_quantity, 0) + COALESCE(wi.warehouse_quantity, 0)) * p.import_price) as total_inventory_value
    FROM supermarket.products p
    INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
    LEFT JOIN (
        SELECT product_id, SUM(quantity) as warehouse_quantity
        FROM supermarket.warehouse_inventory GROUP BY product_id
    ) wi ON p.product_id = wi.product_id
    LEFT JOIN (
        SELECT product_id, SUM(current_quantity) as shelf_quantity  
        FROM supermarket.shelf_inventory GROUP BY product_id
    ) si ON p.product_id = si.product_id
    WHERE p.is_active = true
    GROUP BY pc.category_id, pc.category_name
)
SELECT 
    category_name,
    total_products,
    products_in_stock,
    products_out_of_stock,
    products_need_replenish,
    products_out_in_warehouse,
    total_inventory_units,
    ROUND(total_inventory_value, 2) as total_inventory_value,
    ROUND((products_in_stock::NUMERIC / total_products * 100), 2) as in_stock_percentage,
    ROUND((products_need_replenish::NUMERIC / total_products * 100), 2) as need_replenish_percentage
FROM inventory_summary
ORDER BY total_inventory_value DESC;
```

## Kết luận phần 7.2

Các queries trong phần này đã thực hiện đầy đủ các yêu cầu theo dõi tồn kho của đề tài:

1. **7.2.1**: Liệt kê sản phẩm theo category/shelf với sắp xếp đa dạng (theo số lượng quầy, theo doanh số ngày)
2. **7.2.2**: Phát hiện sản phẩm sắp hết trên quầy nhưng còn trong kho → cần bổ sung
3. **7.2.3**: Phát hiện sản phẩm hết trong kho nhưng còn trên quầy → cần đặt hàng gấp
4. **7.2.4**: Xếp hạng sản phẩm theo tổng tồn kho tăng dần → quản lý tổng thể

Các queries có khả năng:

- **Tích hợp dữ liệu**: Kết hợp warehouse_inventory và shelf_inventory
- **Phân tích xu hướng**: Tính toán doanh số trung bình, dự đoán ngày hết hàng
- **Cảnh báo thông minh**: Phân loại mức độ ưu tiên và alert levels
- **Hỗ trợ quyết định**: Cung cấp thông tin supplier, lịch sử đặt hàng
- **Tối ưu hiệu suất**: Sử dụng Views và CTEs để tái sử dụng logic
