WITH buyer_months AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp) AS month
    FROM olist.orders o
    JOIN olist.customers c USING(customer_id)
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id, DATE_TRUNC('month', o.order_purchase_timestamp)
),
buyer_activity AS (
	SELECT 
		customer_unique_id,
		month,
		LAG(month) OVER (PARTITION BY customer_unique_id ORDER BY month) AS prev_month,
		LEAD(month) OVER (PARTITION BY customer_unique_id ORDER BY month) AS next_month
	FROM buyer_months
),
buyers_type AS (
	SELECT
	    customer_unique_id,
	    MONTH,
	    CASE
	    	WHEN prev_month IS NULL THEN 'new'
	    	WHEN month = prev_month + INTERVAL '1 month' THEN 'returning'
	    	ELSE 'new'
		END AS buyer_type,
		CASE
			WHEN month != next_month  - INTERVAL '1 month' OR next_month IS NULL THEN MONTH + INTERVAL '1 month'
		END churned_munth
	FROM buyer_activity
	ORDER BY MONTH
),
final_buyers AS (
	SELECT 
		MONTH,
		count(CASE WHEN buyer_type = 'new' THEN 1 END) AS new_buyers,
		count(CASE WHEN buyer_type = 'returning' THEN 1 END) AS returning_buyers
	FROM buyers_type bt
	GROUP BY MONTH
	ORDER BY MONTH
),
chur_users AS (
	SELECT *,
		CASE
			WHEN month != next_month  - INTERVAL '1 month' OR next_month IS NULL THEN MONTH + INTERVAL '1 month'
		END churned_month
	FROM buyer_activity
),
final_chur as(
	SELECT 
		churned_month,
		count(*) AS churned_users
	FROM chur_users
	WHERE churned_month IS NOT NULL 
	GROUP BY churned_month
	ORDER BY churned_month
),
base_metrics AS (
    SELECT 
		date_trunc('month',o.order_purchase_timestamp ) AS month,
		SUM(op.payment_value ) AS revenue,
		count(DISTINCT c.customer_unique_id ) AS customers,
		count(DISTINCT o.order_id ) AS orders,
		round(SUM(op.payment_value ) / count(DISTINCT o.order_id ),2) aov
	FROM olist.orders o 
	JOIN olist.order_payments op USING(order_id)
	JOIN olist.customers c USING (customer_id)
	WHERE o.order_status = 'delivered'
	GROUP BY month
	ORDER BY month
),
final_df AS (
	SELECT 
		b.month,
	    b.revenue,
	    b.orders,
	    b.aov,
	    b.customers,
	    fb.new_buyers,
	    fb.returning_buyers,
	    c.churned_users
	FROM base_metrics b
	LEFT JOIN final_buyers fb ON b.month = fb.month
	LEFT JOIN final_chur c ON b.month = c.churned_month
	ORDER BY b.month
)
SELECT *,
round(( churned_users::numeric / NULLIF(lag(customers) OVER (ORDER BY month), 0)) * 100 , 2)  AS churn_rate,
round(( returning_buyers::numeric / NULLIF(lag(customers) OVER (ORDER BY month), 0)) * 100 , 2) AS retention_rate
FROM final_df;

WITH LTV AS (
SELECT 
c.customer_unique_id ,
count(DISTINCT o.order_id ) AS orders,
sum(op.payment_value ) revenue
FROM olist.orders o
JOIN olist.customers c USING(customer_id)
JOIN olist.order_payments op USING (order_id )
WHERE o.order_status = 'delivered'
GROUP BY 1
)
SELECT 
round((SUM(revenue ) / sum(orders)) * (sum(orders) / count(customer_unique_id)),2) AS LTV
FROM LTV;

SELECT 
*
FROM olist.orders o
LIMIT 10;

SELECT 
*
FROM olist.order_payments 
LIMIT 10;

SELECT 
*
FROM olist.customers 
LIMIT 10;

SELECT order_id, COUNT(*), SUM(payment_value)
FROM olist.order_payments
GROUP BY order_id
HAVING COUNT(*) > 1
LIMIT 5;
