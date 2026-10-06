DROP TABLE IF EXISTS analytics.rule_overlap_analysis;

CREATE TABLE analytics.rule_overlap_analysis AS
WITH transaction_rule_counts AS (
    SELECT
        transaction_id,
        customer_id,
        COUNT(DISTINCT rule_id) AS rules_triggered,
        STRING_AGG(
            DISTINCT rule_id,
            ', ' ORDER BY rule_id
        ) AS triggered_rules,
        COUNT(DISTINCT alert_id) AS alert_count
    FROM core.alerts
    GROUP BY
        transaction_id,
        customer_id
),
transaction_outcomes AS (
    SELECT
        a.transaction_id,
        COUNT(DISTINCT ca.case_id) AS case_count,
        COUNT(DISTINCT s.sar_id) AS sar_count
    FROM core.alerts a
    LEFT JOIN core.case_alerts ca
        ON a.alert_id = ca.alert_id
    LEFT JOIN core.sar_reports s
        ON ca.case_id = s.case_id
    GROUP BY a.transaction_id
)
SELECT
    trc.transaction_id,
    trc.customer_id,
    trc.rules_triggered,
    trc.triggered_rules,
    trc.alert_count,
    COALESCE(toc.case_count, 0) AS case_count,
    COALESCE(toc.sar_count, 0) AS sar_count,
    CASE
        WHEN trc.rules_triggered >= 3 THEN 'High Overlap'
        WHEN trc.rules_triggered = 2 THEN 'Moderate Overlap'
        ELSE 'No Overlap'
    END AS overlap_category
FROM transaction_rule_counts trc
LEFT JOIN transaction_outcomes toc
    ON trc.transaction_id = toc.transaction_id;