DROP TABLE IF EXISTS analytics.case_conversion_analysis;

CREATE TABLE analytics.case_conversion_analysis AS
SELECT
    p.rule_id,
    p.rule_name,
    p.alerts_generated,
    p.investigations,
    p.cases,
    ROUND(p.cases::numeric/ NULLIF(p.alerts_generated, 0)* 100,2) AS alert_to_case_conversion_rate,
    ROUND(p.cases::numeric/ NULLIF(p.investigations, 0)* 100,2) AS investigation_to_case_conversion_rate,
    p.alerts_generated - p.cases AS alerts_not_converted_to_cases,
    CASE
        WHEN p.cases::numeric / NULLIF(p.alerts_generated, 0) >= 0.50
            THEN 'Strong'
        WHEN p.cases::numeric / NULLIF(p.alerts_generated, 0) >= 0.25
            THEN 'Moderate'
        ELSE 'Weak'
    END AS conversion_assessment
FROM analytics.tm_rule_performance p;