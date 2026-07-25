DROP TABLE IF EXISTS analytics.customer_features;

CREATE TABLE analytics.customer_features AS
SELECT
    t.customer_id,
    COUNT(*) AS total_transactions,
    SUM(t.amount) AS total_transaction_amount,
    AVG(t.amount) AS average_transaction_amount,
    MAX(t.amount) AS maximum_transaction,
    SUM(
        CASE
            WHEN t.transaction_type='CASH_DEPOSIT'
            THEN 1
            ELSE 0
        END
    ) AS cash_deposit_count,
    SUM(
        CASE
            WHEN t.transaction_type='WIRE_TRANSFER'
            THEN 1
            ELSE 0
        END
    ) AS wire_transfer_count,
    SUM(
        CASE
            WHEN t.suspicious_flag
            THEN 1
            ELSE 0
        END
    ) AS suspicious_transaction_count,

    COUNT(DISTINCT t.device_id) AS unique_devices,
    COUNT(DISTINCT t.merchant_id) AS unique_merchants,
    COUNT(DISTINCT t.destination_country) AS countries_transacted,
    MIN(t.transaction_timestamp) AS first_transaction,
    MAX(t.transaction_timestamp) AS last_transaction
FROM core.transactions t
GROUP BY t.customer_id;