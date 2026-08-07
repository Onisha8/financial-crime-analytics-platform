DROP TABLE IF EXISTS analytics.investigation_duration_sla;

CREATE TABLE analytics.investigation_duration_sla AS
WITH investigation_duration AS (
    SELECT
        i.investigation_id,
        i.investigator_id,
        i.alert_id,
        i.investigation_start,
        i.investigation_end,
        i.disposition,
        CASE
            WHEN i.investigation_end IS NOT NULL
            THEN
                EXTRACT( DAY FROM i.investigation_end - i.investigation_start )
            ELSE
                EXTRACT( DAY FROM CURRENT_TIMESTAMP - i.investigation_start )
        END AS investigation_age_days
    FROM core.investigations i
)

SELECT
    investigator_id,
    COUNT(*) AS total_investigations,
    ROUND(AVG(investigation_age_days),2) AS average_investigation_days,
    MIN(investigation_age_days) AS minimum_investigation_days,
    MAX(investigation_age_days) AS maximum_investigation_days,
    COUNT(*) FILTER ( WHERE investigation_age_days <= 5 ) AS within_sla,
    COUNT(*) FILTER ( WHERE investigation_age_days BETWEEN 6 AND 10 ) AS approaching_sla,
    COUNT(*) FILTER ( WHERE investigation_age_days BETWEEN 11 AND 15 ) AS sla_breaches,
    COUNT(*) FILTER ( WHERE investigation_age_days > 15 ) AS critical_breaches,
    ROUND( COUNT(*) FILTER ( WHERE investigation_age_days <= 5 )::NUMERIC / NULLIF(COUNT(*), 0) * 100, 2 ) AS sla_compliance_rate
FROM investigation_duration
GROUP BY investigator_id;