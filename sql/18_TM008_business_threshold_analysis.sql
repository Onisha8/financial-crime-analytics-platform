DROP TABLE IF EXISTS analytics.tm008_business_threshold_analysis;

CREATE TABLE analytics.tm008_business_threshold_analysis AS
WITH amount_thresholds AS (
    SELECT *
    FROM (
        VALUES
            (500::NUMERIC),
            (600::NUMERIC),
            (700::NUMERIC),
            (750::NUMERIC),
            (800::NUMERIC),
            (900::NUMERIC)
    ) AS x(proposed_amount_threshold)
),
tm008_outcomes AS (
    SELECT
        a.alert_id,
        t.amount,
        CASE
            WHEN COUNT(DISTINCT ca.case_id) > 0
            THEN 1
            ELSE 0
        END AS case_flag,
        CASE
            WHEN COUNT(DISTINCT s.sar_id) > 0
            THEN 1
            ELSE 0
        END AS sar_flag
    FROM core.alerts a
    JOIN core.transactions t
        ON a.transaction_id = t.transaction_id
    LEFT JOIN core.case_alerts ca
        ON a.alert_id = ca.alert_id
    LEFT JOIN core.sar_reports s
        ON ca.case_id = s.case_id
    WHERE a.rule_id = 'TM008'
    GROUP BY
        a.alert_id,
        t.amount
),
baseline AS (
    SELECT
        COUNT(*) AS baseline_alerts,
        SUM(case_flag) AS baseline_cases,
        SUM(sar_flag) AS baseline_sars
    FROM tm008_outcomes
)
SELECT
    th.proposed_amount_threshold,
    b.baseline_alerts,
    b.baseline_cases,
    b.baseline_sars,
    COUNT(*) FILTER (
        WHERE o.amount >= th.proposed_amount_threshold
    ) AS retained_alerts,
    b.baseline_alerts -
    COUNT(*) FILTER (
        WHERE o.amount >= th.proposed_amount_threshold
    ) AS alerts_reduced,
    ROUND(
        (b.baseline_alerts -
            COUNT(*) FILTER (WHERE o.amount >= th.proposed_amount_threshold)
        )::NUMERIC/ NULLIF(b.baseline_alerts, 0)* 100,2
    ) AS alert_reduction_pct,
    SUM(o.case_flag) FILTER (
        WHERE o.amount >= th.proposed_amount_threshold
    ) AS retained_cases,
    SUM(o.sar_flag) FILTER (
        WHERE o.amount >= th.proposed_amount_threshold
    ) AS retained_sars,
    ROUND(
        SUM(o.case_flag) FILTER (
            WHERE o.amount >= th.proposed_amount_threshold
        )::NUMERIC
        / NULLIF(b.baseline_cases, 0)* 100,2
    ) AS case_retention_pct,
    ROUND(
        SUM(o.sar_flag) FILTER (
            WHERE o.amount >= th.proposed_amount_threshold
        )::NUMERIC
        / 
        NULLIF(b.baseline_sars, 0)* 100,2
    ) AS sar_retention_pct,
    ROUND(
        SUM(o.sar_flag) FILTER (
            WHERE o.amount >= th.proposed_amount_threshold
        )::NUMERIC
        /
        NULLIF(
            COUNT(*) FILTER (
                WHERE o.amount >= th.proposed_amount_threshold
            ),0
        )* 100,2
    ) AS retained_sar_conversion_rate
FROM tm008_outcomes o
CROSS JOIN amount_thresholds th
CROSS JOIN baseline b
GROUP BY
    th.proposed_amount_threshold,
    b.baseline_alerts,
    b.baseline_cases,
    b.baseline_sars;