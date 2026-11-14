USE ecommerce;

DROP TABLE IF EXISTS clean_order_items;
CREATE TABLE clean_order_items AS
SELECT
    oi.order_item_id, oi.order_id, o.customer_id,
    o.order_date, DATE(o.order_date) AS order_day,
    o.order_status, o.sales_channel, o.shipping_city, o.coupon_id,
    oi.product_id, p.category_id, p.brand_id, p.supplier_id,
    oi.quantity, oi.unit_price, oi.discount_pct, p.cost_price,
    oi.quantity * oi.unit_price                                   AS gross_amount,
    oi.quantity * oi.unit_price * oi.discount_pct / 100           AS discount_amount,
    oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)     AS net_amount,
    oi.quantity * p.cost_price                                    AS cost_amount,
    CASE WHEN r.order_item_id IS NOT NULL THEN 1 ELSE 0 END       AS is_returned,
    COALESCE(r.refund_amount, 0)                                  AS refund_amount,  -- return nahi = refund 0 (logically sahi)
    CASE WHEN o.order_status = 'Delivered' THEN 1 ELSE 0 END      AS is_delivered,
    CASE WHEN o.order_date < p.created_at THEN 1 ELSE 0 END       AS flag_before_product_launch,
    CASE WHEN r.return_date > '2026-10-28' THEN 1 ELSE 0 END      AS flag_future_return
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id
LEFT JOIN returns r ON r.order_item_id = oi.order_item_id;

ALTER TABLE clean_order_items
  ADD PRIMARY KEY (order_item_id),
  ADD INDEX idx_oi_order (order_id), ADD INDEX idx_oi_cust (customer_id),
  ADD INDEX idx_oi_prod (product_id), ADD INDEX idx_oi_day (order_day);


DROP TABLE IF EXISTS clean_orders;
CREATE TABLE clean_orders AS
SELECT
    o.order_id, o.customer_id, o.order_date, DATE(o.order_date) AS order_day,
    DATE_SUB(DATE(o.order_date), INTERVAL DAYOFMONTH(o.order_date) - 1 DAY) AS order_month,
    o.order_status, o.sales_channel, o.shipping_city, o.coupon_id,
    CASE WHEN o.coupon_id IS NULL THEN 0 ELSE 1 END AS has_coupon,
    p.payment_method, p.payment_status, p.amount AS payment_amount,
    s.courier, s.shipped_date, s.delivered_date,
    DATEDIFF(s.delivered_date, s.shipped_date) AS delivery_days,   -- In Transit = NULL (sahi hai)
    i.line_count, i.units, i.gross_amount, i.discount_amount, i.net_amount
FROM orders o
JOIN payments p ON p.order_id = o.order_id
LEFT JOIN shipments s ON s.order_id = o.order_id
JOIN (SELECT order_id, COUNT(*) AS line_count, SUM(quantity) AS units,
             SUM(gross_amount) AS gross_amount, SUM(discount_amount) AS discount_amount,
             SUM(net_amount) AS net_amount
      FROM clean_order_items GROUP BY order_id) i ON i.order_id = o.order_id;

ALTER TABLE clean_orders
  ADD PRIMARY KEY (order_id),
  ADD INDEX idx_o_cust (customer_id), ADD INDEX idx_o_month (order_month);

-- 3) clean_customers : email saaf + flags
DROP TABLE IF EXISTS clean_customers;
CREATE TABLE clean_customers AS
SELECT c.*,
       LOWER(TRIM(c.email))            AS email_clean,
       COALESCE(c.gender, 'Unknown')   AS gender_clean,   -- sirf reporting label, original NULL safe hai
       CASE WHEN d.email_clean IS NOT NULL THEN 1 ELSE 0 END AS is_dup_email
FROM customers c
LEFT JOIN (SELECT LOWER(TRIM(email)) AS email_clean FROM customers
           WHERE email IS NOT NULL GROUP BY LOWER(TRIM(email)) HAVING COUNT(*) > 1) d
       ON d.email_clean = LOWER(TRIM(c.email));
ALTER TABLE clean_customers ADD PRIMARY KEY (customer_id);


SELECT 'clean_order_items rows' AS chk, COUNT(*) AS val FROM clean_order_items UNION ALL
SELECT 'clean_orders rows', COUNT(*) FROM clean_orders UNION ALL
SELECT 'clean_customers rows', COUNT(*) FROM clean_customers UNION ALL
SELECT 'net_amount total', ROUND(SUM(net_amount),2) FROM clean_order_items UNION ALL
SELECT 'orders net total', ROUND(SUM(net_amount),2) FROM clean_orders UNION ALL
SELECT 'returned lines', SUM(is_returned) FROM clean_order_items UNION ALL
SELECT 'future return flags (all lines)', SUM(flag_future_return) FROM clean_order_items UNION ALL
SELECT 'dup email flags', SUM(is_dup_email) FROM clean_customers UNION ALL
SELECT 'emails with spaces after clean', COUNT(*) FROM clean_customers WHERE CHAR_LENGTH(email_clean) <> CHAR_LENGTH(TRIM(email_clean));

SELECT
  ROUND(SUM(net_amount), 2)                                                        AS booked_sales,
  ROUND(SUM(CASE WHEN is_delivered=1 THEN net_amount END), 2)                      AS delivered_sales_pre_return,
  ROUND(SUM(CASE WHEN is_delivered=1 AND is_returned=1 THEN net_amount END), 2)    AS returned_value,
  ROUND(SUM(CASE WHEN is_delivered=1 AND is_returned=0 THEN net_amount END), 2)    AS net_revenue,
  ROUND(SUM(CASE WHEN is_delivered=1 AND is_returned=0 THEN net_amount - cost_amount END), 2) AS gross_profit
FROM clean_order_items;

USE ecommerce;

CREATE OR REPLACE VIEW v_rev AS
SELECT * FROM clean_order_items
WHERE is_delivered = 1 AND is_returned = 0; 



-- Q1. What are the total revenue, profit, orders and AOV?
select count(distinct order_id) as total_orders,
sum(net_amount) as revenue,
sum(net_amount - cost_amount) as profit,       
round(sum(net_amount - cost_amount) * 100 / sum(net_amount), 2) as profit_margin_pct,      
round(sum(net_amount) / count(distinct order_id), 2) as aov 
from clean_order_items 
where flag_before_product_launch = 0 and flag_future_return = 0;

-- Q2. What is the monthly revenue and profit trend?
select date_format(order_date, '%Y-%m') as month,sum(net_amount) as revenue,
sum(net_amount - cost_amount) as profit 
from clean_order_items 
where flag_before_product_launch = 0 and flag_future_return = 0
group by month order by month;

-- Q3. What is the month-over-month revenue growth %?
select month,revenue,
round((revenue - lag(revenue) over (order by month)) * 100/ lag(revenue) over (order by month),2) as mom_growth_pct
from (select date_format(order_date, '%y-%m') as month,sum(net_amount) as revenue
from clean_order_items
where flag_before_product_launch = 0 and flag_future_return = 0
group by month) as t;

-- Q4. Top 10 products by revenue
select p.product_name,sum(i.net_amount) as revenue, sum(i.quantity) as units
from clean_order_items i
join products p
on i.product_id = p.product_id
where i.flag_before_product_launch = 0
and i.flag_future_return = 0
group by p.product_name
order by revenue desc
limit 10;

-- Q5. Categories with the highest revenue and margin
select c.category_name,sum(i.net_amount) as revenue,
round(sum(i.net_amount - i.cost_amount) * 100 / sum(i.net_amount),2) as margin_pct
from clean_order_items i
join categories c
on i.category_id = c.category_id
where i.flag_before_product_launch = 0
and i.flag_future_return = 0
group by c.category_name
order by revenue desc;

-- Q6. Best-performing brands
select b.brand_name,sum(i.net_amount) as revenue,sum(i.net_amount - i.cost_amount) as profit
from clean_order_items i
join brands b
on i.brand_id = b.brand_id
where i.flag_before_product_launch = 0
and i.flag_future_return = 0
group by b.brand_name
order by revenue desc
limit 10;

-- Q7. Revenue and AOV by sales channel
select sales_channel,count(*) as orders,
sum(net_amount) as revenue,round(avg(net_amount), 2) as aov
from clean_orders
group by sales_channel
order by revenue desc;

-- Q8. Percentage of repeat customers
select round(count(case when cnt > 1 then 1 end) * 100.0 / count(*),2) as repeat_pct
from (select customer_id,count(*) as cnt
from clean_orders
group by customer_id) as t;

-- Q9. Top 10 customers by spend
select customer_id,total_spend,
dense_rank() over (order by total_spend desc) as rnk
from (select customer_id,sum(net_amount) as total_spend
from clean_orders
group by customer_id) as t
order by rnk
limit 10;

-- Q10. Revenue by loyalty tier
select c.loyalty_tier,count(distinct c.customer_id) as customers,
sum(o.net_amount) as revenue,
round(sum(o.net_amount) / count(distinct c.customer_id),2) as revenue_per_customer
from clean_customers c
join clean_orders o
on c.customer_id = o.customer_id
where c.is_dup_email = 0
group by c.loyalty_tier
order by revenue desc;

-- Q11. Top 10 states and cities by sales
select c.state,c.city,sum(o.net_amount) as revenue
from clean_customers c
join clean_orders o
on c.customer_id = o.customer_id
group by c.state, c.city
order by revenue desc
limit 10;

-- Q12. Customers who signed up but never ordered
select
c.customer_id,
c.signup_date
from clean_customers c
left join clean_orders o
on c.customer_id = o.customer_id
where o.order_id is null;

-- Q13. Average delivery time by courier
select courier,round(avg(delivery_days), 2) as avg_delivery_days,count(*) as shipments
from clean_orders
where delivery_days is not null
group by courier
order by avg_delivery_days;

-- Q14. Return rate by category
select c.category_name,
round(sum(i.is_returned) * 100.0 / count(*), 2) as return_rate_pct,
sum(i.refund_amount) as total_refund
from clean_order_items i
join categories c
on i.category_id = c.category_id
where i.flag_future_return = 0
group by c.category_name
order by return_rate_pct desc;

-- Q15. Top return reasons
select reason,count(*) as returns,sum(refund_amount) as refund
from returns
group by reason
order by returns desc;

-- Q16. Suppliers with high return rates
select s.supplier_name,
s.rating,
round(sum(i.is_returned) * 100.0 / count(*), 2) as return_rate_pct
from clean_order_items i
join suppliers s
on i.supplier_id = s.supplier_id
group by s.supplier_name, s.rating
having count(*) > 50
order by return_rate_pct desc;

-- Q17. AOV for coupon and non-coupon orders
select has_coupon ,count(*) as orders,round(avg(net_amount), 2) as aov,
sum(discount_amount) as total_discount
from clean_orders
group by has_coupon;

-- Q18. Most-used coupon codes
select cp.code,cp.discount_type,count(*) as times_used,
sum(o.net_amount) as revenue
from clean_orders o
join coupons cp
on o.coupon_id = cp.coupon_id
group by cp.code, cp.discount_type
order by times_used desc;

-- Q19. Payment method and payment status split
select payment_method,payment_status,
count(*) as orders,sum(payment_amount) as amount
from clean_orders
group by payment_method, payment_status
order by orders desc;

-- Q20. Highly rated products with low sales
select p.product_name,round(avg(r.rating), 2) as avg_rating,
(select sum(i.quantity)
from clean_order_items i
where i.product_id = p.product_id) as units_sold
from products p
join reviews r
on p.product_id = r.product_id
group by p.product_id, p.product_name
having avg_rating >= 4
order by units_sold asc
limit 10;







