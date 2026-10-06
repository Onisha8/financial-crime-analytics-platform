------------------------------------------------------------
-- TM002 : High Risk Geography
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
    'TM002_' || transaction_id,
    transaction_id,
    customer_id,
    account_id,
    'TM002',
    transaction_timestamp::date,
    ROUND((80 + RANDOM()*15)::numeric,2),
    'High',
    'Open'
FROM core.transactions
WHERE
    (
        origin_country IN ('RU','NG','KY','PA','TR','AE')
        OR
        destination_country IN ('RU','NG','KY','PA','TR','AE')
    )
ON CONFLICT DO NOTHING;