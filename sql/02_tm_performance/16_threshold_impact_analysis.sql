DROP TABLE IF EXISTS analytics.threshold_impact_analysis;

CREATE TABLE analytics.threshold_impact_analysis AS
WITH thresholds AS (
    SELECT GENERATE_SERIES(60, 95, 5)::NUMERIC AS proposed_threshold
),
alert_outcomes AS (
    SELECT
        a.alert_id,
        a.rule_id,
        a.alert_score,
        CASE
            WHEN COUNT(DISTINCT ca.case_id) > 0
            THEN 1 ELSE 0
        END AS case_flag,
        CASE
            WHEN COUNT(DISTINCT s.sar_id) > 0
            THEN 1 ELSE 0
        END AS sar_flag
    FROM core.alerts a
    LEFT JOIN core.case_alerts ca
        ON a.alert_id = ca.alert_id
    LEFT JOIN core.sar_reports s
        ON ca.case_id = s.case_id
    GROUP BY
        a.alert_id,
        a.rule_id,
        a.alert_score
),
baseline AS (
    SELECT
        rule_id,
        COUNT(*) AS baseline_alerts,
        SUM(case_flag) AS baseline_cases,
        SUM(sar_flag) AS baseline_sars
    FROM alert_outcomes
    GROUP BY rule_id
)
SELECT
    ao.rule_id,
    ar.rule_name,
    t.proposed_threshold,
    b.baseline_alerts,
    COUNT(*) FILTER (WHERE ao.alert_score >= t.proposed_threshold) AS retained_alerts,
    b.baseline_alerts - COUNT(*) FILTER ( WHERE ao.alert_score >= t.proposed_threshold ) AS alerts_reduced,
    ROUND((b.baseline_alerts - COUNT(*) FILTER (
        WHERE ao.alert_score >= t.proposed_threshold))::NUMERIC/ NULLIF(b.baseline_alerts, 0)* 100,2
    ) AS alert_reduction_pct,
    SUM(ao.case_flag) FILTER (
        WHERE ao.alert_score >= t.proposed_threshold) AS retained_cases,
    SUM(ao.sar_flag) FILTER (
        WHERE ao.alert_score >= t.proposed_threshold) AS retained_sars,
    ROUND(
        SUM(ao.sar_flag) FILTER (
            WHERE ao.alert_score >= t.proposed_threshold)::NUMERIC/ 
            NULLIF(b.baseline_sars, 0)* 100,2) AS sar_retention_pct,
    ROUND(
        SUM(ao.case_flag) FILTER (
            WHERE ao.alert_score >= t.proposed_threshold)::NUMERIC/
        NULLIF(
            COUNT(*) FILTER (
                WHERE ao.alert_score >= t.proposed_threshold),0)* 100,2
    ) AS retained_case_conversion_rate,
    ROUND(
        SUM(ao.sar_flag) FILTER (
            WHERE ao.alert_score >= t.proposed_threshold)::NUMERIC/
        NULLIF(
            COUNT(*) FILTER (
                WHERE ao.alert_score >= t.proposed_threshold),0)* 100,2
    ) AS retained_sar_conversion_rate
FROM alert_outcomes ao
JOIN baseline b
    ON ao.rule_id = b.rule_id
JOIN reference.alert_rules ar
    ON ao.rule_id = ar.rule_id
CROSS JOIN thresholds t
GROUP BY
    ao.rule_id,
    ar.rule_name,
    t.proposed_threshold,
    b.baseline_alerts,
    b.baseline_cases,
    b.baseline_sars;