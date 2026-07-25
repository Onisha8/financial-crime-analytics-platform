------------------------------------------------------------
-- TM007 : Round Dollar Pattern
------------------------------------------------------------
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
    'TM007_' || transaction_id,
    transaction_id,
    customer_id,
    account_id,
    'TM007',
    transaction_timestamp::date,
    ROUND((68 + RANDOM()*18)::numeric,2),
    'Medium',
    'Open'
FROM core.transactions
WHERE
    amount >= 1000
    AND
    amount = ROUND(amount,0)
ON CONFLICT DO NOTHING;