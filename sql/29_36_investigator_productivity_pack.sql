/* ============================================================
   INVESTIGATOR PRODUCTIVITY ANALYTICS PACK
   Analyses 29–36

   Completed separately:
   26 - Investigator Workload & Capacity
   27 - Investigation Throughput & TAT
   28 - Investigation SLA & Aging

   This file:
   29 - Disposition & False Positive Analysis
   30 - Escalation Analysis
   31 - Case Conversion Analysis
   32 - SAR Conversion Analysis
   33 - Investigator Action Intensity
   34 - Case Note Activity
   35 - Current Backlog Analysis
   36 - Investigator Performance Scorecard

   IMPORTANT:
   Metrics are descriptive operational analytics.
   They are not employee-performance ratings.
   ============================================================ */


/* ============================================================
   29. DISPOSITION & FALSE-POSITIVE ANALYSIS
   ============================================================ */

SELECT
    e.employee_id,
    e.employee_name,
    e.role_name,

    COUNT(*) FILTER (
        WHERE i.investigation_end IS NOT NULL
    ) AS completed_investigations,

    COUNT(*) FILTER (
        WHERE i.disposition = 'False Positive'
    ) AS false_positives,

    COUNT(*) FILTER (
        WHERE i.disposition = 'Closed - No Issue'
    ) AS closed_no_issue,

    COUNT(*) FILTER (
        WHERE i.disposition = 'Monitoring Required'
    ) AS monitoring_required,

    COUNT(*) FILTER (
        WHERE i.disposition = 'Escalated'
    ) AS escalated,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE i.disposition = 'False Positive'
        )
        /
        NULLIF(
            COUNT(*) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ), 0
        ),
        2
    ) AS false_positive_pct

FROM core.employees e

JOIN core.investigations i
    ON e.employee_id = i.investigator_id

WHERE e.role_name IN (
    'Investigator I',
    'Senior Investigator',
    'Lead Investigator'
)

GROUP BY
    e.employee_id,
    e.employee_name,
    e.role_name

ORDER BY false_positive_pct DESC;


/* ============================================================
   30. ESCALATION ANALYSIS
   ============================================================ */

SELECT
    e.employee_id,
    e.employee_name,
    e.role_name,

    COUNT(*) FILTER (
        WHERE i.investigation_end IS NOT NULL
    ) AS completed_investigations,

    COUNT(*) FILTER (
        WHERE i.disposition = 'Escalated'
    ) AS escalated_investigations,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE i.disposition = 'Escalated'
        )
        /
        NULLIF(
            COUNT(*) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ), 0
        ),
        2
    ) AS escalation_rate_pct

FROM core.employees e

JOIN core.investigations i
    ON e.employee_id = i.investigator_id

WHERE e.role_name IN (
    'Investigator I',
    'Senior Investigator',
    'Lead Investigator'
)

GROUP BY
    e.employee_id,
    e.employee_name,
    e.role_name

ORDER BY escalation_rate_pct DESC;


/* ============================================================
   31. CASE CONVERSION ANALYSIS

   Measures how frequently completed investigations ultimately
   resulted in a case.
   ============================================================ */

SELECT
    e.employee_id,
    e.employee_name,
    e.role_name,

    COUNT(DISTINCT i.investigation_id) FILTER (
        WHERE i.investigation_end IS NOT NULL
    ) AS completed_investigations,

    COUNT(DISTINCT c.case_id)
        AS cases_created,

    ROUND(
        100.0 *
        COUNT(DISTINCT c.case_id)
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ), 0
        ),
        2
    ) AS case_conversion_pct

FROM core.employees e

JOIN core.investigations i
    ON e.employee_id = i.investigator_id

LEFT JOIN core.cases c
    ON i.investigation_id = c.investigation_id

WHERE e.role_name IN (
    'Investigator I',
    'Senior Investigator',
    'Lead Investigator'
)

GROUP BY
    e.employee_id,
    e.employee_name,
    e.role_name

ORDER BY case_conversion_pct DESC;


/* ============================================================
   32. SAR CONVERSION ANALYSIS

   Shows downstream SAR outcomes from cases associated with
   each investigator's investigations.
   ============================================================ */

SELECT
    e.employee_id,
    e.employee_name,
    e.role_name,

    COUNT(DISTINCT c.case_id)
        AS total_cases,

    COUNT(DISTINCT s.sar_id)
        AS sar_reports,

    ROUND(
        100.0 *
        COUNT(DISTINCT s.sar_id)
        /
        NULLIF(COUNT(DISTINCT c.case_id), 0),
        2
    ) AS case_to_sar_conversion_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT s.sar_id)
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ), 0
        ),
        2
    ) AS investigation_to_sar_conversion_pct

FROM core.employees e

JOIN core.investigations i
    ON e.employee_id = i.investigator_id

LEFT JOIN core.cases c
    ON i.investigation_id = c.investigation_id

LEFT JOIN core.sar_reports s
    ON c.case_id = s.case_id

WHERE e.role_name IN (
    'Investigator I',
    'Senior Investigator',
    'Lead Investigator'
)

GROUP BY
    e.employee_id,
    e.employee_name,
    e.role_name

ORDER BY case_to_sar_conversion_pct DESC;


/* ============================================================
   33. INVESTIGATOR ACTION INTENSITY

   Measures investigative activity volume per investigation.
   ============================================================ */

WITH action_counts AS (

    SELECT
        investigation_id,
        COUNT(*) AS action_count

    FROM core.investigator_actions

    GROUP BY investigation_id
)

SELECT
    e.employee_id,
    e.employee_name,
    e.role_name,

    COUNT(DISTINCT i.investigation_id)
        AS assigned_investigations,

    COALESCE(SUM(ac.action_count), 0)
        AS total_actions,

    ROUND(
        COALESCE(SUM(ac.action_count), 0)::NUMERIC
        /
        NULLIF(COUNT(DISTINCT i.investigation_id), 0),
        2
    ) AS avg_actions_per_investigation

FROM core.employees e

JOIN core.investigations i
    ON e.employee_id = i.investigator_id

LEFT JOIN action_counts ac
    ON i.investigation_id = ac.investigation_id

WHERE e.role_name IN (
    'Investigator I',
    'Senior Investigator',
    'Lead Investigator'
)

GROUP BY
    e.employee_id,
    e.employee_name,
    e.role_name

ORDER BY avg_actions_per_investigation DESC;


/* ============================================================
   34. CASE NOTE ACTIVITY

   Uses author_employee_id from core.case_notes.
   ============================================================ */

SELECT
    e.employee_id,
    e.employee_name,
    e.role_name,

    COUNT(DISTINCT cn.case_id)
        AS cases_with_notes,

    COUNT(cn.case_id)
        AS total_case_notes,

    ROUND(
        COUNT(cn.case_id)::NUMERIC
        /
        NULLIF(COUNT(DISTINCT cn.case_id), 0),
        2
    ) AS avg_notes_per_case

FROM core.employees e

LEFT JOIN core.case_notes cn
    ON e.employee_id = cn.author_employee_id

WHERE e.role_name IN (
    'Investigator I',
    'Senior Investigator',
    'Lead Investigator'
)

GROUP BY
    e.employee_id,
    e.employee_name,
    e.role_name

ORDER BY total_case_notes DESC;


/* ============================================================
   35A. CURRENT BACKLOG BY INVESTIGATOR

   Current-state metric, unlike Analysis 28 which is a
   point-in-time June 30 SLA snapshot.
   ============================================================ */

SELECT
    e.employee_id,
    e.employee_name,
    e.role_name,
    e.workload_capacity,

    COUNT(*) FILTER (
        WHERE i.investigation_end IS NULL
    ) AS current_open_backlog,

    COUNT(*) FILTER (
        WHERE i.investigation_end IS NULL
          AND a.priority = 'High'
    ) AS high_priority_open,

    COUNT(*) FILTER (
        WHERE i.investigation_end IS NULL
          AND a.priority = 'Medium'
    ) AS medium_priority_open,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE i.investigation_end IS NULL
        )
        /
        NULLIF(e.workload_capacity, 0),
        2
    ) AS active_backlog_capacity_pct

FROM core.employees e

JOIN core.investigations i
    ON e.employee_id = i.investigator_id

JOIN core.alerts a
    ON i.alert_id = a.alert_id

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

ORDER BY current_open_backlog DESC;


/* ============================================================
   35B. CURRENT BACKLOG BY PRIORITY
   ============================================================ */

SELECT
    a.priority,

    COUNT(*) AS open_investigations,

    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS backlog_pct

FROM core.investigations i

JOIN core.alerts a
    ON i.alert_id = a.alert_id

WHERE i.investigation_end IS NULL

GROUP BY a.priority

ORDER BY open_investigations DESC;


/* ============================================================
   36. INVESTIGATOR PERFORMANCE SCORECARD

   IMPORTANT:
   This is a descriptive operational scorecard, NOT a ranking.

   Combines:
   - workload
   - completion
   - current backlog
   - TAT
   - false positives
   - escalations
   - cases
   - SARs
   - investigative actions
   ============================================================ */

WITH investigation_metrics AS (

    SELECT
        i.investigator_id,

        COUNT(*) AS assigned_investigations,

        COUNT(*) FILTER (
            WHERE i.investigation_end IS NOT NULL
        ) AS completed_investigations,

        COUNT(*) FILTER (
            WHERE i.investigation_end IS NULL
        ) AS open_investigations,

        COUNT(*) FILTER (
            WHERE i.disposition = 'False Positive'
        ) AS false_positives,

        COUNT(*) FILTER (
            WHERE i.disposition = 'Escalated'
        ) AS escalated_investigations,

        AVG(
            EXTRACT(
                EPOCH FROM (
                    i.investigation_end -
                    i.investigation_start
                )
            ) / 86400.0
        ) FILTER (
            WHERE i.investigation_end IS NOT NULL
        ) AS avg_tat_days

    FROM core.investigations i

    GROUP BY i.investigator_id
),

case_metrics AS (

    SELECT
        i.investigator_id,

        COUNT(DISTINCT c.case_id)
            AS cases_created,

        COUNT(DISTINCT s.sar_id)
            AS sar_reports

    FROM core.investigations i

    LEFT JOIN core.cases c
        ON i.investigation_id = c.investigation_id

    LEFT JOIN core.sar_reports s
        ON c.case_id = s.case_id

    GROUP BY i.investigator_id
),

action_metrics AS (

    SELECT
        investigator_id,
        COUNT(*) AS total_actions

    FROM core.investigator_actions

    GROUP BY investigator_id
)

SELECT
    e.employee_id,
    e.employee_name,
    e.role_name,
    e.workload_capacity,

    im.assigned_investigations,
    im.completed_investigations,
    im.open_investigations,

    ROUND(
        100.0 *
        im.assigned_investigations
        / NULLIF(e.workload_capacity, 0),
        2
    ) AS assigned_capacity_utilization_pct,

    ROUND(
        100.0 *
        im.open_investigations
        / NULLIF(e.workload_capacity, 0),
        2
    ) AS active_backlog_capacity_pct,

    ROUND(
        100.0 *
        im.completed_investigations
        / NULLIF(im.assigned_investigations, 0),
        2
    ) AS completion_rate_pct,

    ROUND(im.avg_tat_days, 2)
        AS avg_tat_days,

    im.false_positives,

    ROUND(
        100.0 *
        im.false_positives
        / NULLIF(im.completed_investigations, 0),
        2
    ) AS false_positive_pct,

    im.escalated_investigations,

    ROUND(
        100.0 *
        im.escalated_investigations
        / NULLIF(im.completed_investigations, 0),
        2
    ) AS escalation_rate_pct,

    COALESCE(cm.cases_created, 0)
        AS cases_created,

    ROUND(
        100.0 *
        COALESCE(cm.cases_created, 0)
        / NULLIF(im.completed_investigations, 0),
        2
    ) AS case_conversion_pct,

    COALESCE(cm.sar_reports, 0)
        AS sar_reports,

    ROUND(
        100.0 *
        COALESCE(cm.sar_reports, 0)
        / NULLIF(COALESCE(cm.cases_created, 0), 0),
        2
    ) AS case_to_sar_conversion_pct,

    COALESCE(am.total_actions, 0)
        AS total_actions,

    ROUND(
        COALESCE(am.total_actions, 0)::NUMERIC
        / NULLIF(im.assigned_investigations, 0),
        2
    ) AS avg_actions_per_investigation

FROM core.employees e

JOIN investigation_metrics im
    ON e.employee_id = im.investigator_id

LEFT JOIN case_metrics cm
    ON e.employee_id = cm.investigator_id

LEFT JOIN action_metrics am
    ON e.employee_id = am.investigator_id

WHERE e.role_name IN (
    'Investigator I',
    'Senior Investigator',
    'Lead Investigator'
)

ORDER BY
    e.role_name,
    e.employee_id;


/* ============================================================
   PACK VALIDATION
   ============================================================ */


/* V1 — Investigation reconciliation */

SELECT
    'Investigation reconciliation' AS validation,

    CASE
        WHEN COUNT(*) = 53392
         AND COUNT(*) FILTER (
                WHERE investigation_end IS NULL
             ) = 5339
         AND COUNT(*) FILTER (
                WHERE investigation_end IS NOT NULL
             ) = 48053
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS total,

    COUNT(*) FILTER (
        WHERE investigation_end IS NULL
    ) AS open_count,

    COUNT(*) FILTER (
        WHERE investigation_end IS NOT NULL
    ) AS closed_count

FROM core.investigations;


/* V2 — Every investigation assigned */

SELECT
    'Unassigned investigations' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.investigations

WHERE investigator_id IS NULL;


/* V3 — Open investigations cannot have disposition */

SELECT
    'Open investigation disposition' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.investigations

WHERE investigation_end IS NULL
  AND disposition IS NOT NULL;


/* V4 — Closed investigations require disposition */

SELECT
    'Closed investigation disposition' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.investigations

WHERE investigation_end IS NOT NULL
  AND disposition IS NULL;


/* V5 — Open investigations cannot have cases */

SELECT
    'Open investigations with cases' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.investigations i

JOIN core.cases c
    ON i.investigation_id = c.investigation_id

WHERE i.investigation_end IS NULL;


/* V6 — Investigation audit reconciliation */

SELECT
    'Investigation audit reconciliation' AS validation,

    CASE
        WHEN
            (SELECT COUNT(*)
             FROM core.audit_logs
             WHERE event_type =
                   'INVESTIGATION_ASSIGNED') = 53392

        AND

            (SELECT COUNT(*)
             FROM core.audit_logs
             WHERE event_type =
                   'INVESTIGATION_COMPLETED') = 48053

        THEN 'PASS'
        ELSE 'FAIL'
    END AS result;


/* V7 — No completion event for open investigations */

SELECT
    'Open investigation completion audit' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.investigations i

JOIN core.audit_logs al
    ON i.investigation_id =
       al.related_investigation_id

WHERE i.investigation_end IS NULL
  AND al.event_type =
      'INVESTIGATION_COMPLETED';


/* V8 — Case relationship integrity */

SELECT
    'Invalid case investigation links' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.cases c

LEFT JOIN core.investigations i
    ON c.investigation_id =
       i.investigation_id

WHERE c.investigation_id IS NOT NULL
  AND i.investigation_id IS NULL;


/* V9 — SAR relationship integrity */

SELECT
    'Invalid SAR case links' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.sar_reports s

LEFT JOIN core.cases c
    ON s.case_id = c.case_id

WHERE c.case_id IS NULL;


/* V10 — Action relationship integrity */

SELECT
    'Invalid action investigation links' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.investigator_actions ia

LEFT JOIN core.investigations i
    ON ia.investigation_id =
       i.investigation_id

WHERE i.investigation_id IS NULL;