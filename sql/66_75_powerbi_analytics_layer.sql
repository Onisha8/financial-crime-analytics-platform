/* ============================================================
   POWER BI ANALYTICS / SEMANTIC LAYER
   Analyses 66–75

   PURPOSE
   -------
   Build dashboard-ready PostgreSQL views for:

   1. Executive FinCrime Overview
   2. Transaction Monitoring & Model Performance
   3. Investigation Operations
   4. Customer & Network Risk

   Power BI should consume these views rather than rebuilding
   complex business logic inside the report.

   NOTE:
   SLA thresholds are synthetic portfolio assumptions:
     Critical = 7 days
     High     = 15 days
     Medium   = 30 days
     Low      = 45 days
   ============================================================ */

CREATE SCHEMA IF NOT EXISTS analytics;


/* ============================================================
   CLEAN REBUILD
   ============================================================ */

DROP VIEW IF EXISTS analytics.vw_executive_kpis;
DROP VIEW IF EXISTS analytics.vw_monthly_fincrime_funnel;
DROP VIEW IF EXISTS analytics.vw_tm_rule_performance;
DROP VIEW IF EXISTS analytics.vw_investigator_performance;
DROP VIEW IF EXISTS analytics.vw_investigation_sla;
DROP VIEW IF EXISTS analytics.vw_customer_risk_dashboard;
DROP VIEW IF EXISTS analytics.vw_network_relationships;
DROP VIEW IF EXISTS analytics.vw_network_customer_metrics;


/* ============================================================
   66. EXECUTIVE KPI VIEW
   One-row enterprise scorecard.
   ============================================================ */

CREATE VIEW analytics.vw_executive_kpis AS

SELECT

    /* Population */

    (SELECT COUNT(*)
     FROM core.customers)
        AS total_customers,

    (SELECT COUNT(*)
     FROM core.transactions)
        AS total_transactions,

    (SELECT ROUND(SUM(amount), 2)
     FROM core.transactions)
        AS total_transaction_volume,

    /* TM */

    (SELECT COUNT(*)
     FROM core.alerts)
        AS total_alerts,

    (SELECT COUNT(DISTINCT customer_id)
     FROM core.alerts)
        AS alerted_customers,

    /* Investigations */

    (SELECT COUNT(*)
     FROM core.investigations)
        AS total_investigations,

    (SELECT COUNT(*)
     FROM core.investigations
     WHERE investigation_end IS NULL)
        AS open_investigations,

    (SELECT COUNT(*)
     FROM core.investigations
     WHERE investigation_end IS NOT NULL)
        AS completed_investigations,

    /* Cases */

    (SELECT COUNT(*)
     FROM core.cases)
        AS total_cases,

    (SELECT COUNT(*)
     FROM core.cases
     WHERE case_status = 'Open')
        AS open_cases,

    /* SAR */

    (SELECT COUNT(*)
     FROM core.sar_reports)
        AS total_sars,

    (SELECT COUNT(*)
     FROM core.sar_reports
     WHERE sar_status = 'Filed')
        AS filed_sars,

    /* Customer risk */

    (SELECT COUNT(*)
     FROM analytics.customer_risk_score
     WHERE customer_risk_tier = 'Critical')
        AS critical_risk_customers,

    (SELECT COUNT(*)
     FROM analytics.customer_risk_score
     WHERE customer_risk_tier = 'High')
        AS high_risk_customers,

    /* Network */

    (SELECT COUNT(*)
     FROM analytics.entity_relationships)
        AS entity_relationships,

    (SELECT COUNT(*)
     FROM analytics.customer_network_metrics
     WHERE network_degree > 0)
        AS connected_customers,

    /* Funnel conversion */

    ROUND(
        100.0 *
        (SELECT COUNT(*) FROM core.cases)
        /
        NULLIF(
            (SELECT COUNT(*)
             FROM core.investigations
             WHERE investigation_end IS NOT NULL),
            0
        ),
        2
    ) AS investigation_to_case_pct,

    ROUND(
        100.0 *
        (SELECT COUNT(*) FROM core.sar_reports)
        /
        NULLIF(
            (SELECT COUNT(*) FROM core.cases),
            0
        ),
        2
    ) AS case_to_sar_pct;


/* ============================================================
   67. MONTHLY FINCRIME FUNNEL

   Alert-month cohort view.

   IMPORTANT:
   Cases/SARs are attributed to the month of the originating
   alert rather than case-open/SAR-filing month.

   This makes the funnel denominator internally coherent:
   Alert -> Investigation -> Case -> SAR.
   ============================================================ */

CREATE VIEW analytics.vw_monthly_fincrime_funnel AS

SELECT
    DATE_TRUNC(
        'month',
        a.alert_date
    )::DATE AS month,

    COUNT(DISTINCT a.alert_id)
        AS alerts,

    COUNT(DISTINCT i.investigation_id)
        AS investigations,

    COUNT(DISTINCT i.investigation_id) FILTER (
        WHERE i.investigation_end IS NOT NULL
    ) AS completed_investigations,

    COUNT(DISTINCT c.case_id)
        AS cases,

    COUNT(DISTINCT s.sar_id)
        AS sars,

    COUNT(DISTINCT a.customer_id)
        AS alerted_customers,

    ROUND(
        AVG(a.alert_score),
        2
    ) AS avg_alert_score,

    ROUND(
        100.0 *
        COUNT(DISTINCT c.case_id)
        /
        NULLIF(
            COUNT(DISTINCT i.investigation_id)
            FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS investigation_to_case_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT s.sar_id)
        /
        NULLIF(
            COUNT(DISTINCT c.case_id),
            0
        ),
        2
    ) AS case_to_sar_pct

FROM core.alerts a

LEFT JOIN core.investigations i
    ON a.alert_id = i.alert_id

LEFT JOIN core.cases c
    ON i.investigation_id = c.investigation_id

LEFT JOIN core.sar_reports s
    ON c.case_id = s.case_id

GROUP BY
    DATE_TRUNC('month', a.alert_date)::DATE;


/* ============================================================
   68. TM RULE PERFORMANCE
   ============================================================ */

CREATE VIEW analytics.vw_tm_rule_performance AS

SELECT
    a.rule_id,

    COUNT(DISTINCT a.alert_id)
        AS alerts,

    COUNT(DISTINCT a.customer_id)
        AS alerted_customers,

    ROUND(
        AVG(a.alert_score),
        2
    ) AS avg_alert_score,

    COUNT(DISTINCT a.alert_id) FILTER (
        WHERE a.priority = 'High'
    ) AS high_priority_alerts,

    COUNT(DISTINCT i.investigation_id)
        AS investigations,

    COUNT(DISTINCT i.investigation_id) FILTER (
        WHERE i.investigation_end IS NOT NULL
    ) AS completed_investigations,

    COUNT(DISTINCT i.investigation_id) FILTER (
        WHERE i.investigation_end IS NOT NULL
          AND i.disposition = 'False Positive'
    ) AS false_positives,

    COUNT(DISTINCT i.investigation_id) FILTER (
        WHERE i.investigation_end IS NOT NULL
          AND i.disposition = 'Escalated'
    ) AS escalations,

    COUNT(DISTINCT c.case_id)
        AS cases,

    COUNT(DISTINCT s.sar_id)
        AS sars,

    ROUND(
        100.0 *
        COUNT(DISTINCT i.investigation_id) FILTER (
            WHERE i.investigation_end IS NOT NULL
              AND i.disposition = 'False Positive'
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
            WHERE i.investigation_end IS NOT NULL
              AND i.disposition = 'Escalated'
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
    ) AS investigation_to_sar_pct,

    ROUND(
        100.0 *
        COUNT(DISTINCT s.sar_id)
        /
        NULLIF(
            COUNT(DISTINCT c.case_id),
            0
        ),
        2
    ) AS case_to_sar_pct

FROM core.alerts a

LEFT JOIN core.investigations i
    ON a.alert_id = i.alert_id

LEFT JOIN core.cases c
    ON i.investigation_id = c.investigation_id

LEFT JOIN core.sar_reports s
    ON c.case_id = s.case_id

GROUP BY a.rule_id;


/* ============================================================
   69. INVESTIGATOR PERFORMANCE
   Descriptive operational metrics only.
   ============================================================ */

CREATE VIEW analytics.vw_investigator_performance AS

SELECT
    e.employee_id,

    CONCAT(
        e.first_name,
        ' ',
        e.last_name
    ) AS investigator_name,

    e.role,

    e.workload_capacity,

    COUNT(i.investigation_id)
        AS assigned_investigations,

    COUNT(i.investigation_id) FILTER (
        WHERE i.investigation_end IS NOT NULL
    ) AS completed_investigations,

    COUNT(i.investigation_id) FILTER (
        WHERE i.investigation_end IS NULL
    ) AS open_investigations,

    ROUND(
        100.0 *
        COUNT(i.investigation_id)
        /
        NULLIF(e.workload_capacity, 0),
        2
    ) AS assigned_capacity_utilization_pct,

    ROUND(
        100.0 *
        COUNT(i.investigation_id) FILTER (
            WHERE i.investigation_end IS NULL
        )
        /
        NULLIF(e.workload_capacity, 0),
        2
    ) AS active_backlog_utilization_pct,

    ROUND(
        100.0 *
        COUNT(i.investigation_id) FILTER (
            WHERE i.investigation_end IS NOT NULL
        )
        /
        NULLIF(
            COUNT(i.investigation_id),
            0
        ),
        2
    ) AS completion_rate_pct,

    ROUND(
        AVG(
            EXTRACT(
                EPOCH FROM (
                    i.investigation_end
                    - i.investigation_start
                )
            ) / 86400.0
        ) FILTER (
            WHERE i.investigation_end IS NOT NULL
        ),
        2
    ) AS avg_tat_days,

    ROUND(
        100.0 *
        COUNT(i.investigation_id) FILTER (
            WHERE i.investigation_end IS NOT NULL
              AND i.disposition = 'False Positive'
        )
        /
        NULLIF(
            COUNT(i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS false_positive_rate_pct,

    ROUND(
        100.0 *
        COUNT(i.investigation_id) FILTER (
            WHERE i.investigation_end IS NOT NULL
              AND i.disposition = 'Escalated'
        )
        /
        NULLIF(
            COUNT(i.investigation_id) FILTER (
                WHERE i.investigation_end IS NOT NULL
            ),
            0
        ),
        2
    ) AS escalation_rate_pct

FROM core.employees e

LEFT JOIN core.investigations i
    ON e.employee_id = i.investigator_id

WHERE e.role IN (
    'Investigator I',
    'Senior Investigator',
    'Lead Investigator'
)

GROUP BY
    e.employee_id,
    e.first_name,
    e.last_name,
    e.role,
    e.workload_capacity;


/* ============================================================
   70. INVESTIGATION SLA / BACKLOG VIEW

   Reporting timestamp = 2026-06-30 23:59:59

   This preserves the point-in-time methodology from the
   validated Investigator Productivity Pack.
   ============================================================ */

CREATE VIEW analytics.vw_investigation_sla AS

WITH base AS (

    SELECT
        i.investigation_id,
        i.alert_id,
        i.investigator_id,

        a.customer_id,
        a.rule_id,
        a.priority,
        a.alert_score,

        i.investigation_start,
        i.investigation_end,
        i.disposition,

        TIMESTAMP '2026-06-30 23:59:59'
            AS reporting_ts,

        CASE
            WHEN a.priority = 'Critical' THEN 7
            WHEN a.priority = 'High' THEN 15
            WHEN a.priority = 'Medium' THEN 30
            WHEN a.priority = 'Low' THEN 45
            ELSE 30
        END AS sla_days

    FROM core.investigations i

    JOIN core.alerts a
        ON i.alert_id = a.alert_id

    WHERE i.investigation_start
          <= TIMESTAMP '2026-06-30 23:59:59'
),

lifecycle AS (

    SELECT
        *,

        CASE
            WHEN investigation_end IS NOT NULL
             AND investigation_end <= reporting_ts
                THEN 'Closed'
            ELSE 'Open'
        END AS snapshot_status,

        EXTRACT(
            EPOCH FROM (
                CASE
                    WHEN investigation_end IS NOT NULL
                     AND investigation_end <= reporting_ts
                        THEN investigation_end
                    ELSE reporting_ts
                END
                - investigation_start
            )
        ) / 86400.0 AS lifecycle_days

    FROM base
)

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

        ELSE 'Open Breached SLA'
    END AS sla_status,

    CASE
        WHEN snapshot_status = 'Open'
         AND lifecycle_days <= 7
            THEN '0-7 days'

        WHEN snapshot_status = 'Open'
         AND lifecycle_days <= 15
            THEN '8-15 days'

        WHEN snapshot_status = 'Open'
         AND lifecycle_days <= 30
            THEN '16-30 days'

        WHEN snapshot_status = 'Open'
         AND lifecycle_days <= 60
            THEN '31-60 days'

        ELSE '60+ days'
    END AS aging_bucket

FROM lifecycle;


/* ============================================================
   71. CUSTOMER RISK DASHBOARD VIEW
   ============================================================ */

CREATE VIEW analytics.vw_customer_risk_dashboard AS

SELECT
    r.customer_id,

    r.customer_risk_score,
    r.customer_risk_tier,

    r.kyc_risk_score,
    r.transaction_risk_score,
    r.digital_risk_score,
    r.fincrime_risk_score,

    r.kyc_risk_rating,
    r.politically_exposed_person_flag,
    r.customer_segment,
    r.income_band,
    r.state,

    r.transaction_count,
    r.transaction_volume,
    r.suspicious_transaction_count,
    r.cross_border_transaction_count,
    r.high_risk_merchant_transactions,

    r.failed_login_count,
    r.high_risk_ip_logins,

    r.alert_count,
    r.distinct_tm_rules,
    r.high_priority_alerts,

    r.case_count,
    r.sar_count,

    r.risk_reasons,

    n.network_degree,
    n.total_relationship_strength,
    n.high_risk_customer_connections,
    n.high_risk_rare_ip_link_count,
    n.avg_connected_customer_risk_score

FROM analytics.customer_risk_score r

LEFT JOIN analytics.customer_network_metrics n
    ON r.customer_id = n.customer_id;


/* ============================================================
   72. NETWORK RELATIONSHIP VIEW
   Edge table for Power BI network/relationship reporting.
   ============================================================ */

CREATE VIEW analytics.vw_network_relationships AS

SELECT
    customer_1,
    customer_2,

    shared_rare_ip_count,
    shared_high_risk_rare_ip_count,
    rarest_shared_ip_prevalence,

    relationship_strength_score,

    customer_1_risk_score,
    customer_1_risk_tier,

    customer_2_risk_score,
    customer_2_risk_tier,

    CASE
        WHEN customer_1_risk_tier
             IN ('High', 'Critical')
          OR customer_2_risk_tier
             IN ('High', 'Critical')
            THEN TRUE
        ELSE FALSE
    END AS high_risk_relationship

FROM analytics.entity_relationships;


/* ============================================================
   73. NETWORK CUSTOMER VIEW
   ============================================================ */

CREATE VIEW analytics.vw_network_customer_metrics AS

SELECT
    n.customer_id,
    n.customer_risk_score,
    n.customer_risk_tier,

    n.network_degree,
    n.total_relationship_strength,
    n.strongest_relationship_score,
    n.rare_ip_link_count,
    n.high_risk_rare_ip_link_count,
    n.high_risk_customer_connections,
    n.avg_connected_customer_risk_score,
    n.max_connected_customer_risk_score,

    CASE
        WHEN n.network_degree >= 10 THEN 5
        WHEN n.network_degree >= 5 THEN 3
        WHEN n.network_degree >= 1 THEN 1
        ELSE 0
    END
    +
    CASE
        WHEN n.high_risk_customer_connections >= 3 THEN 5
        WHEN n.high_risk_customer_connections >= 1 THEN 3
        ELSE 0
    END
    +
    CASE
        WHEN n.high_risk_rare_ip_link_count >= 3 THEN 5
        WHEN n.high_risk_rare_ip_link_count >= 1 THEN 3
        ELSE 0
    END AS network_risk_overlay

FROM analytics.customer_network_metrics n;


/* ============================================================
   74. DASHBOARD DATASET INVENTORY
   ============================================================ */

SELECT
    'Executive KPI' AS dataset,
    COUNT(*) AS rows
FROM analytics.vw_executive_kpis

UNION ALL

SELECT
    'Monthly FinCrime Funnel',
    COUNT(*)
FROM analytics.vw_monthly_fincrime_funnel

UNION ALL

SELECT
    'TM Rule Performance',
    COUNT(*)
FROM analytics.vw_tm_rule_performance

UNION ALL

SELECT
    'Investigator Performance',
    COUNT(*)
FROM analytics.vw_investigator_performance

UNION ALL

SELECT
    'Investigation SLA',
    COUNT(*)
FROM analytics.vw_investigation_sla

UNION ALL

SELECT
    'Customer Risk',
    COUNT(*)
FROM analytics.vw_customer_risk_dashboard

UNION ALL

SELECT
    'Network Relationships',
    COUNT(*)
FROM analytics.vw_network_relationships

UNION ALL

SELECT
    'Network Customer Metrics',
    COUNT(*)
FROM analytics.vw_network_customer_metrics;


/* ============================================================
   75. VALIDATION SUITE
   ============================================================ */


/* V1 Executive view = one row */

SELECT
    'Executive KPI row count' AS validation,
    CASE WHEN COUNT(*) = 1
         THEN 'PASS'
         ELSE 'FAIL'
    END AS result,
    COUNT(*) AS observed
FROM analytics.vw_executive_kpis;


/* V2 Alert reconciliation */

SELECT
    'Executive alert reconciliation' AS validation,
    CASE WHEN total_alerts = 53392
         THEN 'PASS'
         ELSE 'FAIL'
    END AS result,
    total_alerts AS observed
FROM analytics.vw_executive_kpis;


/* V3 Investigation reconciliation */

SELECT
    'Executive investigation reconciliation' AS validation,
    CASE WHEN total_investigations = 53392
         THEN 'PASS'
         ELSE 'FAIL'
    END AS result,
    total_investigations AS observed
FROM analytics.vw_executive_kpis;


/* V4 Open investigation reconciliation */

SELECT
    'Open investigation reconciliation' AS validation,
    CASE WHEN open_investigations = 5339
         THEN 'PASS'
         ELSE 'FAIL'
    END AS result,
    open_investigations AS observed
FROM analytics.vw_executive_kpis;


/* V5 Case reconciliation */

SELECT
    'Executive case reconciliation' AS validation,
    CASE WHEN total_cases = 18597
         THEN 'PASS'
         ELSE 'FAIL'
    END AS result,
    total_cases AS observed
FROM analytics.vw_executive_kpis;


/* V6 SAR reconciliation */

SELECT
    'Executive SAR reconciliation' AS validation,
    CASE WHEN total_sars = 11103
         THEN 'PASS'
         ELSE 'FAIL'
    END AS result,
    total_sars AS observed
FROM analytics.vw_executive_kpis;


/* V7 Monthly alerts reconcile */

SELECT
    'Monthly funnel alert reconciliation' AS validation,
    CASE WHEN SUM(alerts) = 53392
         THEN 'PASS'
         ELSE 'FAIL'
    END AS result,
    SUM(alerts) AS observed
FROM analytics.vw_monthly_fincrime_funnel;


/* V8 Rule alerts reconcile */

SELECT
    'Rule alert reconciliation' AS validation,
    CASE WHEN SUM(alerts) = 53392
         THEN 'PASS'
         ELSE 'FAIL'
    END AS result,
    SUM(alerts) AS observed
FROM analytics.vw_tm_rule_performance;


/* V9 Investigator assignments reconcile */

SELECT
    'Investigator assignment reconciliation' AS validation,
    CASE WHEN SUM(assigned_investigations) = 53392
         THEN 'PASS'
         ELSE 'FAIL'
    END AS result,
    SUM(assigned_investigations) AS observed
FROM analytics.vw_investigator_performance;


/* V10 Customer risk coverage */

SELECT
    'Customer risk coverage' AS validation,
    CASE WHEN COUNT(*) = 10000
         THEN 'PASS'
         ELSE 'FAIL'
    END AS result,
    COUNT(*) AS observed
FROM analytics.vw_customer_risk_dashboard;


/* V11 Network relationship reconciliation */

SELECT
    'Network relationship reconciliation' AS validation,
    CASE WHEN COUNT(*) = 389
         THEN 'PASS'
         ELSE 'FAIL'
    END AS result,
    COUNT(*) AS observed
FROM analytics.vw_network_relationships;


/* V12 Network customer coverage */

SELECT
    'Network customer coverage' AS validation,
    CASE WHEN COUNT(*) = 10000
         THEN 'PASS'
         ELSE 'FAIL'
    END AS result,
    COUNT(*) AS observed
FROM analytics.vw_network_customer_metrics;


/* V13 Critical + High customer reconciliation */

SELECT
    'High risk customer reconciliation' AS validation,

    CASE
        WHEN critical_risk_customers = 3
         AND high_risk_customers = 524
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    critical_risk_customers,
    high_risk_customers

FROM analytics.vw_executive_kpis;


/* V14 Entity relationship reconciliation */

SELECT
    'Entity relationship count' AS validation,

    CASE
        WHEN entity_relationships = 389
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    entity_relationships AS observed

FROM analytics.vw_executive_kpis;


/* V15 Connected customer reconciliation */

SELECT
    'Connected customer reconciliation' AS validation,

    CASE
        WHEN connected_customers = 207
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    connected_customers AS observed

FROM analytics.vw_executive_kpis;


/* ============================================================
   FINAL ANALYTICS LAYER SCORECARD
   ============================================================ */

SELECT *
FROM analytics.vw_executive_kpis;