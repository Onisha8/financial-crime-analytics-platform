WITH shared_devices AS (
    SELECT
        device_id
    FROM core.transactions
    WHERE device_id IS NOT NULL
    GROUP BY device_id
    HAVING COUNT(DISTINCT customer_id) >= 3
),
flagged_transactions AS (
    SELECT
        t.transaction_id,
        t.customer_id,
        t.account_id,
        t.transaction_timestamp,
        t.device_id
    FROM core.transactions t
    JOIN shared_devices sd
        ON t.device_id = sd.device_id
)
INSERT INTO core.alerts (
    alert_id,
    transaction_id,
    customer_id,
    account_id,
    rule_id,
    alert_date,
    alert_score,
    priority,
    alert_status
)
SELECT
    'TM005_' || transaction_id,
    transaction_id,
    customer_id,
    account_id,
    'TM005',
    transaction_timestamp::DATE,
    ROUND((70 + RANDOM() * 20)::NUMERIC, 2),
    'Medium',
    'Open'
FROM flagged_transactions
ON CONFLICT DO NOTHING;