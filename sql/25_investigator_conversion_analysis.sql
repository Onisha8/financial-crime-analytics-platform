DROP TABLE IF EXISTS analytics.investigator_conversion_analysis;

CREATE TABLE analytics.investigator_conversion_analysis AS
WITH investigator_outcomes AS (
    SELECT
        i.investigator_id,
        COUNT(DISTINCT i.investigation_id) AS investigations,
        COUNT(DISTINCT c.case_id) AS cases_created,
        COUNT(DISTINCT s.sar_id) AS sars_filed
    FROM core.investigations i
    LEFT JOIN core.cases c
        ON i.investigation_id = c.investigation_id
    LEFT JOIN core.sar_reports s
        ON c.case_id = s.case_id
    GROUP BY i.investigator_id
)
SELECT
    io.investigator_id,
    e.employee_name,
    io.investigations,
    io.cases_created,
    io.sars_filed,
    ROUND(io.cases_created::NUMERIC/ NULLIF(io.investigations, 0)* 100,2) AS investigation_to_case_rate,
    ROUND(io.sars_filed::NUMERIC/ NULLIF(io.investigations, 0)* 100,2) AS investigation_to_sar_rate,
    ROUND( io.sars_filed::NUMERIC/ NULLIF(io.cases_created, 0)* 100, 2 ) AS case_to_sar_rate,
    CASE
        WHEN io.sars_filed::NUMERIC / NULLIF(io.investigations, 0) >= 0.20
            THEN 'High Conversion'
        WHEN io.sars_filed::NUMERIC / NULLIF(io.investigations, 0) >= 0.10
            THEN 'Moderate Conversion'
        ELSE 'Low Conversion'
    END AS conversion_category
FROM investigator_outcomes io
LEFT JOIN core.employees e
    ON io.investigator_id = e.employee_id;