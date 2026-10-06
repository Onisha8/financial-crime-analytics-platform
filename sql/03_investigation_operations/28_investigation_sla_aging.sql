/*
============================================================
28 - Investigation SLA & Aging Analysis
Point-in-Time Operational Snapshot
============================================================

Reporting Date: 2026-06-30

Synthetic SLA assumptions:
High   = 15 days
Medium = 30 days

NOTE:
These are project assumptions, not regulatory deadlines.

An investigation is considered OPEN as of the reporting date if:
1. it started on/before the reporting date, AND
2. it has no end date OR ended after the reporting date.

An investigation is considered CLOSED as of the reporting date if:
its investigation_end is on/before the reporting date.
============================================================
*/

WITH parameters AS (

    SELECT TIMESTAMP '2026-06-30 23:59:59' AS reporting_ts

),

base AS (

    SELECT
        i.investigation_id,
        i.investigator_id,
        i.investigation_start,
        i.investigation_end,
        i.disposition,

        a.priority,
        a.rule_id,

        p.reporting_ts,

        CASE
            WHEN a.priority = 'Critical' THEN 7
            WHEN a.priority = 'High'     THEN 15
            WHEN a.priority = 'Medium'   THEN 30
            WHEN a.priority = 'Low'      THEN 45
            ELSE 30
        END AS sla_days

    FROM core.investigations i

    JOIN core.alerts a
        ON i.alert_id = a.alert_id

    CROSS JOIN parameters p

    WHERE i.investigation_start <= p.reporting_ts
),

snapshot AS (

    SELECT
        *,

        CASE
            WHEN investigation_end IS NOT NULL
             AND investigation_end <= reporting_ts
                THEN 'Closed'
            ELSE 'Open'
        END AS snapshot_status,

        CASE
            WHEN investigation_end IS NOT NULL
             AND investigation_end <= reporting_ts
                THEN EXTRACT(
                    EPOCH FROM (
                        investigation_end - investigation_start
                    )
                ) / 86400.0

            ELSE EXTRACT(
                EPOCH FROM (
                    reporting_ts - investigation_start
                )
            ) / 86400.0
        END AS lifecycle_days

    FROM base
),

classified AS (

    SELECT
        *,

        CASE
            WHEN snapshot_status = 'Closed'
             AND lifecycle_days <= sla_days
                THEN 'Closed Within SLA'

            WHEN snapshot_status = 'Closed'
             AND lifecycle_days > sla_days
                THEN 'Closed Breached SLA'

            WHEN snapshot_status = 'Open'
             AND lifecycle_days <= sla_days
                THEN 'Open Within SLA'

            WHEN snapshot_status = 'Open'
             AND lifecycle_days > sla_days
                THEN 'Open Breached SLA'
        END AS sla_status

    FROM snapshot
)

SELECT
    sla_status,

    COUNT(*) AS investigation_count,

    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_investigations,

    ROUND(AVG(lifecycle_days), 2)
        AS avg_lifecycle_days,

    ROUND(AVG(sla_days), 2)
        AS avg_sla_days

FROM classified

GROUP BY sla_status

ORDER BY
    CASE sla_status
        WHEN 'Closed Within SLA'   THEN 1
        WHEN 'Closed Breached SLA' THEN 2
        WHEN 'Open Within SLA'     THEN 3
        WHEN 'Open Breached SLA'   THEN 4
    END;


/*
============================================================
SLA Performance by Alert Priority
============================================================
*/
WITH parameters AS (
    SELECT DATE '2026-07-31' AS reporting_date
),
base AS (
    SELECT
        i.investigation_id,
        i.investigation_end,
        a.priority,
        CASE
            WHEN a.priority = 'Critical' THEN 7
            WHEN a.priority = 'High'     THEN 15
            WHEN a.priority = 'Medium'   THEN 30
            WHEN a.priority = 'Low'      THEN 45
            ELSE 30
        END AS sla_days,
        CASE
            WHEN i.investigation_end IS NOT NULL
            THEN EXTRACT(EPOCH FROM (i.investigation_end - i.investigation_start)) / 86400.0
            ELSE EXTRACT(EPOCH FROM (p.reporting_date::timestamp - i.investigation_start)) / 86400.0
        END AS lifecycle_days
    FROM core.investigations i
    JOIN core.alerts a
        ON i.alert_id = a.alert_id
    CROSS JOIN parameters p
)
SELECT
    priority,
    COUNT(*) AS total_investigations,
    COUNT(*) FILTER (WHERE investigation_end IS NULL) AS open_investigations,
    COUNT(*) FILTER (WHERE lifecycle_days > sla_days) AS sla_breaches,
    ROUND(100.0 * COUNT(*) FILTER (WHERE lifecycle_days > sla_days)/ NULLIF(COUNT(*), 0), 2) AS breach_rate_pct,
    ROUND(AVG(lifecycle_days), 2) AS avg_lifecycle_days,
    MAX(sla_days) AS sla_days
FROM base
GROUP BY priority
ORDER BY
    CASE priority
        WHEN 'Critical' THEN 1
        WHEN 'High'     THEN 2
        WHEN 'Medium'   THEN 3
        WHEN 'Low'      THEN 4
        ELSE 5
    END;


/*
============================================================
Open Investigation Backlog Aging
============================================================
*/
WITH parameters AS (

    SELECT TIMESTAMP '2026-06-30 23:59:59' AS reporting_ts

),

open_as_of_reporting_date AS (

    SELECT
        i.investigation_id,
        i.investigator_id,
        a.priority,
        a.rule_id,

        EXTRACT(
            EPOCH FROM (
                p.reporting_ts - i.investigation_start
            )
        ) / 86400.0 AS age_days

    FROM core.investigations i

    JOIN core.alerts a
        ON i.alert_id = a.alert_id

    CROSS JOIN parameters p

    WHERE i.investigation_start <= p.reporting_ts

      AND (
            i.investigation_end IS NULL
            OR i.investigation_end > p.reporting_ts
          )
),

bucketed AS (

    SELECT
        *,

        CASE
            WHEN age_days <= 7  THEN '0-7 Days'
            WHEN age_days <= 15 THEN '8-15 Days'
            WHEN age_days <= 30 THEN '16-30 Days'
            WHEN age_days <= 60 THEN '31-60 Days'
            ELSE '60+ Days'
        END AS aging_bucket

    FROM open_as_of_reporting_date
)

SELECT
    aging_bucket,

    COUNT(*) AS open_investigations,

    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS backlog_pct

FROM bucketed

GROUP BY aging_bucket

ORDER BY
    CASE aging_bucket
        WHEN '0-7 Days'   THEN 1
        WHEN '8-15 Days'  THEN 2
        WHEN '16-30 Days' THEN 3
        WHEN '31-60 Days' THEN 4
        WHEN '60+ Days'   THEN 5
    END;
