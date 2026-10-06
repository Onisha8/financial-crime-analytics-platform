-- Inject suspicious AML scenarios
-- Scenario 1: Structuring
UPDATE core.transactions
SET suspicious_flag = TRUE,
    scenario_type = 'Structuring'
WHERE transaction_id IN (
    SELECT transaction_id
    FROM core.transactions
    WHERE transaction_type = 'CASH_DEPOSIT'
      AND amount BETWEEN 8500 AND 10000
    LIMIT 3000
);

-- Scenario 2: Large Wire Transfer
UPDATE core.transactions
SET suspicious_flag = TRUE,
    scenario_type = 'Large Wire Transfer'
WHERE transaction_id IN (
    SELECT transaction_id
    FROM core.transactions
    WHERE transaction_type = 'WIRE_TRANSFER'
      AND amount >= 25000
    LIMIT 3000
);

-- Scenario 3: High Velocity Online Transfer
UPDATE core.transactions
SET suspicious_flag = TRUE,
    scenario_type = 'High Velocity Online Transfer'
WHERE transaction_id IN (
    SELECT transaction_id
    FROM core.transactions
    WHERE transaction_type = 'ONLINE_TRANSFER'
      AND amount >= 10000
    LIMIT 2500
);

-- Generate alerts from suspicious transactions
INSERT INTO core.alerts
(alert_id, transaction_id, customer_id, account_id, rule_id, alert_date, alert_score, priority, alert_status)
SELECT
    'AL' || LPAD(ROW_NUMBER() OVER (ORDER BY transaction_timestamp)::TEXT, 10, '0') AS alert_id,
    transaction_id,
    customer_id,
    account_id,
    CASE
        WHEN scenario_type = 'Structuring' THEN 'TM001'
        WHEN scenario_type = 'Large Wire Transfer' THEN 'TM006'
        WHEN scenario_type = 'High Velocity Online Transfer' THEN 'TM004'
    END AS rule_id,
    transaction_timestamp::DATE AS alert_date,
    CASE
        WHEN scenario_type = 'Large Wire Transfer' THEN ROUND((75 + RANDOM() * 20)::NUMERIC, 2)
        WHEN scenario_type = 'Structuring' THEN ROUND((70 + RANDOM() * 20)::NUMERIC, 2)
        WHEN scenario_type = 'High Velocity Online Transfer' THEN ROUND((65 + RANDOM() * 20)::NUMERIC, 2)
    END AS alert_score,
    CASE
        WHEN scenario_type = 'Large Wire Transfer' THEN 'High'
        WHEN scenario_type = 'Structuring' THEN 'High'
        WHEN scenario_type = 'High Velocity Online Transfer' THEN 'Medium'
    END AS priority,
    'Open' AS alert_status
FROM core.transactions
WHERE suspicious_flag = TRUE
ON CONFLICT (alert_id) DO NOTHING;
