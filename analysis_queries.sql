/*
==================================================================
UK ONLINE RETAIL SALES ANALYSIS - SQL QUERIES
==================================================================
Dataset: Online Retail II (UCI ML Repository)
Database: PostgreSQL
Tables: clean_sales (779,425 rows), cancellations (19,494 rows)

Each query below answers a specific business question and includes
a brief note on the technique demonstrated.
==================================================================
*/


-- ==================================================================
-- QUERY 1: Monthly Revenue Trend
-- ==================================================================
-- Business question: How has revenue trended month over month?
-- Is there seasonality in the business?
--
-- Technique: Date truncation, aggregation, COUNT DISTINCT
-- ==================================================================

SELECT
    DATE_TRUNC('month', invoice_date) AS month,
    ROUND(SUM(total_price), 2) AS total_revenue,
    COUNT(DISTINCT invoice) AS num_orders,
    COUNT(DISTINCT customer_id) AS num_customers
FROM clean_sales
GROUP BY DATE_TRUNC('month', invoice_date)
ORDER BY month;

-- INSIGHT: Revenue peaks in November (£1.03M-£1.17M) both years,
-- consistent with Christmas gift-buying. February is consistently
-- the weakest month.


-- ==================================================================
-- QUERY 2: Top Customers by Revenue
-- ==================================================================
-- Business question: Who are our most valuable customers?
--
-- Technique: RANK() window function - ranks rows without collapsing
-- them into groups the way GROUP BY alone would.
-- ==================================================================

SELECT
    customer_id,
    country,
    ROUND(SUM(total_price), 2) AS total_spent,
    COUNT(DISTINCT invoice) AS num_orders,
    RANK() OVER (ORDER BY SUM(total_price) DESC) AS revenue_rank
FROM clean_sales
GROUP BY customer_id, country
ORDER BY total_spent DESC
LIMIT 20;

-- INSIGHT: Customer 16446 spent £168k across only 2 orders - a
-- notable outlier, likely a wholesale/business account rather than
-- a typical consumer.


-- ==================================================================
-- QUERY 2b: Revenue Concentration (Pareto / 80-20 Analysis)
-- ==================================================================
-- Business question: How much of our revenue comes from our top
-- customers? Are we overly dependent on a small group?
--
-- Technique: CTEs to break the query into readable steps.
-- SUM() OVER () with no ordering gives a grand total on every row.
-- SUM() OVER (ORDER BY ...) gives a running/cumulative total -
-- the core mechanic behind Pareto analysis.
-- ==================================================================

WITH customer_revenue AS (
    SELECT
        customer_id,
        SUM(total_price) AS total_spent
    FROM clean_sales
    GROUP BY customer_id
),
ranked_customers AS (
    SELECT
        customer_id,
        total_spent,
        RANK() OVER (ORDER BY total_spent DESC) AS revenue_rank,
        SUM(total_spent) OVER () AS overall_total_revenue,
        SUM(total_spent) OVER (ORDER BY total_spent DESC) AS running_total
    FROM customer_revenue
)
SELECT
    revenue_rank,
    customer_id,
    ROUND(total_spent, 2) AS total_spent,
    ROUND(running_total / overall_total_revenue * 100, 2) AS cumulative_pct_of_revenue
FROM ranked_customers
WHERE revenue_rank <= 100
ORDER BY revenue_rank;

-- INSIGHT: The top 100 customers (out of ~5,900) generate 37.6% of
-- total revenue - under 2% of customers driving over a third of
-- the business. Suggests a need for key-account management and
-- close churn monitoring of this group.


-- ==================================================================
-- QUERY 3: Customer Retention / Repeat Purchase Rate
-- ==================================================================
-- Business question: What percentage of customers come back and
-- buy again? A core retail KPI.
--
-- Technique: CASE WHEN to bucket raw numbers into business-meaningful
-- segments, combined with a window function to calculate percentages.
-- ==================================================================

WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT invoice) AS num_orders
    FROM clean_sales
    GROUP BY customer_id
)
SELECT
    CASE
        WHEN num_orders = 1 THEN 'One-time customer'
        WHEN num_orders BETWEEN 2 AND 5 THEN 'Repeat (2-5 orders)'
        ELSE 'Loyal (6+ orders)'
    END AS customer_segment,
    COUNT(*) AS num_customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_customers
FROM customer_orders
GROUP BY customer_segment
ORDER BY num_customers DESC;

-- INSIGHT: 72.4% of customers are repeat buyers (2+ orders), with
-- 30.6% classified as "loyal" (6+ orders). Only 27.6% are one-time
-- purchasers - a healthy retention profile overall.


-- ==================================================================
-- QUERY 4: Top Products by Revenue, Per Country
-- ==================================================================
-- Business question: What are the best-selling products, and does
-- this vary by country? Useful for inventory/marketing decisions.
--
-- Technique: PARTITION BY - resets the ranking separately within
-- each country/group, rather than ranking across the whole dataset.
-- This "top N per group" pattern is extremely common in interviews.
-- ==================================================================

WITH product_country_sales AS (
    SELECT
        country,
        description,
        SUM(total_price) AS revenue,
        SUM(quantity) AS units_sold
    FROM clean_sales
    GROUP BY country, description
),
ranked_products AS (
    SELECT
        country,
        description,
        revenue,
        units_sold,
        ROW_NUMBER() OVER (PARTITION BY country ORDER BY revenue DESC) AS rank_in_country
    FROM product_country_sales
)
SELECT country, description, ROUND(revenue, 2) AS revenue, units_sold, rank_in_country
FROM ranked_products
WHERE rank_in_country <= 3
    AND country IN ('United Kingdom', 'Germany', 'France', 'EIRE', 'Netherlands')
ORDER BY country, rank_in_country;

-- INSIGHT: "WHITE HANGING HEART T-LIGHT HOLDER" and "REGENCY
-- CAKESTAND 3 TIER" are consistent bestsellers in the UK and
-- Germany. "POSTAGE" and "Manual" appear as top revenue lines for
-- France/Germany - these are administrative entries, not products,
-- and were flagged as a data quality note rather than a genuine
-- sales insight.


-- ==================================================================
-- QUERY 5: RFM Customer Segmentation
-- ==================================================================
-- Business question: Which customers are at risk of churning, and
-- which are our best/most recently active customers?
--
-- Technique: NTILE(4) splits customers into quartiles based on a
-- metric - the core mechanic behind RFM (Recency, Frequency,
-- Monetary) segmentation, a widely used retail/marketing technique.
-- ==================================================================

WITH customer_rfm AS (
    SELECT
        customer_id,
        MAX(invoice_date) AS last_purchase_date,
        (SELECT MAX(invoice_date) FROM clean_sales) - MAX(invoice_date) AS recency_days,
        COUNT(DISTINCT invoice) AS frequency,
        SUM(total_price) AS monetary
    FROM clean_sales
    GROUP BY customer_id
),
rfm_scores AS (
    SELECT
        customer_id,
        recency_days,
        frequency,
        ROUND(monetary, 2) AS monetary,
        NTILE(4) OVER (ORDER BY recency_days ASC) AS recency_score,
        NTILE(4) OVER (ORDER BY frequency DESC) AS frequency_score,
        NTILE(4) OVER (ORDER BY monetary DESC) AS monetary_score
    FROM customer_rfm
)
SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    recency_score,
    frequency_score,
    monetary_score,
    CASE
        WHEN recency_score = 1 AND frequency_score = 1 AND monetary_score = 1 THEN 'Champions'
        WHEN recency_score >= 3 AND frequency_score >= 3 THEN 'At Risk / Lapsed'
        WHEN recency_score = 1 THEN 'Recent Customers'
        ELSE 'Needs Attention'
    END AS segment
FROM rfm_scores
ORDER BY monetary DESC
LIMIT 20;

-- INSIGHT: Most top-spending customers are "Champions" (recent,
-- frequent, high-value). Notable exception: customer 12346 has
-- spent £77,556 historically but hasn't purchased in 325 days -
-- a high-value customer flagged as a churn risk worth targeted
-- re-engagement.
