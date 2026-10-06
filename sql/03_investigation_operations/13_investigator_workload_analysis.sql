DROP TABLE IF EXISTS analytics.investigator_workload;

CREATE TABLE analytics.investigator_workload AS
SELECT
    investigator_id,
    COUNT(*) AS investigations_completed,
    COUNT(DISTINCT c.case_id) AS cases_created,
    COUNT(DISTINCT s.sar_id) AS sars_filed,
    ROUND(COUNT(DISTINCT c.case_id)::numeric/COUNT(*) * 100,2) AS case_conversion_rate,
    ROUND(COUNT(DISTINCT s.sar_id)::numeric/COUNT(*) * 100,2) AS sar_conversion_rate
FROM core.investigations i
LEFT JOIN core.cases c
    ON i.investigation_id = c.investigation_id
LEFT JOIN core.sar_reports s
    ON c.case_id = s.case_id
GROUP BY investigator_id;