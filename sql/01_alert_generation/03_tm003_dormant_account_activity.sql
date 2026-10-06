------------------------------------------------------------
-- TM003 : Dormant Account Activity
------------------------------------------------------------
WITH ordered_transactions AS (
    SELECT
        transaction_id,
        account_id,
        customer_id,
        transaction_timestamp,
        amount,
        LAG(transaction_timestamp)
            OVER (
                PARTITION BY account_id
                ORDER BY transaction_timestamp
            ) AS previous_transaction
    FROM core.transactions
),
dormant_transactions AS (
    SELECT *
    FROM ordered_transactions
    WHERE
        previous_transaction IS NOT NULL
        AND
        transaction_timestamp - previous_transaction
            >= INTERVAL '180 days'
        AND
        amount >= 10000
)
INSERT INTO core.alerts
(
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
    'TM003_' || transaction_id,
    transaction_id,
    customer_id,
    account_id,
    'TM003',
    transaction_timestamp::date,
    ROUND((82 + RANDOM()*12)::numeric,2),
    'High',
    'Open'
FROM dormant_transactions
ON CONFLICT DO NOTHING;