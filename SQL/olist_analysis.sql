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
