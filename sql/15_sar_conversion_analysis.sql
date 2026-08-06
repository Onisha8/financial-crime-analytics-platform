DROP TABLE IF EXISTS analytics.sar_conversion_analysis;

CREATE TABLE analytics.sar_conversion_analysis AS
SELECT
    p.rule_id,
    p.rule_name,
    p.alerts_generated,
    p.investigations,
    p.cases,
    p.sar_reports,
    ROUND(p.sar_reports::NUMERIC/ NULLIF(p.alerts_generated, 0)* 100,2) AS alert_to_sar_conversion_rate,
    ROUND(p.sar_reports::NUMERIC/ NULLIF(p.investigations, 0)* 100,2) AS investigation_to_sar_conversion_rate,
    ROUND(p.sar_reports::NUMERIC/ NULLIF(p.cases, 0)* 100,2) AS case_to_sar_conversion_rate,
    p.alerts_generated - p.sar_reports AS alerts_not_converted_to_sars,
    CASE
        WHEN p.sar_reports::NUMERIC/ NULLIF(p.alerts_generated, 0) >= 0.20
            THEN 'High Yield'
        WHEN p.sar_reports::NUMERIC/ NULLIF(p.alerts_generated, 0) >= 0.10
            THEN 'Moderate Yield'
        WHEN p.sar_reports::NUMERIC/ NULLIF(p.alerts_generated, 0) >= 0.05
            THEN 'Low Yield'
        ELSE 'Very Low Yield'
    END AS sar_yield_assessment
FROM analytics.tm_rule_performance p;