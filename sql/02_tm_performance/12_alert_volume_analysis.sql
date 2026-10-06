DROP TABLE IF EXISTS analytics.alert_volume_analysis;

CREATE TABLE analytics.alert_volume_analysis AS
SELECT
    rule_id,
    rule_name,
    alerts_generated,
    ROUND(alerts_generated::numeric/SUM(alerts_generated) OVER()*100,2) AS alert_volume_pct,
    SUM(alerts_generated) OVER() AS total_alerts,
    RANK() OVER(
        ORDER BY alerts_generated DESC
    ) AS volume_rank,
    CASE
        WHEN alerts_generated >= 10000 THEN 'Very High'
        WHEN alerts_generated >= 5000 THEN 'High'
        WHEN alerts_generated >= 2000 THEN 'Medium'
        ELSE 'Low'
    END AS workload_category
FROM analytics.tm_rule_performance;