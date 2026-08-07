DROP TABLE IF EXISTS analytics.investigator_workload_summary;

CREATE TABLE analytics.investigator_workload_summary AS
SELECT
    e.employee_id AS investigator_id,
    e.employee_name,
    e.role_name,
    e.department,
    COUNT(i.investigation_id) AS assigned_investigations,
    COUNT(i.investigation_id)
        FILTER ( WHERE i.investigation_end IS NOT NULL ) AS completed_investigations,
    COUNT(i.investigation_id)
        FILTER ( WHERE i.investigation_end IS NULL ) AS open_investigations,
    ROUND(
        COUNT(i.investigation_id)
            FILTER (WHERE i.investigation_end IS NOT NULL)::NUMERIC/ NULLIF(COUNT(i.investigation_id), 0)* 100,2
    ) AS completion_rate,
    ROUND(
        COUNT(i.investigation_id)::NUMERIC/ NULLIF(SUM(COUNT(i.investigation_id)) OVER (),0)* 100,2
    ) AS workload_share_pct
FROM core.employees e
LEFT JOIN core.investigations i
    ON e.employee_id = i.investigator_id
WHERE e.department IN (
    'Financial Crime Operations',
    'Financial Crime Analytics'
)
GROUP BY
    e.employee_id,
    e.employee_name,
    e.role_name,
    e.department;