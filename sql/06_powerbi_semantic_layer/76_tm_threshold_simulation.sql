/* ============================================================
   76. TM ALERT SCORE THRESHOLD SIMULATION (Power BI view)
   ------------------------------------------------------------
   Reporting version of analysis 45 (37_46 pack). Replaces the
   hard-coded analytics.tm_threshold_simulation table, so the
   visual always reflects the current alert/case/SAR data.

   Question answered:
     If alerts scoring below a candidate threshold had been
     suppressed, how much investigator workload would be saved,
     and how many cases/SARs would have been missed?

   Grain: one row per candidate threshold.
   Thresholds: 65-90 in steps of 5. 65 is the baseline: the
   lowest alert score in the data, so nothing is suppressed.

   This is a retrospective what-if on synthetic data. It does not
   change any rule threshold, and it is not a recommendation:
   choosing a threshold is a risk-appetite decision.
   ============================================================ */

DROP VIEW  IF EXISTS analytics.vw_tm_threshold_simulation;
DROP TABLE IF EXISTS analytics.tm_threshold_simulation;   -- old hard-coded values

CREATE VIEW analytics.vw_tm_threshold_simulation AS

WITH thresholds AS (
    SELECT generate_series(65, 90, 5)::NUMERIC AS threshold
),

/* One row per alert with its downstream outcome
   (each alert has one investigation; each case at most one SAR). */
outcomes AS (
    SELECT
        a.alert_id,
        a.alert_score,
        i.investigation_end IS NOT NULL      AS is_completed,
        i.disposition = 'False Positive'     AS is_false_positive,
        c.case_id IS NOT NULL                AS has_case,
        s.sar_id  IS NOT NULL                AS has_sar
    FROM core.alerts a
    JOIN core.investigations i  ON i.alert_id = a.alert_id
    LEFT JOIN core.cases c      ON c.investigation_id = i.investigation_id
    LEFT JOIN core.sar_reports s ON s.case_id = c.case_id
),

baseline AS (
    SELECT
        COUNT(*)                          AS alerts,
        COUNT(*) FILTER (WHERE has_case)  AS cases,
        COUNT(*) FILTER (WHERE has_sar)   AS sars
    FROM outcomes
),

retained AS (
    SELECT
        t.threshold,
        COUNT(*)                                              AS alerts_retained,
        COUNT(*) FILTER (WHERE o.has_case)                    AS cases_retained,
        COUNT(*) FILTER (WHERE o.has_sar)                     AS sars_retained,
        COUNT(*) FILTER (WHERE o.is_completed)                AS completed_retained,
        COUNT(*) FILTER (WHERE o.is_completed AND o.is_false_positive) AS false_positives_retained
    FROM thresholds t
    LEFT JOIN outcomes o ON o.alert_score >= t.threshold
    GROUP BY t.threshold
)

SELECT
    r.threshold::INTEGER                                                   AS threshold,

    /* Workload */
    r.alerts_retained,
    ROUND(100.0 * r.alerts_retained / b.alerts, 2)                         AS alerts_retained_pct,
    b.alerts - r.alerts_retained                                           AS alerts_suppressed,
    ROUND(100.0 - 100.0 * r.alerts_retained / b.alerts, 2)                 AS workload_reduction_pct,

    /* Outcomes retained */
    r.cases_retained,
    ROUND(100.0 * r.cases_retained / NULLIF(b.cases, 0), 2)                AS cases_retained_pct,
    r.sars_retained,
    ROUND(100.0 * r.sars_retained / NULLIF(b.sars, 0), 2)                  AS sars_retained_pct,
    b.sars - r.sars_retained                                               AS sars_missed,

    /* Cost of suppression: SARs missed per 1,000 alerts suppressed */
    ROUND(1000.0 * (b.sars - r.sars_retained)
          / NULLIF(b.alerts - r.alerts_retained, 0), 1)                   AS sars_missed_per_1k_suppressed,

    /* Quality of the remaining queue */
    ROUND(100.0 * r.false_positives_retained / NULLIF(r.completed_retained, 0), 2)
                                                                           AS retained_false_positive_rate_pct,
    ROUND(100.0 * r.sars_retained / NULLIF(r.alerts_retained, 0), 2)       AS retained_alert_to_sar_pct

FROM retained r
CROSS JOIN baseline b;
