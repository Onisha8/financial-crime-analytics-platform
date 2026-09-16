/*
============================================================
27 - Investigation Throughput & Turnaround Time Analysis
============================================================

Business Objective:
Measure investigation completion volume and turnaround time
across investigators and investigator roles.

Key Metrics:
- Assigned investigations
- Completed investigations
- Open investigations
- Average TAT
- Median TAT
- P90 TAT
- Minimum / Maximum TAT
- Completion rate

TAT:
Investigation End - Investigation Start
============================================================
*/

WITH investigation_metrics AS (

    SELECT
        i.investigation_id,
        i.investigator_id,
        e.employee_name,
        e.role_name,
        i.investigation_start,
        i.investigation_end,
        i.disposition,

        CASE
            WHEN i.investigation_end IS NOT NULL
            THEN EXTRACT(
                EPOCH FROM (
                    i.investigation_end - i.investigation_start
                )
            ) / 86400.0
        END AS tat_days

    FROM core.investigations i

    JOIN core.employees e
        ON i.investigator_id = e.employee_id
),

investigator_summary AS (

    SELECT
        investigator_id,
        employee_name,
        role_name,

        COUNT(*) AS assigned_investigations,

        COUNT(*) FILTER (
            WHERE investigation_end IS NOT NULL
        ) AS completed_investigations,

        COUNT(*) FILTER (
            WHERE investigation_end IS NULL
        ) AS open_investigations,

        ROUND(
            AVG(tat_days)
                FILTER (WHERE investigation_end IS NOT NULL),
            2
        ) AS avg_tat_days,

        ROUND(
            PERCENTILE_CONT(0.50)
            WITHIN GROUP (ORDER BY tat_days)
                FILTER (WHERE investigation_end IS NOT NULL)::NUMERIC,
            2
        ) AS median_tat_days,

        ROUND(
            PERCENTILE_CONT(0.90)
            WITHIN GROUP (ORDER BY tat_days)
                FILTER (WHERE investigation_end IS NOT NULL)::NUMERIC,
            2
        ) AS p90_tat_days,

        ROUND(
            MIN(tat_days)
                FILTER (WHERE investigation_end IS NOT NULL),
            2
        ) AS min_tat_days,

        ROUND(
            MAX(tat_days)
                FILTER (WHERE investigation_end IS NOT NULL),
            2
        ) AS max_tat_days

    FROM investigation_metrics

    GROUP BY
        investigator_id,
        employee_name,
        role_name
)

SELECT
    investigator_id,
    employee_name,
    role_name,

    assigned_investigations,
    completed_investigations,
    open_investigations,

    ROUND(
        completed_investigations::NUMERIC
        / NULLIF(assigned_investigations, 0)
        * 100,
        2
    ) AS completion_rate_pct,

    avg_tat_days,
    median_tat_days,
    p90_tat_days,
    min_tat_days,
    max_tat_days

FROM investigator_summary

ORDER BY
    avg_tat_days,
    investigator_id;