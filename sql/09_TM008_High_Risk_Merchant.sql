------------------------------------------------------------
-- TM008: High-Risk Merchant
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
    'TM008_' || t.transaction_id,
    t.transaction_id,
    t.customer_id,
    t.account_id,
    'TM008',
    t.transaction_timestamp::DATE,
    ROUND((72 + RANDOM() * 20)::NUMERIC, 2),
    CASE
        WHEN m.merchant_risk_rating = 'High' THEN 'High'
        ELSE 'Medium'
    END,
    'Open'
FROM core.transactions t
JOIN core.merchants m
    ON t.merchant_id = m.merchant_id
WHERE t.transaction_type = 'CARD_PURCHASE'
  AND (
        m.merchant_risk_rating = 'High'
        OR m.merchant_category IN (
            'Money Services',
            'Crypto Exchange',
            'Gaming',
            'Jewelry',
            'Pawn Shop'
        )
      )
  AND t.amount >= 500
ON CONFLICT DO NOTHING;