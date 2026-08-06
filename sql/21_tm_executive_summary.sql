DROP TABLE IF EXISTS analytics.tm_executive_summary;

CREATE TABLE analytics.tm_executive_summary AS
WITH overlap_by_rule AS (
    SELECT
        a.rule_id,
        COUNT(DISTINCT a.alert_id)
            FILTER (
                WHERE roa.rules_triggered > 1
            ) AS overlapping_alerts
    FROM core.alerts a
    JOIN analytics.rule_overlap_analysis roa
        ON a.transaction_id = roa.transaction_id
    GROUP BY a.rule_id
)
SELECT
    p.rule_id,
    p.rule_name,
    p.alerts_generated,
    p.investigations,
    p.cases,
    p.sar_reports,
    p.case_conversion_rate,
    p.sar_conversion_rate,
    f.false_positive_alerts,
    f.false_positive_rate,
    COALESCE(o.overlapping_alerts, 0) AS overlapping_alerts,
    ROUND( COALESCE(o.overlapping_alerts, 0)::NUMERIC/ NULLIF(p.alerts_generated, 0)* 100,2
    ) AS overlap_rate,
    ROUND( p.alerts_generated::NUMERIC/ SUM(p.alerts_generated) OVER ()* 100,2
    ) AS alert_volume_pct,
    CASE
        WHEN f.false_positive_rate >= 70
             OR ( p.alerts_generated >= 10000 AND p.sar_conversion_rate < 15)
            THEN 'Immediate Tuning'
        WHEN f.false_positive_rate >= 50 OR p.sar_conversion_rate < 10
            THEN 'Priority Review'
        WHEN f.false_positive_rate >= 30 OR p.sar_conversion_rate < 20
            THEN 'Monitor and Review'
        ELSE 'Performing Acceptably'
    END AS executive_recommendation
FROM analytics.tm_rule_performance p
LEFT JOIN analytics.false_positive_analysis f
    ON p.rule_id = f.rule_id
LEFT JOIN overlap_by_rule o
    ON p.rule_id = o.rule_id;