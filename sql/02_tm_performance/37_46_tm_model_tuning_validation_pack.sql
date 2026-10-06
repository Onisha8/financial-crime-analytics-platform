/* ============================================================
   TRANSACTION MONITORING MODEL TUNING + VALIDATION PACK
   Analyses 37–46

   37 - Rule Alert Volume
   38 - Rule False Positive Rate
   39 - Rule Escalation Rate
   40 - Rule Case & SAR Conversion
   41 - Alert Score Band Effectiveness
   42 - Priority Effectiveness
   43 - Rule x Priority Matrix
   44 - Repeat Alert / Customer Concentration
   45 - Alert Score Threshold Simulation
   46 - Model Validation / Integrity Checks

   NOTE:
   rule_id is sourced directly from core.alerts.
   No core.rules master table is required.
   ============================================================ */


/* ============================================================
   37. RULE ALERT VOLUME
   ============================================================ */

SELECT
    a.rule_id,

    COUNT(*) AS total_alerts,

    COUNT(DISTINCT a.customer_id)
        AS unique_customers,

    COUNT(DISTINCT a.account_id)
        AS unique_accounts,

    ROUND(AVG(a.alert_score), 2)
        AS avg_alert_score,

    COUNT(*) FILTER (
        WHERE a.priority = 'High'
    ) AS high_priority_alerts,

    COUNT(*) FILTER (
        WHERE a.priority = 'Medium'
    ) AS medium_priority_alerts,

    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_total_alerts

FROM core.alerts a

GROUP BY a.rule_id

ORDER BY total_alerts DESC;


/* ============================================================
   38. RULE FALSE-POSITIVE RATE

   Denominator = completed investigations only.
   Open investigations are excluded because they do not yet
   have a final disposition.
   ============================================================ */

SELECT
    a.rule_id,

    COUNT(*) FILTER (
        WHERE i.investigation_end IS NOT NULL
    ) AS completed_investigations,

    COUNT(*) FILTER (
        WHERE i.disposition = 'False Positive'
    ) AS false_positives,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE i.disposition = 'False Positive'
        )
        /
        NULLIF(
            COUNT(*) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS false_positive_rate_pct

FROM core.alerts a

JOIN core.investigations i
    ON a.alert_id = i.alert_id

GROUP BY a.rule_id

ORDER BY false_positive_rate_pct DESC;


/* ============================================================
   39. RULE ESCALATION RATE
   ============================================================ */

SELECT
    a.rule_id,

    COUNT(*) FILTER (
        WHERE i.investigation_end IS NOT NULL
    ) AS completed_investigations,

    COUNT(*) FILTER (
        WHERE i.disposition = 'Escalated'
    ) AS escalated_investigations,

    COUNT(*) FILTER (
        WHERE i.disposition = 'Monitoring Required'
    ) AS monitoring_required,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE i.disposition = 'Escalated'
        )
        /
        NULLIF(
            COUNT(*) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS escalation_rate_pct

FROM core.alerts a

JOIN core.investigations i
    ON a.alert_id = i.alert_id

GROUP BY a.rule_id

ORDER BY escalation_rate_pct DESC;


/* ============================================================
   40. RULE DOWNSTREAM CONVERSION

   Measures alert -> case and alert -> SAR yield.

   completed_alerts is used as the denominator because open
   investigations have not reached a final outcome.
   ============================================================ */

SELECT
    a.rule_id,

    COUNT(DISTINCT i.investigation_id) FILTER (
        WHERE i.investigation_end IS NOT NULL
    ) AS completed_investigations,

    COUNT(DISTINCT c.case_id)
        AS cases_created,

    COUNT(DISTINCT s.sar_id)
        AS sar_reports,

    ROUND(
        100.0 *
        COUNT(DISTINCT c.case_id)
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS case_conversion_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT s.sar_id)
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS investigation_to_sar_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT s.sar_id)
        /
        NULLIF(COUNT(DISTINCT c.case_id), 0),
        2
    ) AS case_to_sar_pct

FROM core.alerts a

JOIN core.investigations i
    ON a.alert_id = i.alert_id

LEFT JOIN core.cases c
    ON i.investigation_id = c.investigation_id

LEFT JOIN core.sar_reports s
    ON c.case_id = s.case_id

GROUP BY a.rule_id

ORDER BY investigation_to_sar_pct DESC;


/* ============================================================
   41. ALERT SCORE BAND EFFECTIVENESS

   Tests whether stronger alert scores correspond with stronger
   downstream investigative outcomes.
   ============================================================ */

WITH scored AS (

    SELECT
        a.alert_id,
        a.alert_score,

        CASE
            WHEN a.alert_score < 60 THEN '<60'
            WHEN a.alert_score < 70 THEN '60-69.99'
            WHEN a.alert_score < 80 THEN '70-79.99'
            WHEN a.alert_score < 90 THEN '80-89.99'
            ELSE '90+'
        END AS score_band,

        i.investigation_id,
        i.investigation_end,
        i.disposition,
        c.case_id,
        s.sar_id

    FROM core.alerts a

    JOIN core.investigations i
        ON a.alert_id = i.alert_id

    LEFT JOIN core.cases c
        ON i.investigation_id = c.investigation_id

    LEFT JOIN core.sar_reports s
        ON c.case_id = s.case_id
)

SELECT
    score_band,

    COUNT(DISTINCT alert_id)
        AS alerts,

    COUNT(DISTINCT investigation_id) FILTER (
        WHERE investigation_end IS NOT NULL
    ) AS completed_investigations,

    ROUND(
        AVG(alert_score),
        2
    ) AS avg_score,

    ROUND(
        100.0 *
        COUNT(DISTINCT investigation_id) FILTER (
            WHERE disposition = 'False Positive'
        )
        /
        NULLIF(
            COUNT(DISTINCT investigation_id) FILTER (
                WHERE investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS false_positive_rate_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT investigation_id) FILTER (
            WHERE disposition = 'Escalated'
        )
        /
        NULLIF(
            COUNT(DISTINCT investigation_id) FILTER (
                WHERE investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS escalation_rate_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT case_id)
        /
        NULLIF(
            COUNT(DISTINCT investigation_id) FILTER (
                WHERE investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS case_conversion_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT sar_id)
        /
        NULLIF(
            COUNT(DISTINCT investigation_id) FILTER (
                WHERE investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS sar_conversion_pct

FROM scored

GROUP BY score_band

ORDER BY
    CASE score_band
        WHEN '<60' THEN 1
        WHEN '60-69.99' THEN 2
        WHEN '70-79.99' THEN 3
        WHEN '80-89.99' THEN 4
        WHEN '90+' THEN 5
    END;


/* ============================================================
   42. PRIORITY EFFECTIVENESS
   ============================================================ */

SELECT
    a.priority,

    COUNT(DISTINCT a.alert_id)
        AS alerts,

    COUNT(DISTINCT i.investigation_id) FILTER (
        WHERE i.investigation_end IS NOT NULL
    ) AS completed_investigations,

    ROUND(AVG(a.alert_score), 2)
        AS avg_alert_score,

    ROUND(
        100.0 *
        COUNT(DISTINCT i.investigation_id) FILTER (
            WHERE i.disposition = 'False Positive'
        )
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS false_positive_rate_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT i.investigation_id) FILTER (
            WHERE i.disposition = 'Escalated'
        )
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS escalation_rate_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT c.case_id)
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS case_conversion_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT s.sar_id)
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS sar_conversion_pct

FROM core.alerts a

JOIN core.investigations i
    ON a.alert_id = i.alert_id

LEFT JOIN core.cases c
    ON i.investigation_id = c.investigation_id

LEFT JOIN core.sar_reports s
    ON c.case_id = s.case_id

GROUP BY a.priority

ORDER BY
    CASE a.priority
        WHEN 'Critical' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Medium' THEN 3
        WHEN 'Low' THEN 4
        ELSE 5
    END;


/* ============================================================
   43. RULE x PRIORITY EFFECTIVENESS MATRIX
   ============================================================ */

SELECT
    a.rule_id,
    a.priority,

    COUNT(DISTINCT a.alert_id)
        AS alerts,

    COUNT(DISTINCT i.investigation_id) FILTER (
        WHERE i.investigation_end IS NOT NULL
    ) AS completed_investigations,

    ROUND(AVG(a.alert_score), 2)
        AS avg_alert_score,

    ROUND(
        100.0 *
        COUNT(DISTINCT i.investigation_id) FILTER (
            WHERE i.disposition = 'False Positive'
        )
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS false_positive_rate_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT i.investigation_id) FILTER (
            WHERE i.disposition = 'Escalated'
        )
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS escalation_rate_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT c.case_id)
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS case_conversion_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT s.sar_id)
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS sar_conversion_pct

FROM core.alerts a

JOIN core.investigations i
    ON a.alert_id = i.alert_id

LEFT JOIN core.cases c
    ON i.investigation_id = c.investigation_id

LEFT JOIN core.sar_reports s
    ON c.case_id = s.case_id

GROUP BY
    a.rule_id,
    a.priority

ORDER BY
    a.rule_id,
    CASE a.priority
        WHEN 'Critical' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Medium' THEN 3
        WHEN 'Low' THEN 4
        ELSE 5
    END;


/* ============================================================
   44A. REPEAT ALERT / CUSTOMER CONCENTRATION BY RULE
   ============================================================ */

WITH customer_rule_alerts AS (

    SELECT
        rule_id,
        customer_id,
        COUNT(*) AS alert_count

    FROM core.alerts

    GROUP BY
        rule_id,
        customer_id
)

SELECT
    rule_id,

    COUNT(*) AS alerted_customers,

    SUM(alert_count) AS total_alerts,

    ROUND(
        AVG(alert_count),
        2
    ) AS avg_alerts_per_customer,

    COUNT(*) FILTER (
        WHERE alert_count > 1
    ) AS repeat_alert_customers,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE alert_count > 1
        )
        /
        NULLIF(COUNT(*), 0),
        2
    ) AS repeat_customer_pct,

    MAX(alert_count)
        AS max_alerts_single_customer

FROM customer_rule_alerts

GROUP BY rule_id

ORDER BY repeat_customer_pct DESC;


/* ============================================================
   44B. MOST FREQUENTLY ALERTED CUSTOMERS

   Useful later for entity/network analytics.
   ============================================================ */

SELECT
    customer_id,

    COUNT(*) AS total_alerts,

    COUNT(DISTINCT rule_id)
        AS distinct_rules,

    ROUND(AVG(alert_score), 2)
        AS avg_alert_score,

    COUNT(*) FILTER (
        WHERE priority = 'High'
    ) AS high_priority_alerts

FROM core.alerts

GROUP BY customer_id

HAVING COUNT(*) > 1

ORDER BY
    total_alerts DESC,
    distinct_rules DESC

LIMIT 25;


/* ============================================================
   45. ALERT SCORE THRESHOLD TUNING SIMULATION

   IMPORTANT:
   This does NOT change any production/synthetic thresholds.
   It estimates the workload/outcome impact if alerts below a
   candidate score threshold were suppressed.

   Thresholds tested:
   60, 65, 70, 75, 80, 85, 90
   ============================================================ */

WITH thresholds AS (

    SELECT *
    FROM (
        VALUES
            (60::NUMERIC),
            (65::NUMERIC),
            (70::NUMERIC),
            (75::NUMERIC),
            (80::NUMERIC),
            (85::NUMERIC),
            (90::NUMERIC)
    ) AS t(threshold)
),

outcomes AS (

    SELECT
        a.alert_id,
        a.alert_score,

        i.investigation_end,
        i.disposition,

        c.case_id,
        s.sar_id

    FROM core.alerts a

    JOIN core.investigations i
        ON a.alert_id = i.alert_id

    LEFT JOIN core.cases c
        ON i.investigation_id = c.investigation_id

    LEFT JOIN core.sar_reports s
        ON c.case_id = s.case_id
),

baseline AS (

    SELECT
        COUNT(DISTINCT alert_id)
            AS baseline_alerts,

        COUNT(DISTINCT case_id)
            AS baseline_cases,

        COUNT(DISTINCT sar_id)
            AS baseline_sars

    FROM outcomes
)

SELECT
    t.threshold,

    COUNT(DISTINCT o.alert_id) FILTER (
        WHERE o.alert_score >= t.threshold
    ) AS alerts_retained,

    ROUND(
        100.0 *
        COUNT(DISTINCT o.alert_id) FILTER (
            WHERE o.alert_score >= t.threshold
        )
        /
        NULLIF(b.baseline_alerts, 0),
        2
    ) AS alerts_retained_pct,

    ROUND(
        100.0 -
        (
            100.0 *
            COUNT(DISTINCT o.alert_id) FILTER (
                WHERE o.alert_score >= t.threshold
            )
            /
            NULLIF(b.baseline_alerts, 0)
        ),
        2
    ) AS workload_reduction_pct,

    COUNT(DISTINCT o.case_id) FILTER (
        WHERE o.alert_score >= t.threshold
    ) AS cases_retained,

    ROUND(
        100.0 *
        COUNT(DISTINCT o.case_id) FILTER (
            WHERE o.alert_score >= t.threshold
        )
        /
        NULLIF(b.baseline_cases, 0),
        2
    ) AS cases_retained_pct,

    COUNT(DISTINCT o.sar_id) FILTER (
        WHERE o.alert_score >= t.threshold
    ) AS sars_retained,

    ROUND(
        100.0 *
        COUNT(DISTINCT o.sar_id) FILTER (
            WHERE o.alert_score >= t.threshold
        )
        /
        NULLIF(b.baseline_sars, 0),
        2
    ) AS sars_retained_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT o.alert_id) FILTER (
            WHERE o.alert_score >= t.threshold
              AND o.disposition = 'False Positive'
        )
        /
        NULLIF(
            COUNT(DISTINCT o.alert_id) FILTER (
                WHERE o.alert_score >= t.threshold
                  AND o.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS retained_false_positive_rate_pct

FROM thresholds t

CROSS JOIN outcomes o

CROSS JOIN baseline b

GROUP BY
    t.threshold,
    b.baseline_alerts,
    b.baseline_cases,
    b.baseline_sars

ORDER BY t.threshold;


/* ============================================================
   46. MODEL VALIDATION / DATA QUALITY CHECKS
   ============================================================ */


/* V1 — Alert volume */

SELECT
    'Alert volume' AS validation,

    CASE
        WHEN COUNT(*) = 53392
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS observed_value

FROM core.alerts;


/* V2 — Unique alert IDs */

SELECT
    'Unique alert IDs' AS validation,

    CASE
        WHEN COUNT(*) =
             COUNT(DISTINCT alert_id)
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS total_alerts,

    COUNT(DISTINCT alert_id)
        AS unique_alerts

FROM core.alerts;


/* V3 — Every alert has an investigation */

SELECT
    'Alerts without investigations' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.alerts a

LEFT JOIN core.investigations i
    ON a.alert_id = i.alert_id

WHERE i.investigation_id IS NULL;


/* V4 — Investigation without alert */

SELECT
    'Investigations without alerts' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.investigations i

LEFT JOIN core.alerts a
    ON i.alert_id = a.alert_id

WHERE a.alert_id IS NULL;


/* V5 — Missing alert scores */

SELECT
    'Missing alert scores' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.alerts

WHERE alert_score IS NULL;


/* V6 — Alert score range */

SELECT
    'Alert score range' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count,

    MIN(alert_score) AS min_score,
    MAX(alert_score) AS max_score

FROM core.alerts

WHERE alert_score < 0
   OR alert_score > 100;


/* V7 — Missing priority */

SELECT
    'Missing alert priority' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.alerts

WHERE priority IS NULL;


/* V8 — Unexpected priority */

SELECT
    'Unexpected priority values' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.alerts

WHERE priority NOT IN (
    'Critical',
    'High',
    'Medium',
    'Low'
);


/* V9 — Closed investigation outcome */

SELECT
    'Closed investigation outcome' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.investigations

WHERE investigation_end IS NOT NULL

  AND (
        disposition IS NULL

        OR disposition NOT IN (
            'False Positive',
            'Escalated',
            'Monitoring Required',
            'Closed - No Issue'
        )
      );


/* V10 — Open investigations have no final disposition */

SELECT
    'Open investigation outcome' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.investigations

WHERE investigation_end IS NULL
  AND disposition IS NOT NULL;


/* V11 — Cases must originate from completed investigations */

SELECT
    'Cases from incomplete investigations' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM core.cases c

JOIN core.investigations i
    ON c.investigation_id =
       i.investigation_id

WHERE i.investigation_end IS NULL;


/* V12 — SARs must have valid cases */

SELECT
    'SARs without valid cases' AS validation,

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


/* ============================================================
   FINAL PORTFOLIO RECONCILIATION
   ============================================================ */

SELECT
    (SELECT COUNT(*)
     FROM core.alerts)
        AS alerts,

    (SELECT COUNT(*)
     FROM core.investigations)
        AS investigations,

    (SELECT COUNT(*)
     FROM core.investigations
     WHERE investigation_end IS NULL)
        AS open_investigations,

    (SELECT COUNT(*)
     FROM core.investigations
     WHERE investigation_end IS NOT NULL)
        AS completed_investigations,

    (SELECT COUNT(*)
     FROM core.cases)
        AS cases,

    (SELECT COUNT(*)
     FROM core.sar_reports)
        AS sar_reports;
