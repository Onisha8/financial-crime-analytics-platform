-------------------------------------------------------
-- 1. Overall Transaction Summary
-------------------------------------------------------
SELECT
    COUNT(*) AS total_transactions,
    SUM(amount) AS total_transaction_amount,
    AVG(amount) AS average_transaction_amount
FROM core.transactions;

-------------------------------------------------------
-- 2. Transactions by Type
-------------------------------------------------------
SELECT
    transaction_type,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS average_amount
FROM core.transactions
GROUP BY transaction_type
ORDER BY transaction_count DESC;

-------------------------------------------------------
-- 3. Alerts by Rule
-------------------------------------------------------
SELECT
    r.rule_name,
    COUNT(*) AS alert_count,
    AVG(a.alert_score) AS average_alert_score
FROM core.alerts a
JOIN reference.alert_rules r
ON a.rule_id = r.rule_id
GROUP BY r.rule_name
ORDER BY alert_count DESC;

-------------------------------------------------------
-- 4. Investigation Outcomes
-------------------------------------------------------
SELECT
    disposition,
    COUNT(*) AS investigations
FROM core.investigations
GROUP BY disposition
ORDER BY investigations DESC;

-------------------------------------------------------
-- 5. Case Status
-------------------------------------------------------
SELECT
    case_status,
    COUNT(*) AS total_cases
FROM core.cases
GROUP BY case_status;

-------------------------------------------------------
-- 6. SAR Filing Summary
-------------------------------------------------------
SELECT
    sar_status,
    COUNT(*) AS total_reports
FROM core.sar_reports
GROUP BY sar_status;

-------------------------------------------------------
-- 7. High-Risk Merchants
-------------------------------------------------------
SELECT
    merchant_category,
    merchant_risk_rating,
    COUNT(*) AS merchant_count
FROM core.merchants
GROUP BY merchant_category, merchant_risk_rating
ORDER BY merchant_count DESC;

-------------------------------------------------------
-- 8. Top 20 Customers by Transaction Volume
-------------------------------------------------------
SELECT
    customer_id,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_amount
FROM core.transactions
GROUP BY customer_id
ORDER BY total_amount DESC
LIMIT 20;

-------------------------------------------------------
-- 9. Monthly Transaction Trend
-------------------------------------------------------
SELECT
    DATE_TRUNC('month', transaction_timestamp) AS month,
    COUNT(*) AS transaction_count,
    SUM(amount) AS transaction_amount
FROM core.transactions
GROUP BY DATE_TRUNC('month', transaction_timestamp)
ORDER BY month;

-------------------------------------------------------
-- 10. Alert Conversion Funnel
-------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM core.alerts) AS alerts,
    (SELECT COUNT(*) FROM core.investigations) AS investigations,
    (SELECT COUNT(*) FROM core.cases) AS cases,
    (SELECT COUNT(*) FROM core.sar_reports) AS sar_reports;