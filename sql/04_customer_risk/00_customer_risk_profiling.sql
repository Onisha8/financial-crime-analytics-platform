/* ============================================================
   CUSTOMER RISK ENGINE — ONE-TIME DATA PROFILING
   ============================================================ */


/* 1. Customer KYC / segment distributions */
SELECT
    'KYC_RISK' AS dimension,
    COALESCE(kyc_risk_rating, 'NULL') AS value,
    COUNT(*) AS record_count
FROM core.customers
GROUP BY kyc_risk_rating
UNION ALL

SELECT
    'PEP',
    COALESCE(
        politically_exposed_person_flag::TEXT,
        'NULL'
    ),
    COUNT(*)
FROM core.customers
GROUP BY politically_exposed_person_flag
UNION ALL

SELECT
    'SEGMENT',
    COALESCE(customer_segment, 'NULL'),
    COUNT(*)
FROM core.customers
GROUP BY customer_segment
UNION ALL

SELECT
    'INCOME_BAND',
    COALESCE(income_band, 'NULL'),
    COUNT(*)
FROM core.customers
GROUP BY income_band
ORDER BY dimension, record_count DESC;


/* 2. Transaction types */
SELECT
    transaction_type,
    COUNT(*) AS transactions,
    ROUND(SUM(amount), 2) AS total_amount,
    ROUND(AVG(amount), 2) AS avg_amount
FROM core.transactions
GROUP BY transaction_type
ORDER BY transactions DESC;


/* 3. Transaction channels */
SELECT
    channel,
    COUNT(*) AS transactions,
    ROUND(AVG(amount), 2) AS avg_amount
FROM core.transactions
GROUP BY channel
ORDER BY transactions DESC;


/* 4. Transaction status */
SELECT
    transaction_status,
    COUNT(*) AS transactions
FROM core.transactions
GROUP BY transaction_status
ORDER BY transactions DESC;


/* 5. Existing suspicious/scenario population */
SELECT
    suspicious_flag,
    scenario_type,
    COUNT(*) AS transactions,
    ROUND(SUM(amount), 2) AS total_amount
FROM core.transactions
GROUP BY
    suspicious_flag,
    scenario_type
ORDER BY transactions DESC;


/* 6. Transaction geography */
SELECT
    destination_country,
    COUNT(*) AS transactions,
    ROUND(SUM(amount), 2) AS total_amount
FROM core.transactions
GROUP BY destination_country
ORDER BY transactions DESC
LIMIT 20;


/* 7. Merchant risk */
SELECT
    merchant_risk_rating,
    COUNT(*) AS merchants
FROM core.merchants
GROUP BY merchant_risk_rating
ORDER BY merchants DESC;


/* 8. IP risk */
SELECT
    risk_rating,
    COUNT(*) AS ip_addresses
FROM core.ip_addresses
GROUP BY risk_rating
ORDER BY ip_addresses DESC;


/* 9. Login behavior */
SELECT
    login_success,
    mfa_used,
    COUNT(*) AS login_events
FROM core.login_events
GROUP BY
    login_success,
    mfa_used
ORDER BY login_events DESC;


/* 10. Overall volume reconciliation */
SELECT
    (SELECT COUNT(*) FROM core.customers) AS customers,
    (SELECT COUNT(*) FROM core.accounts) AS accounts,
    (SELECT COUNT(*) FROM core.transactions) AS transactions,
    (SELECT COUNT(*) FROM core.devices) AS devices,
    (SELECT COUNT(*) FROM core.ip_addresses) AS ip_addresses,
    (SELECT COUNT(*) FROM core.login_events) AS login_events,
    (SELECT COUNT(*) FROM core.beneficiaries) AS beneficiaries,
    (SELECT COUNT(*) FROM core.alerts) AS alerts,
    (SELECT COUNT(*) FROM core.cases) AS cases,
    (SELECT COUNT(*) FROM core.sar_reports) AS sars;