DROP TABLE IF EXISTS analytics.tm_model_tuning_dashboard;

CREATE TABLE analytics.tm_model_tuning_dashboard AS
SELECT
    rule_id,
    rule_name,
    alerts_generated,
    investigations,
    cases,
    sar_reports,
    average_alert_score,
    case_conversion_rate,
    sar_conversion_rate,
    ROUND(alerts_generated::numeric/SUM(alerts_generated) OVER()*100,2) AS alert_volume_pct,
    ROUND(sar_reports::numeric/NULLIF(investigations,0)*100,2) AS investigator_success_rate,
    CASE
        WHEN sar_conversion_rate >= 30 THEN 'Excellent'
        WHEN sar_conversion_rate >= 20 THEN 'Good'
        WHEN sar_conversion_rate >= 10 THEN 'Needs Review'
        ELSE 'Needs Tuning'
    END AS model_health
FROM analytics.tm_rule_performance;