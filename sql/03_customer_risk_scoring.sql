DROP TABLE IF EXISTS analytics.customer_risk_scores_v2;

CREATE TABLE analytics.customer_risk_scores_v2 AS
SELECT
    customer_id,
    ROUND(
        LEAST(
            100,
            (
                suspicious_transaction_count * 10
                +
                wire_transfer_count * 1.5
                +
                cash_deposit_count * 1.2
                +
                unique_devices * 2
                +
                countries_transacted * 5
            )
        )
    ,2) AS calculated_risk_score,
    CASE
        WHEN (
            suspicious_transaction_count * 10
            +
            wire_transfer_count * 1.5
            +
            cash_deposit_count * 1.2
            +
            unique_devices * 2
            +
            countries_transacted * 5
        ) >= 80 THEN 'Critical'
        WHEN (
            suspicious_transaction_count * 10
            +
            wire_transfer_count * 1.5
            +
            cash_deposit_count * 1.2
            +
            unique_devices * 2
            +
            countries_transacted * 5
        ) >= 60 THEN 'High'
        WHEN (
            suspicious_transaction_count * 10
            +
            wire_transfer_count * 1.5
            +
            cash_deposit_count * 1.2
            +
            unique_devices * 2
            +
            countries_transacted * 5
        ) >= 35 THEN 'Medium'
        ELSE 'Low'
    END AS risk_band
FROM analytics.customer_features;