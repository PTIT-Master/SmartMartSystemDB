# 7.4. QUERIES BÁO CÁO THỐNG KÊ

Phần này trình bày các câu lệnh SQL cho báo cáo và thống kê, bao gồm xếp hạng doanh thu, phân tích hiệu suất bán hàng, và các báo cáo quản lý khác nhau theo yêu cầu của đề tài.

## 7.4.1. Xếp hạng doanh thu sản phẩm theo tháng (RANK())

### A. Xếp hạng sản phẩm theo doanh thu tháng cụ thể

```sql
-- Query: Liệt kê hàng hóa sắp xếp theo doanh thu giảm dần trong tháng cụ thể
-- Đáp ứng yêu cầu: "Liệt kê hàng hóa, sắp xếp theo thứ tự giảm dần doanh thu của từng hàng hóa trong một tháng cụ thể"
SELECT 
    p.product_code,
    p.product_name,
    pc.category_name,
    s.supplier_name,
    SUM(sid.quantity) as total_quantity_sold,
    SUM(sid.subtotal) as total_revenue,
    AVG(sid.unit_price) as avg_selling_price,
    COUNT(DISTINCT si.invoice_id) as total_transactions,
    -- Ranking theo doanh thu
    RANK() OVER (ORDER BY SUM(sid.subtotal) DESC) as revenue_rank,
    ROW_NUMBER() OVER (ORDER BY SUM(sid.subtotal) DESC) as revenue_position,
    -- Ranking trong category
    RANK() OVER (PARTITION BY pc.category_name ORDER BY SUM(sid.subtotal) DESC) as category_rank,
    -- So sánh với trung bình category
    ROUND(
        (SUM(sid.subtotal) / AVG(SUM(sid.subtotal)) OVER (PARTITION BY pc.category_name) - 1) * 100, 
        2
    ) as vs_category_avg_percent,
    -- Thông tin bổ sung
    ROUND(SUM(sid.subtotal) / SUM(sid.quantity), 2) as revenue_per_unit,
    p.import_price,
    ROUND((AVG(sid.unit_price) - p.import_price) / p.import_price * 100, 2) as profit_margin_percent
FROM supermarket.sales_invoice_details sid
INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
INNER JOIN supermarket.products p ON sid.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
INNER JOIN supermarket.suppliers s ON p.supplier_id = s.supplier_id
WHERE 
    -- Lọc theo tháng cụ thể (ví dụ tháng 12/2024)
    EXTRACT(MONTH FROM si.invoice_date) = 12
    AND EXTRACT(YEAR FROM si.invoice_date) = 2024
GROUP BY 
    p.product_id, p.product_code, p.product_name, 
    pc.category_name, s.supplier_name, p.import_price
HAVING SUM(sid.quantity) > 0 -- Chỉ lấy sản phẩm có bán
ORDER BY total_revenue DESC;
```

### B. Xếp hạng top sản phẩm với DENSE_RANK và NTILE

```sql
-- Query: Phân tích chi tiết với nhiều ranking functions
WITH monthly_sales AS (
    SELECT 
        p.product_id,
        p.product_code,
        p.product_name,
        pc.category_name,
        SUM(sid.quantity) as total_quantity,
        SUM(sid.subtotal) as total_revenue,
        AVG(sid.unit_price) as avg_price,
        COUNT(DISTINCT si.invoice_id) as transaction_count,
        COUNT(DISTINCT si.customer_id) as unique_customers
    FROM supermarket.sales_invoice_details sid
    INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
    INNER JOIN supermarket.products p ON sid.product_id = p.product_id
    INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
    WHERE 
        EXTRACT(MONTH FROM si.invoice_date) = 12
        AND EXTRACT(YEAR FROM si.invoice_date) = 2024
    GROUP BY p.product_id, p.product_code, p.product_name, pc.category_name
)
SELECT 
    product_code,
    product_name,
    category_name,
    total_quantity,
    total_revenue,
    avg_price,
    transaction_count,
    unique_customers,
    -- Các loại ranking
    RANK() OVER (ORDER BY total_revenue DESC) as revenue_rank,
    DENSE_RANK() OVER (ORDER BY total_revenue DESC) as revenue_dense_rank,
    ROW_NUMBER() OVER (ORDER BY total_revenue DESC) as revenue_row_num,
    -- Phân nhóm thành 5 tiers (20% mỗi nhóm)
    NTILE(5) OVER (ORDER BY total_revenue DESC) as revenue_tier,
    -- Percentile ranking
    PERCENT_RANK() OVER (ORDER BY total_revenue) as revenue_percentile,
    -- Cumulative distribution
    CUME_DIST() OVER (ORDER BY total_revenue DESC) as revenue_cumulative_dist,
    -- So sánh với sản phẩm trước/sau
    LAG(total_revenue) OVER (ORDER BY total_revenue DESC) as prev_product_revenue,
    LEAD(total_revenue) OVER (ORDER BY total_revenue DESC) as next_product_revenue,
    -- Tính hiệu số với sản phẩm trước
    total_revenue - LAG(total_revenue) OVER (ORDER BY total_revenue DESC) as revenue_gap_with_prev
FROM monthly_sales
ORDER BY total_revenue DESC;
```

### C. Sử dụng View có sẵn cho product revenue

```sql
-- Sử dụng view v_product_revenue đã được định nghĩa
SELECT 
    product_code,
    product_name,
    category_name,
    total_transactions,
    total_quantity_sold,
    total_revenue,
    avg_revenue_per_transaction,
    month_year,
    RANK() OVER (
        PARTITION BY month_year 
        ORDER BY total_revenue DESC
    ) as monthly_rank
FROM supermarket.v_product_revenue
WHERE month_year = DATE_TRUNC('month', DATE('2024-12-01'))
ORDER BY total_revenue DESC;
```

## 7.4.2. Xếp hạng nhà cung cấp theo doanh thu

### A. Ranking nhà cung cấp theo tổng doanh thu

```sql
-- Query: Thống kê và xếp hạng nhà cung cấp theo doanh thu
-- Đáp ứng yêu cầu: "Thống kê doanh thu của các nhà cung cấp và xếp hạng các nhà cung cấp"
SELECT 
    s.supplier_id,
    s.supplier_code,
    s.supplier_name,
    s.contact_person,
    s.phone,
    -- Thống kê sản phẩm
    COUNT(DISTINCT p.product_id) as total_products,
    COUNT(DISTINCT po.order_id) as total_purchase_orders,
    -- Thống kê tài chính
    SUM(po.total_amount) as total_purchase_amount,
    SUM(sales_data.total_revenue) as total_sales_revenue,
    SUM(sales_data.total_quantity_sold) as total_quantity_sold,
    COUNT(DISTINCT sales_data.invoice_id) as total_sales_transactions,
    -- Tính profit
    SUM(sales_data.total_revenue) - SUM(po.total_amount) as gross_profit,
    CASE 
        WHEN SUM(po.total_amount) > 0 THEN
            ROUND(
                (SUM(sales_data.total_revenue) - SUM(po.total_amount)) / SUM(po.total_amount) * 100, 
                2
            )
        ELSE NULL
    END as profit_margin_percent,
    -- Rankings
    RANK() OVER (ORDER BY SUM(sales_data.total_revenue) DESC) as sales_revenue_rank,
    RANK() OVER (ORDER BY COUNT(DISTINCT p.product_id) DESC) as product_count_rank,
    RANK() OVER (ORDER BY (SUM(sales_data.total_revenue) - SUM(po.total_amount)) DESC) as profit_rank,
    -- Phân loại supplier
    NTILE(3) OVER (ORDER BY SUM(sales_data.total_revenue) DESC) as supplier_tier, -- 1=Top, 2=Medium, 3=Low
    -- Metrics bổ sung
    ROUND(SUM(sales_data.total_revenue) / NULLIF(COUNT(DISTINCT p.product_id), 0), 2) as avg_revenue_per_product,
    ROUND(SUM(sales_data.total_quantity_sold) / NULLIF(COUNT(DISTINCT p.product_id), 0), 2) as avg_quantity_per_product
FROM supermarket.suppliers s
LEFT JOIN supermarket.products p ON s.supplier_id = p.supplier_id AND p.is_active = true
LEFT JOIN supermarket.purchase_orders po ON s.supplier_id = po.supplier_id
LEFT JOIN (
    -- Subquery: Tổng hợp doanh số bán hàng theo supplier
    SELECT 
        p.supplier_id,
        si.invoice_id,
        SUM(sid.subtotal) as total_revenue,
        SUM(sid.quantity) as total_quantity_sold
    FROM supermarket.sales_invoice_details sid
    INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
    INNER JOIN supermarket.products p ON sid.product_id = p.product_id
    GROUP BY p.supplier_id, si.invoice_id
) sales_data ON s.supplier_id = sales_data.supplier_id
WHERE s.is_active = true
GROUP BY s.supplier_id, s.supplier_code, s.supplier_name, s.contact_person, s.phone
HAVING COUNT(DISTINCT p.product_id) > 0 -- Chỉ lấy supplier có sản phẩm
ORDER BY total_sales_revenue DESC;
```

### B. Sử dụng View có sẵn cho supplier performance

```sql
-- Sử dụng view v_supplier_performance đã được định nghĩa
SELECT 
    supplier_code,
    supplier_name,
    total_products,
    total_orders,
    total_purchase_amount,
    total_sales_revenue,
    profit_margin,
    RANK() OVER (ORDER BY total_sales_revenue DESC) as revenue_rank,
    RANK() OVER (ORDER BY profit_margin DESC) as profit_rank,
    CASE 
        WHEN RANK() OVER (ORDER BY total_sales_revenue DESC) <= 3 THEN 'TOP PERFORMER'
        WHEN RANK() OVER (ORDER BY total_sales_revenue DESC) <= 10 THEN 'GOOD PERFORMER'  
        ELSE 'AVERAGE PERFORMER'
    END as performance_category
FROM supermarket.v_supplier_performance
WHERE total_sales_revenue > 0
ORDER BY total_sales_revenue DESC;
```

### C. Phân tích chi tiết supplier theo thời gian

```sql
-- Query: Phân tích hiệu suất supplier theo tháng
SELECT 
    s.supplier_code,
    s.supplier_name,
    DATE_TRUNC('month', si.invoice_date) as sale_month,
    COUNT(DISTINCT si.invoice_id) as monthly_transactions,
    SUM(sid.quantity) as monthly_quantity,
    SUM(sid.subtotal) as monthly_revenue,
    AVG(sid.unit_price) as avg_selling_price,
    -- Ranking theo tháng
    RANK() OVER (
        PARTITION BY DATE_TRUNC('month', si.invoice_date) 
        ORDER BY SUM(sid.subtotal) DESC
    ) as monthly_rank,
    -- So sánh với tháng trước
    LAG(SUM(sid.subtotal)) OVER (
        PARTITION BY s.supplier_id 
        ORDER BY DATE_TRUNC('month', si.invoice_date)
    ) as prev_month_revenue,
    -- Tính growth rate
    CASE 
        WHEN LAG(SUM(sid.subtotal)) OVER (
            PARTITION BY s.supplier_id 
            ORDER BY DATE_TRUNC('month', si.invoice_date)
        ) > 0 THEN
            ROUND((
                SUM(sid.subtotal) / LAG(SUM(sid.subtotal)) OVER (
                    PARTITION BY s.supplier_id 
                    ORDER BY DATE_TRUNC('month', si.invoice_date)
                ) - 1
            ) * 100, 2)
        ELSE NULL
    END as monthly_growth_percent
FROM supermarket.suppliers s
INNER JOIN supermarket.products p ON s.supplier_id = p.supplier_id
INNER JOIN supermarket.sales_invoice_details sid ON p.product_id = sid.product_id
INNER JOIN supermarket.sales_invoices si ON sid.invoice_id = si.invoice_id
WHERE 
    s.is_active = true
    AND si.invoice_date >= CURRENT_DATE - INTERVAL '12 months' -- 12 tháng gần nhất
GROUP BY s.supplier_id, s.supplier_code, s.supplier_name, DATE_TRUNC('month', si.invoice_date)
ORDER BY sale_month DESC, monthly_revenue DESC;
```

## 7.4.3. Thống kê khách hàng thành viên và hóa đơn

### A. Thông tin khách hàng thành viên và lịch sử hóa đơn

```sql
-- Query: Hiển thị thông tin khách hàng thành viên và hóa đơn
-- Đáp ứng yêu cầu: "Hiển thị thông tin của các khách hàng thành viên và các hóa đơn của các khách hàng"
SELECT 
    c.customer_code,
    c.full_name,
    c.phone,
    c.email,
    c.address,
    c.membership_card_no,
    ml.level_name as membership_level,
    c.registration_date,
    c.total_spending,
    c.loyalty_points,
    -- Thống kê hóa đơn
    COUNT(si.invoice_id) as total_invoices,
    MIN(si.invoice_date) as first_purchase_date,
    MAX(si.invoice_date) as last_purchase_date,
    AVG(si.total_amount) as avg_order_value,
    SUM(si.total_amount) as total_order_value, -- Để so sánh với c.total_spending
    -- Thống kê sản phẩm
    COUNT(DISTINCT sid.product_id) as unique_products_purchased,
    SUM(sid.quantity) as total_items_purchased,
    -- Thống kê điểm thưởng
    SUM(si.points_earned) as total_points_earned,
    SUM(si.points_used) as total_points_used,
    -- Phân loại khách hàng
    CASE 
        WHEN c.total_spending >= 5000000 THEN 'VIP' -- >= 5M
        WHEN c.total_spending >= 2000000 THEN 'GOLD' -- >= 2M
        WHEN c.total_spending >= 500000 THEN 'SILVER' -- >= 500K
        ELSE 'BRONZE'
    END as customer_segment,
    -- Tần suất mua hàng
    CASE 
        WHEN MAX(si.invoice_date) >= CURRENT_DATE - INTERVAL '7 days' THEN 'ACTIVE_WEEKLY'
        WHEN MAX(si.invoice_date) >= CURRENT_DATE - INTERVAL '30 days' THEN 'ACTIVE_MONTHLY'
        WHEN MAX(si.invoice_date) >= CURRENT_DATE - INTERVAL '90 days' THEN 'ACTIVE_QUARTERLY'
        ELSE 'INACTIVE'
    END as activity_status,
    -- Tính số ngày trung bình giữa các lần mua
    CASE 
        WHEN COUNT(si.invoice_id) > 1 THEN
            ROUND(
                EXTRACT(EPOCH FROM (MAX(si.invoice_date) - MIN(si.invoice_date))) / 
                (COUNT(si.invoice_id) - 1) / 86400, -- Convert to days
                1
            )
        ELSE NULL
    END as avg_days_between_purchases
FROM supermarket.customers c
LEFT JOIN supermarket.membership_levels ml ON c.membership_level_id = ml.level_id
LEFT JOIN supermarket.sales_invoices si ON c.customer_id = si.customer_id
LEFT JOIN supermarket.sales_invoice_details sid ON si.invoice_id = sid.invoice_id
WHERE c.is_active = true
GROUP BY 
    c.customer_id, c.customer_code, c.full_name, c.phone, c.email, 
    c.address, c.membership_card_no, ml.level_name, c.registration_date,
    c.total_spending, c.loyalty_points
ORDER BY c.total_spending DESC;
```

### B. Sử dụng View có sẵn cho customer purchase history

```sql
-- Sử dụng view v_customer_purchase_history đã được định nghĩa
SELECT 
    customer_code,
    full_name,
    phone,
    membership_level,
    total_spending,
    loyalty_points,
    total_purchases,
    avg_purchase_amount,
    last_purchase_date,
    RANK() OVER (ORDER BY total_spending DESC) as spending_rank,
    CASE 
        WHEN total_spending >= 5000000 THEN 'VIP'
        WHEN total_spending >= 2000000 THEN 'PREMIUM'
        WHEN total_spending >= 1000000 THEN 'GOLD'
        WHEN total_spending >= 500000 THEN 'SILVER'
        ELSE 'BRONZE'
    END as customer_tier
FROM supermarket.v_customer_purchase_history
WHERE total_purchases > 0
ORDER BY total_spending DESC;
```

### C. Phân tích RFM (Recency, Frequency, Monetary) cho khách hàng

```sql
-- Query: Phân tích RFM để phân đoạn khách hàng
WITH customer_rfm AS (
    SELECT 
        c.customer_id,
        c.customer_code,
        c.full_name,
        -- Recency: Số ngày từ lần mua cuối
        CURRENT_DATE - MAX(si.invoice_date)::DATE as days_since_last_purchase,
        -- Frequency: Số lần mua hàng
        COUNT(DISTINCT si.invoice_id) as purchase_frequency,
        -- Monetary: Tổng giá trị mua hàng
        SUM(si.total_amount) as total_monetary_value,
        -- Thông tin bổ sung
        AVG(si.total_amount) as avg_order_value,
        MIN(si.invoice_date) as first_purchase_date,
        MAX(si.invoice_date) as last_purchase_date
    FROM supermarket.customers c
    INNER JOIN supermarket.sales_invoices si ON c.customer_id = si.customer_id
    WHERE 
        c.is_active = true
        AND si.invoice_date >= CURRENT_DATE - INTERVAL '12 months' -- 12 tháng gần nhất
    GROUP BY c.customer_id, c.customer_code, c.full_name
),
rfm_scores AS (
    SELECT 
        *,
        -- RFM Scoring (1-5 scale, 5 là tốt nhất)
        NTILE(5) OVER (ORDER BY days_since_last_purchase) as recency_score, -- Càng gần đây càng cao điểm
        NTILE(5) OVER (ORDER BY purchase_frequency DESC) as frequency_score,
        NTILE(5) OVER (ORDER BY total_monetary_value DESC) as monetary_score
    FROM customer_rfm
)
SELECT 
    customer_code,
    full_name,
    days_since_last_purchase,
    purchase_frequency,
    ROUND(total_monetary_value, 2) as total_monetary_value,
    ROUND(avg_order_value, 2) as avg_order_value,
    first_purchase_date,
    last_purchase_date,
    -- RFM Scores (đảo ngược recency để 5 là tốt nhất)
    (6 - recency_score) as recency_score, -- Flip để 5 = mua gần đây
    frequency_score,
    monetary_score,
    -- Tổng điểm RFM
    (6 - recency_score) + frequency_score + monetary_score as rfm_total_score,
    -- Phân loại khách hàng dựa trên RFM
    CASE 
        WHEN (6 - recency_score) >= 4 AND frequency_score >= 4 AND monetary_score >= 4 THEN 'CHAMPIONS'
        WHEN (6 - recency_score) >= 4 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'LOYAL_CUSTOMERS'
        WHEN (6 - recency_score) >= 4 AND frequency_score <= 2 AND monetary_score >= 4 THEN 'BIG_SPENDERS'
        WHEN (6 - recency_score) >= 3 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'POTENTIAL_LOYALISTS'
        WHEN (6 - recency_score) <= 2 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'AT_RISK'
        WHEN (6 - recency_score) <= 2 AND frequency_score <= 2 AND monetary_score >= 4 THEN 'CANT_LOSE_THEM'
        WHEN (6 - recency_score) >= 3 AND frequency_score <= 2 AND monetary_score <= 2 THEN 'NEW_CUSTOMERS'
        ELSE 'OTHERS'
    END as customer_segment
FROM rfm_scores
ORDER BY rfm_total_score DESC;
```

## 7.4.4. Phân tích hiệu suất bán hàng theo ngày trong tuần

### A. Doanh thu theo ngày trong tuần

```sql
-- Query: Phân tích hiệu suất bán hàng theo ngày trong tuần
SELECT 
    EXTRACT(DOW FROM si.invoice_date) as day_of_week_number, -- 0=Sunday, 1=Monday, ...
    TO_CHAR(si.invoice_date, 'Day') as day_of_week_name,
    COUNT(DISTINCT si.invoice_id) as total_transactions,
    COUNT(DISTINCT si.customer_id) as unique_customers,
    SUM(si.total_amount) as total_revenue,
    AVG(si.total_amount) as avg_transaction_value,
    SUM(sid.quantity) as total_items_sold,
    -- Metrics bổ sung
    ROUND(SUM(si.total_amount) / COUNT(DISTINCT si.invoice_id), 2) as revenue_per_transaction,
    ROUND(SUM(sid.quantity) / COUNT(DISTINCT si.invoice_id), 2) as items_per_transaction,
    -- Ranking theo ngày
    RANK() OVER (ORDER BY SUM(si.total_amount) DESC) as revenue_rank_by_day,
    -- Tỷ lệ phần trăm so với tổng tuần
    ROUND(
        SUM(si.total_amount) / SUM(SUM(si.total_amount)) OVER () * 100, 
        2
    ) as revenue_percentage_of_week,
    -- Phân loại hiệu suất
    CASE 
        WHEN RANK() OVER (ORDER BY SUM(si.total_amount) DESC) <= 2 THEN 'PEAK_DAYS'
        WHEN RANK() OVER (ORDER BY SUM(si.total_amount) DESC) <= 4 THEN 'GOOD_DAYS'
        ELSE 'SLOW_DAYS'
    END as performance_category
FROM supermarket.sales_invoices si
INNER JOIN supermarket.sales_invoice_details sid ON si.invoice_id = sid.invoice_id
WHERE 
    si.invoice_date >= CURRENT_DATE - INTERVAL '90 days' -- 3 tháng gần nhất
GROUP BY 
    EXTRACT(DOW FROM si.invoice_date),
    TO_CHAR(si.invoice_date, 'Day')
ORDER BY day_of_week_number;
```

### B. Chi tiết sản phẩm bán chạy theo từng ngày trong tuần

```sql
-- Query: Sản phẩm bán chạy nhất theo ngày trong tuần
SELECT 
    EXTRACT(DOW FROM si.invoice_date) as day_of_week_number,
    TO_CHAR(si.invoice_date, 'Day') as day_of_week_name,
    p.product_code,
    p.product_name,
    pc.category_name,
    SUM(sid.quantity) as total_quantity_sold,
    SUM(sid.subtotal) as total_revenue,
    COUNT(DISTINCT si.invoice_id) as transaction_count,
    ROUND(AVG(sid.unit_price), 2) as avg_selling_price,
    -- Ranking trong ngày
    RANK() OVER (
        PARTITION BY EXTRACT(DOW FROM si.invoice_date) 
        ORDER BY SUM(sid.quantity) DESC
    ) as quantity_rank_in_day,
    RANK() OVER (
        PARTITION BY EXTRACT(DOW FROM si.invoice_date) 
        ORDER BY SUM(sid.subtotal) DESC  
    ) as revenue_rank_in_day
FROM supermarket.sales_invoices si
INNER JOIN supermarket.sales_invoice_details sid ON si.invoice_id = sid.invoice_id
INNER JOIN supermarket.products p ON sid.product_id = p.product_id
INNER JOIN supermarket.product_categories pc ON p.category_id = pc.category_id
WHERE 
    si.invoice_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY 
    EXTRACT(DOW FROM si.invoice_date),
    TO_CHAR(si.invoice_date, 'Day'),
    p.product_id, p.product_code, p.product_name, pc.category_name
HAVING 
    RANK() OVER (
        PARTITION BY EXTRACT(DOW FROM si.invoice_date) 
        ORDER BY SUM(sid.subtotal) DESC
    ) <= 5 -- Top 5 mỗi ngày
ORDER BY day_of_week_number, revenue_rank_in_day;
```

### C. Phân tích theo giờ trong ngày

```sql
-- Query: Phân tích doanh thu theo giờ trong ngày
SELECT 
    EXTRACT(HOUR FROM si.invoice_date) as hour_of_day,
    COUNT(DISTINCT si.invoice_id) as transaction_count,
    SUM(si.total_amount) as hourly_revenue,
    AVG(si.total_amount) as avg_transaction_value,
    -- Phân loại khung giờ
    CASE 
        WHEN EXTRACT(HOUR FROM si.invoice_date) BETWEEN 6 AND 10 THEN 'MORNING (6-10)'
        WHEN EXTRACT(HOUR FROM si.invoice_date) BETWEEN 11 AND 14 THEN 'LUNCH (11-14)'
        WHEN EXTRACT(HOUR FROM si.invoice_date) BETWEEN 15 AND 18 THEN 'AFTERNOON (15-18)'
        WHEN EXTRACT(HOUR FROM si.invoice_date) BETWEEN 19 AND 22 THEN 'EVENING (19-22)'
        ELSE 'OFF_PEAK'
    END as time_segment,
    -- Ranking theo giờ
    RANK() OVER (ORDER BY SUM(si.total_amount) DESC) as hour_revenue_rank,
    -- Tỷ lệ phần trăm trong ngày
    ROUND(
        SUM(si.total_amount) / SUM(SUM(si.total_amount)) OVER () * 100, 
        2
    ) as revenue_percentage_of_day
FROM supermarket.sales_invoices si
WHERE 
    si.invoice_date >= CURRENT_DATE - INTERVAL '30 days'
    AND EXTRACT(HOUR FROM si.invoice_date) BETWEEN 6 AND 22 -- Giờ mở cửa
GROUP BY EXTRACT(HOUR FROM si.invoice_date)
ORDER BY hour_of_day;
```

## 7.4.5. Báo cáo doanh thu hàng ngày (30 ngày gần nhất)

### A. Daily sales summary

```sql
-- Query: Báo cáo doanh thu hàng ngày 30 ngày gần nhất
SELECT 
    DATE(si.invoice_date) as sale_date,
    TO_CHAR(si.invoice_date, 'Day') as day_of_week,
    COUNT(DISTINCT si.invoice_id) as total_transactions,
    COUNT(DISTINCT si.customer_id) as unique_customers,
    COUNT(DISTINCT CASE WHEN si.customer_id IS NOT NULL THEN si.customer_id END) as member_customers,
    COUNT(DISTINCT CASE WHEN si.customer_id IS NULL THEN si.invoice_id END) as non_member_transactions,
    SUM(si.total_amount) as daily_revenue,
    AVG(si.total_amount) as avg_transaction_value,
    MAX(si.total_amount) as highest_transaction,
    MIN(si.total_amount) as lowest_transaction,
    -- Thống kê items
    SUM(sid.quantity) as total_items_sold,
    COUNT(DISTINCT sid.product_id) as unique_products_sold,
    -- Metrics tính toán
    ROUND(SUM(si.total_amount) / COUNT(DISTINCT si.invoice_id), 2) as revenue_per_transaction,
    ROUND(SUM(sid.quantity) / COUNT(DISTINCT si.invoice_id), 2) as items_per_transaction,
    ROUND(
        COUNT(DISTINCT CASE WHEN si.customer_id IS NOT NULL THEN si.customer_id END)::NUMERIC / 
        NULLIF(COUNT(DISTINCT si.invoice_id), 0) * 100, 
        2
    ) as member_transaction_percentage,
    -- So sánh với ngày trước
    LAG(SUM(si.total_amount)) OVER (ORDER BY DATE(si.invoice_date)) as prev_day_revenue,
    CASE 
        WHEN LAG(SUM(si.total_amount)) OVER (ORDER BY DATE(si.invoice_date)) > 0 THEN
            ROUND((
                SUM(si.total_amount) / LAG(SUM(si.total_amount)) OVER (ORDER BY DATE(si.invoice_date)) - 1
            ) * 100, 2)
        ELSE NULL
    END as daily_growth_percent,
    -- Moving average 7 ngày
    ROUND(
        AVG(SUM(si.total_amount)) OVER (
            ORDER BY DATE(si.invoice_date) 
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2
    ) as moving_avg_7_days,
    -- Phân loại hiệu suất ngày
    CASE 
        WHEN RANK() OVER (ORDER BY SUM(si.total_amount) DESC) <= 5 THEN 'TOP_5_DAYS'
        WHEN SUM(si.total_amount) >= AVG(SUM(si.total_amount)) OVER () THEN 'ABOVE_AVERAGE'
        ELSE 'BELOW_AVERAGE'
    END as daily_performance
FROM supermarket.sales_invoices si
INNER JOIN supermarket.sales_invoice_details sid ON si.invoice_id = sid.invoice_id
WHERE 
    si.invoice_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE(si.invoice_date), TO_CHAR(si.invoice_date, 'Day')
ORDER BY sale_date DESC;
```

### B. Weekly and monthly aggregation

```sql
-- Query: Tổng hợp theo tuần và tháng
SELECT 
    'WEEK' as period_type,
    TO_CHAR(DATE_TRUNC('week', si.invoice_date), 'YYYY-MM-DD') as period_start,
    TO_CHAR(DATE_TRUNC('week', si.invoice_date) + INTERVAL '6 days', 'YYYY-MM-DD') as period_end,
    COUNT(DISTINCT si.invoice_id) as total_transactions,
    COUNT(DISTINCT si.customer_id) as unique_customers,
    SUM(si.total_amount) as total_revenue,
    AVG(si.total_amount) as avg_transaction_value,
    ROUND(
        SUM(si.total_amount) / 7.0, 2
    ) as avg_daily_revenue
FROM supermarket.sales_invoices si
WHERE si.invoice_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE_TRUNC('week', si.invoice_date)

UNION ALL

SELECT 
    'MONTH' as period_type,
    TO_CHAR(DATE_TRUNC('month', si.invoice_date), 'YYYY-MM-DD') as period_start,
    TO_CHAR(DATE_TRUNC('month', si.invoice_date) + INTERVAL '1 month' - INTERVAL '1 day', 'YYYY-MM-DD') as period_end,
    COUNT(DISTINCT si.invoice_id) as total_transactions,
    COUNT(DISTINCT si.customer_id) as unique_customers,
    SUM(si.total_amount) as total_revenue,
    AVG(si.total_amount) as avg_transaction_value,
    ROUND(
        SUM(si.total_amount) / EXTRACT(DAY FROM DATE_TRUNC('month', si.invoice_date) + INTERVAL '1 month' - INTERVAL '1 day'), 
        2
    ) as avg_daily_revenue
FROM supermarket.sales_invoices si
WHERE si.invoice_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE_TRUNC('month', si.invoice_date)
ORDER BY period_type DESC, period_start DESC;
```

### C. Dashboard tổng hợp 30 ngày

```sql
-- Query: Dashboard summary cho 30 ngày gần nhất
WITH daily_summary AS (
    SELECT 
        DATE(si.invoice_date) as sale_date,
        SUM(si.total_amount) as daily_revenue,
        COUNT(DISTINCT si.invoice_id) as daily_transactions,
        COUNT(DISTINCT si.customer_id) as daily_customers
    FROM supermarket.sales_invoices si
    WHERE si.invoice_date >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY DATE(si.invoice_date)
),
summary_stats AS (
    SELECT 
        COUNT(*) as total_days,
        SUM(daily_revenue) as total_revenue_30_days,
        AVG(daily_revenue) as avg_daily_revenue,
        MAX(daily_revenue) as best_day_revenue,
        MIN(daily_revenue) as worst_day_revenue,
        STDDEV(daily_revenue) as revenue_std_dev,
        SUM(daily_transactions) as total_transactions_30_days,
        AVG(daily_transactions) as avg_daily_transactions,
        SUM(daily_customers) as total_unique_customers_30_days
    FROM daily_summary
)
SELECT 
    'LAST_30_DAYS_SUMMARY' as report_type,
    total_days,
    ROUND(total_revenue_30_days, 2) as total_revenue,
    ROUND(avg_daily_revenue, 2) as avg_daily_revenue,
    ROUND(best_day_revenue, 2) as best_day_revenue,
    ROUND(worst_day_revenue, 2) as worst_day_revenue,
    ROUND(revenue_std_dev, 2) as revenue_standard_deviation,
    total_transactions_30_days,
    ROUND(avg_daily_transactions, 1) as avg_daily_transactions,
    total_unique_customers_30_days,
    ROUND(total_revenue_30_days / total_transactions_30_days, 2) as avg_transaction_value,
    ROUND((best_day_revenue - worst_day_revenue) / worst_day_revenue * 100, 2) as revenue_volatility_percent,
    -- Growth indicators (so với 30 ngày trước đó)
    (
        SELECT SUM(si2.total_amount)
        FROM supermarket.sales_invoices si2
        WHERE si2.invoice_date >= CURRENT_DATE - INTERVAL '60 days'
          AND si2.invoice_date < CURRENT_DATE - INTERVAL '30 days'
    ) as prev_30_days_revenue,
    ROUND((
        total_revenue_30_days / NULLIF(
            (SELECT SUM(si2.total_amount)
             FROM supermarket.sales_invoices si2
             WHERE si2.invoice_date >= CURRENT_DATE - INTERVAL '60 days'
               AND si2.invoice_date < CURRENT_DATE - INTERVAL '30 days'), 
            0
        ) - 1
    ) * 100, 2) as revenue_growth_vs_prev_30_days_percent
FROM summary_stats;
```

## Kết luận phần 7.4

Các queries trong phần này đã thực hiện đầy đủ các yêu cầu báo cáo thống kê của đề tài:

1. **7.4.1**: Xếp hạng sản phẩm theo doanh thu tháng với RANK(), DENSE_RANK(), NTILE()
2. **7.4.2**: Xếp hạng nhà cung cấp theo doanh thu và profit margin  
3. **7.4.3**: Thống kê khách hàng thành viên với phân tích RFM segmentation
4. **7.4.4**: Phân tích hiệu suất bán hàng theo ngày trong tuần và theo giờ
5. **7.4.5**: Báo cáo doanh thu hàng ngày với moving averages và growth analysis

**Tính năng nổi bật:**

- **Window Functions**: Sử dụng đầy đủ RANK(), ROW_NUMBER(), NTILE(), LAG(), LEAD()
- **Advanced Analytics**: RFM analysis, growth rates, moving averages, percentiles
- **Business Intelligence**: Customer segmentation, product performance tiers, supplier rankings
- **Dashboard Ready**: Queries tối ưu cho visualization và dashboard
- **Flexible Timeframes**: Dễ dàng thay đổi khoảng thời gian phân tích
