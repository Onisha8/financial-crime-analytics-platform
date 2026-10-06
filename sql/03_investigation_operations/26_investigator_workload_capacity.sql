/*
============================================================
26 - Investigator Workload & Capacity Analysis
============================================================

Business Objective:
Evaluate investigation workload distribution across investigators
and compare assigned investigations against configured capacity.

Key Questions:
1. How many investigations are assigned to each investigator?
2. What percentage of configured capacity is being utilized?
3. Which investigators carry the highest workload?
4. How does workload differ by investigator role?

Primary Tables:
- core.employees
- core.investigations
============================================================
*/

WITH investigator_workload AS (

    SELECT
        e.employee_id,
        e.employee_name,
        e.role_name,
        e.workload_capacity,

        COUNT(i.investigation_id) AS assigned_investigations,

        COUNT(*) FILTER (
            WHERE i.investigation_end IS NOT NULL
        ) AS completed_investigations,

        COUNT(*) FILTER (
            WHERE i.investigation_end IS NULL
        ) AS open_investigations

    FROM core.employees e

    LEFT JOIN core.investigations i
        ON e.employee_id = i.investigator_id

    WHERE e.role_name IN (
        'Investigator I',
        'Senior Investigator',
        'Lead Investigator'
    )

    GROUP BY
        e.employee_id,
        e.employee_name,
        e.role_name,
        e.workload_capacity
)

SELECT
    employee_id,
    employee_name,
    role_name,
    workload_capacity,

    assigned_investigations,
    completed_investigations,
    open_investigations,

    ROUND(
        assigned_investigations::NUMERIC
        / NULLIF(workload_capacity, 0)
        * 100,
        2
    ) AS capacity_utilization_pct,

    workload_capacity - assigned_investigations
        AS remaining_capacity,

    RANK() OVER (
        ORDER BY assigned_investigations DESC
    ) AS workload_rank

FROM investigator_workload

ORDER BY
    assigned_investigations DESC,
    employee_id;