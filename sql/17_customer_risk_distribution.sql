DROP TABLE IF EXISTS analytics.customer_risk_distribution;

CREATE TABLE analytics.customer_risk_distribution AS
WITH customer_outcomes AS (
    SELECT
        cr.customer_id,
        cr.calculated_risk_score,
        cr.risk_band,
        COUNT(DISTINCT a.alert_id) AS alert_count,
        COUNT(DISTINCT ca.case_id) AS case_count,
        COUNT(DISTINCT s.sar_id) AS sar_count
    FROM analytics.customer_risk_scores_v2 cr
    LEFT JOIN core.alerts a
        ON cr.customer_id = a.customer_id
    LEFT JOIN core.case_alerts ca
        ON a.alert_id = ca.alert_id
    LEFT JOIN core.sar_reports s
        ON ca.case_id = s.case_id
    GROUP BY
        cr.customer_id,
        cr.calculated_risk_score,
        cr.risk_band
)
SELECT
    risk_band,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*)::NUMERIC/ SUM(COUNT(*)) OVER ()* 100,2) AS customer_population_pct,
    ROUND(AVG(calculated_risk_score),2) AS average_risk_score,
    SUM(alert_count) AS total_alerts,
    SUM(case_count) AS total_cases,
    SUM(sar_count) AS total_sars,
    ROUND(SUM(alert_count)::NUMERIC/ NULLIF(COUNT(*), 0),2) AS alerts_per_customer,
    ROUND(SUM(case_count)::NUMERIC/ NULLIF(SUM(alert_count), 0)* 100,2) AS alert_to_case_conversion_rate,
    ROUND( SUM(sar_count)::NUMERIC/ NULLIF(SUM(alert_count), 0)* 100,2) AS alert_to_sar_conversion_rate
FROM customer_outcomes
GROUP BY risk_band;