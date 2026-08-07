DROP TABLE IF EXISTS analytics.investigator_disposition_analysis;

CREATE TABLE analytics.investigator_disposition_analysis AS
SELECT
    i.investigator_id,
    e.employee_name,
    COUNT(*) AS total_investigations,
    COUNT(*) FILTER ( WHERE i.disposition = 'False Positive' ) AS false_positives,
    COUNT(*) FILTER ( WHERE i.disposition = 'Closed - No Issue' ) AS closed_no_issue,
    COUNT(*) FILTER ( WHERE i.disposition = 'Monitoring Required' ) AS monitoring_required,
    COUNT(*) FILTER ( WHERE i.disposition = 'Escalated' ) AS escalated,
    ROUND(
        COUNT(*) FILTER ( WHERE i.disposition = 'False Positive' )::NUMERIC / NULLIF(COUNT(*), 0)* 100, 2
    ) AS false_positive_rate,
    ROUND(
        COUNT(*) FILTER ( WHERE i.disposition = 'Escalated' )::NUMERIC / NULLIF(COUNT(*), 0) * 100, 2
    ) AS escalation_rate,
    ROUND(
        COUNT(*) FILTER ( WHERE i.disposition IN ( 'Escalated', 'Monitoring Required' ) )::NUMERIC / NULLIF(COUNT(*), 0) * 100, 2
    ) AS further_review_rate
FROM core.investigations i
LEFT JOIN core.employees e
    ON i.investigator_id = e.employee_id
GROUP BY
    i.investigator_id,
    e.employee_name;