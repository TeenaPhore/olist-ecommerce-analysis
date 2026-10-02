-- =====================================================
-- 1. Monthly Revenue Trend
-- =====================================================

-- Identify the month with the largest month-over-month
-- decline in delivered revenue.

WITH monthly_revenue AS (
    SELECT
        EXTRACT(YEAR FROM order_purchase_timestamp) AS year,
        EXTRACT(MONTH FROM order_purchase_timestamp) AS month,
        SUM(price) AS revenue
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE order_status = 'delivered'
    GROUP BY
        EXTRACT(YEAR FROM order_purchase_timestamp),
        EXTRACT(MONTH FROM order_purchase_timestamp)
),
revenue_with_previous AS (
    SELECT
        year,
        month,
        revenue,
        LAG(revenue) OVER (
            ORDER BY year, month
        ) AS previous_revenue
    FROM monthly_revenue
)
SELECT
    year,
    month,
    revenue,
    revenue - previous_revenue AS revenue_change
FROM revenue_with_previous
ORDER BY revenue_change;

-- =====================================================
-- 2. Delivered Orders Decline
-- =====================================================

-- Compare delivered orders between November and December 2017
-- and calculate the order and percentage change.

WITH order_count AS (
    SELECT
        EXTRACT(YEAR FROM order_purchase_timestamp) AS year,
        EXTRACT(MONTH FROM order_purchase_timestamp) AS month,
        COUNT(order_id) AS total_orders
    FROM orders
    WHERE order_status = 'delivered'
    GROUP BY 1, 2
),
previous_order_count AS (
    SELECT
        year,
        month,
        total_orders,
        LAG(total_orders) OVER (
            ORDER BY year, month
        ) AS previous_order
    FROM order_count
)
SELECT
    year,
    month,
    total_orders,
    total_orders - previous_order AS order_change,
    ROUND(
        100.0 * (total_orders - previous_order)
        / NULLIF(previous_order, 0),
        2
    ) AS percentage_change
FROM previous_order_count
WHERE year = 2017
  AND month IN (11, 12)
ORDER BY 1, 2;

-- =====================================================
-- 3. Average Order Value (AOV)
-- =====================================================

-- Compare monthly Average Order Value for delivered orders.

WITH monthly_metrics AS (
    SELECT
        EXTRACT(YEAR FROM order_purchase_timestamp) AS year,
        EXTRACT(MONTH FROM order_purchase_timestamp) AS month,
        COUNT(DISTINCT o.order_id) AS total_orders,
        SUM(price) AS revenue
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE order_status = 'delivered'
    GROUP BY 1, 2
)
SELECT
    year,
    month,
    total_orders,
    revenue,
    ROUND(revenue / total_orders, 2) AS average_order_value
FROM monthly_metrics
WHERE year = 2017
  AND month IN (11, 12)
ORDER BY year, month;

-- =====================================================
-- 4. Overall Cancellation Rate
-- =====================================================

-- Compare the overall cancellation rate between
-- November and December 2017.

WITH monthly_orders AS (
    SELECT
        EXTRACT(YEAR FROM order_purchase_timestamp) AS year,
        EXTRACT(MONTH FROM order_purchase_timestamp) AS month,
        SUM(
            CASE
                WHEN order_status = 'canceled' THEN 1
                ELSE 0
            END
        ) AS cancelled_orders,
        COUNT(order_id) AS total_orders
    FROM orders
    GROUP BY 1, 2
)
SELECT
    year,
    month,
    cancelled_orders,
    total_orders,
    ROUND(
        100.0 * cancelled_orders / NULLIF(total_orders, 0),
        2
    ) AS cancellation_rate
FROM monthly_orders
WHERE year = 2017
  AND month IN (11, 12)
ORDER BY year, month;

-- =====================================================
-- 5. Seller Cancellation Analysis
-- =====================================================

-- Identify the sellers with the highest cancellation
-- rates in December 2017.

WITH seller_orders AS (
    SELECT
        oi.seller_id,
        COUNT(DISTINCT o.order_id) AS total_orders,
        COUNT(
            DISTINCT CASE
                WHEN o.order_status = 'canceled'
                THEN o.order_id
            END
        ) AS canceled_orders
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) = 2017
      AND EXTRACT(MONTH FROM o.order_purchase_timestamp) = 12
    GROUP BY oi.seller_id
),
seller_cancellation AS (
    SELECT
        seller_id,
        total_orders,
        canceled_orders,
        ROUND(
            canceled_orders * 100.0 / NULLIF(total_orders, 0),
            2
        ) AS cancellation_rate
    FROM seller_orders
)
SELECT
    seller_id,
    total_orders,
    canceled_orders,
    cancellation_rate
FROM (
    SELECT
        seller_id,
        total_orders,
        canceled_orders,
        cancellation_rate,
        DENSE_RANK() OVER (
            ORDER BY cancellation_rate DESC
        ) AS rnk
    FROM seller_cancellation
) ranked
WHERE rnk <= 10
ORDER BY cancellation_rate DESC;

-- =====================================================
-- 6. Average Delivery Time
-- =====================================================

-- Compare average delivery time from order approval
-- to customer delivery for November and December 2017.

SELECT
    EXTRACT(YEAR FROM order_purchase_timestamp) AS year,
    EXTRACT(MONTH FROM order_purchase_timestamp) AS month,
    ROUND(
        AVG(
            order_delivered_customer_date::date
            - order_approved_at::date
        ),
        2
    ) AS avg_delivery_days
FROM orders
WHERE order_status = 'delivered'
  AND order_approved_at IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL
  AND EXTRACT(YEAR FROM order_purchase_timestamp) = 2017
  AND EXTRACT(MONTH FROM order_purchase_timestamp) IN (11, 12)
GROUP BY 1, 2
ORDER BY 1, 2;

-- =====================================================
-- 7. Category Revenue Change
-- =====================================================

-- Compare delivered revenue by product category
-- between November and December 2017.

WITH category_revenue AS (
    SELECT
        pct.product_category_name_english,
        COALESCE(
            SUM(
                CASE
                    WHEN EXTRACT(YEAR FROM o.order_purchase_timestamp) = 2017
                     AND EXTRACT(MONTH FROM o.order_purchase_timestamp) = 11
                    THEN oi.price
                END
            ), 0
        ) AS nov_revenue,
        COALESCE(
            SUM(
                CASE
                    WHEN EXTRACT(YEAR FROM o.order_purchase_timestamp) = 2017
                     AND EXTRACT(MONTH FROM o.order_purchase_timestamp) = 12
                    THEN oi.price
                END
            ), 0
        ) AS dec_revenue
    FROM products p
    JOIN order_items oi
        ON oi.product_id = p.product_id
    JOIN orders o
        ON oi.order_id = o.order_id
    JOIN product_category_translation pct
        ON pct.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY pct.product_category_name_english
)
SELECT
    product_category_name_english,
    nov_revenue,
    dec_revenue,
    dec_revenue - nov_revenue AS revenue_change
FROM category_revenue
ORDER BY revenue_change ASC;

-- =====================================================
-- 8. Category-Level Cancellation Rate Comparison
-- =====================================================

-- Compare cancellation rates by product category
-- between November and December 2017.

WITH november_orders AS (
    SELECT
        pct.product_category_name_english AS product_category,
        COUNT(DISTINCT o.order_id) AS total_orders,
        COUNT(
            DISTINCT CASE
                WHEN o.order_status = 'canceled'
                THEN o.order_id
            END
        ) AS canceled_orders
    FROM products p
    JOIN order_items oi
        ON oi.product_id = p.product_id
    JOIN orders o
        ON o.order_id = oi.order_id
    JOIN product_category_translation pct
        ON pct.product_category_name = p.product_category_name
    WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) = 2017
      AND EXTRACT(MONTH FROM o.order_purchase_timestamp) = 11
    GROUP BY pct.product_category_name_english
),
december_orders AS (
    SELECT
        pct.product_category_name_english AS product_category,
        COUNT(DISTINCT o.order_id) AS total_orders,
        COUNT(
            DISTINCT CASE
                WHEN o.order_status = 'canceled'
                THEN o.order_id
            END
        ) AS canceled_orders
    FROM products p
    JOIN order_items oi
        ON oi.product_id = p.product_id
    JOIN orders o
        ON o.order_id = oi.order_id
    JOIN product_category_translation pct
        ON pct.product_category_name = p.product_category_name
    WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) = 2017
      AND EXTRACT(MONTH FROM o.order_purchase_timestamp) = 12
    GROUP BY pct.product_category_name_english
),
cancellation_rates AS (
    SELECT
        COALESCE(n.product_category, d.product_category) AS product_category,
        100.0 * n.canceled_orders / NULLIF(n.total_orders, 0) AS nov_rate,
        100.0 * d.canceled_orders / NULLIF(d.total_orders, 0) AS dec_rate
    FROM november_orders n
    FULL JOIN december_orders d
        ON n.product_category = d.product_category
)
SELECT
    product_category,
    ROUND(nov_rate, 2) AS nov_cancellation_rate,
    ROUND(dec_rate, 2) AS dec_cancellation_rate,
    ROUND(dec_rate - nov_rate, 2) AS change_in_percentage_points
FROM cancellation_rates
ORDER BY change_in_percentage_points DESC NULLS LAST;

-- =====================================================
-- 9. Monthly Unique Customer Activity
-- =====================================================

-- Calculate monthly unique customers for 2017.

SELECT
    EXTRACT(YEAR FROM o.order_purchase_timestamp) AS year,
    EXTRACT(MONTH FROM o.order_purchase_timestamp) AS month,
    COUNT(DISTINCT c.customer_id) AS unique_customers
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) = 2017
GROUP BY 1, 2
ORDER BY 1, 2;

-- =====================================================
-- 10. Customer Retention Analysis
-- =====================================================

-- Count customers who placed orders in both
-- November and December 2017.

WITH nov_customers AS (
    SELECT DISTINCT o.customer_id
    FROM orders o
    WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) = 2017
      AND EXTRACT(MONTH FROM o.order_purchase_timestamp) = 11
),
dec_customers AS (
    SELECT DISTINCT o.customer_id
    FROM orders o
    WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) = 2017
      AND EXTRACT(MONTH FROM o.order_purchase_timestamp) = 12
)
SELECT COUNT(*) AS returning_customers
FROM nov_customers n
INNER JOIN dec_customers d
    ON n.customer_id = d.customer_id;
-- =====================================================
-- 11. Customer Purchase Frequency
-- =====================================================

-- Identify customers who placed more than one order in 2017.

SELECT
    customer_id,
    COUNT(order_id) AS total_orders
FROM orders
WHERE EXTRACT(YEAR FROM order_purchase_timestamp) = 2017
GROUP BY customer_id
HAVING COUNT(order_id) > 1
ORDER BY total_orders DESC;
