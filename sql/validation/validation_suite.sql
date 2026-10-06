/* ============================================================
   FINANCIAL CRIME ANALYTICS PLATFORM — CONSOLIDATED VALIDATION SUITE
   ------------------------------------------------------------
   One read-only query that returns one row per check:

       check_id | area | check_type | severity | check_name | expected | actual | result

   check_type
     Integrity       Keys, orphans, duplicates, allowed values
     Lifecycle       Alert -> investigation -> case -> SAR state and date order
     Reconciliation  One layer must agree with another (no hard-coded numbers)
     Business rule   Scoring / entity-resolution rules hold for every record
     Snapshot        Documented v1.0 baseline values (expected to change if the
                     data is regenerated; update them deliberately)

   severity
     Error    A failure means the data or a reported metric is wrong     -> FAIL
     Warning  A known, documented limitation of the synthetic data that
              does not feed any reported metric (see docs/limitations)   -> WARN
              Planned fix: v1.1 workflow regeneration.

   Run directly in pgAdmin/psql, or via:
     python python/validation/run_validation_suite.py
   ============================================================ */

WITH
base AS (
    SELECT
        (SELECT COUNT(*) FROM core.customers)                                   AS customers,
        (SELECT COUNT(*) FROM core.transactions)                                AS transactions,
        (SELECT COUNT(*) FROM core.transactions WHERE suspicious_flag)          AS suspicious_transactions,
        (SELECT COUNT(*) FROM core.alerts)                                      AS alerts,
        (SELECT COUNT(*) FROM core.investigations)                              AS investigations,
        (SELECT COUNT(*) FROM core.investigations WHERE investigation_end IS NULL)     AS open_investigations,
        (SELECT COUNT(*) FROM core.investigations WHERE investigation_end IS NOT NULL) AS completed_investigations,
        (SELECT COUNT(*) FROM core.cases)                                       AS cases,
        (SELECT COUNT(*) FROM core.sar_reports)                                 AS sars,
        (SELECT COUNT(*) FROM analytics.entity_relationships)                   AS relationships,
        (SELECT COUNT(*) FROM analytics.customer_network_metrics WHERE network_degree > 0) AS connected_customers
),

checks AS (

/* ------------------------------------------------------------
   DQ — Core data quality
   ------------------------------------------------------------ */
SELECT 'DQ01' AS check_id, 'Data quality' AS area, 'Integrity' AS check_type, 'Error' AS severity,
       'Customer IDs are unique' AS check_name,
       '0 duplicates' AS expected,
       (COUNT(*) - COUNT(DISTINCT customer_id))::TEXT AS actual,
       COUNT(*) = COUNT(DISTINCT customer_id) AS passed
FROM core.customers

UNION ALL
SELECT 'DQ02', 'Data quality', 'Integrity', 'Error',
       'Transaction IDs are unique',
       '0 duplicates',
       (COUNT(*) - COUNT(DISTINCT transaction_id))::TEXT,
       COUNT(*) = COUNT(DISTINCT transaction_id)
FROM core.transactions

UNION ALL
SELECT 'DQ03', 'Data quality', 'Integrity', 'Error',
       'Transactions have no missing key fields (account, customer, timestamp, amount, type)',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.transactions
WHERE account_id IS NULL OR customer_id IS NULL OR transaction_timestamp IS NULL
   OR amount IS NULL OR transaction_type IS NULL

UNION ALL
SELECT 'DQ04', 'Data quality', 'Integrity', 'Error',
       'Transaction amounts are positive',
       '0 rows <= 0',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.transactions
WHERE amount <= 0

UNION ALL
SELECT 'DQ05', 'Data quality', 'Integrity', 'Error',
       'Transaction customer is the owner of the transaction account',
       '0 mismatches',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.transactions t
JOIN core.accounts a ON a.account_id = t.account_id
WHERE a.customer_id <> t.customer_id

UNION ALL
SELECT 'DQ06', 'Data quality', 'Integrity', 'Error',
       'Alert IDs are unique',
       '0 duplicates',
       (COUNT(*) - COUNT(DISTINCT alert_id))::TEXT,
       COUNT(*) = COUNT(DISTINCT alert_id)
FROM core.alerts

UNION ALL
SELECT 'DQ07', 'Data quality', 'Integrity', 'Error',
       'Alert scores present and within 0-100',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.alerts
WHERE alert_score IS NULL OR alert_score < 0 OR alert_score > 100

UNION ALL
SELECT 'DQ08', 'Data quality', 'Integrity', 'Error',
       'Alert priority in (Critical, High, Medium, Low)',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.alerts
WHERE priority IS NULL OR priority NOT IN ('Critical', 'High', 'Medium', 'Low')

UNION ALL
SELECT 'DQ09', 'Data quality', 'Integrity', 'Error',
       'Alert customer/account/date match the alerted transaction',
       '0 mismatches',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.alerts a
JOIN core.transactions t ON t.transaction_id = a.transaction_id
WHERE a.customer_id <> t.customer_id
   OR a.account_id  <> t.account_id
   OR a.alert_date  <> t.transaction_timestamp::DATE

UNION ALL
SELECT 'DQ10', 'Data quality', 'Integrity', 'Error',
       'Alert rule IDs exist in reference.alert_rules',
       '0 orphans',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.alerts a
LEFT JOIN reference.alert_rules r ON r.rule_id = a.rule_id
WHERE r.rule_id IS NULL

/* ------------------------------------------------------------
   LC — Alert -> investigation -> case -> SAR lifecycle
   ------------------------------------------------------------ */
UNION ALL
SELECT 'LC01', 'Lifecycle', 'Integrity', 'Error',
       'Every alert has an investigation',
       '0 alerts without investigation',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.alerts a
LEFT JOIN core.investigations i ON i.alert_id = a.alert_id
WHERE i.investigation_id IS NULL

UNION ALL
SELECT 'LC02', 'Lifecycle', 'Integrity', 'Error',
       'Every investigation links to a valid alert',
       '0 orphans',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.investigations i
LEFT JOIN core.alerts a ON a.alert_id = i.alert_id
WHERE a.alert_id IS NULL

UNION ALL
SELECT 'LC03', 'Lifecycle', 'Integrity', 'Error',
       'At most one investigation per alert',
       '0 alerts with >1 investigation',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM (
    SELECT alert_id FROM core.investigations GROUP BY alert_id HAVING COUNT(*) > 1
) d

UNION ALL
SELECT 'LC04', 'Lifecycle', 'Integrity', 'Error',
       'Every investigation is assigned to an existing employee',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.investigations i
LEFT JOIN core.employees e ON e.employee_id = i.investigator_id
WHERE e.employee_id IS NULL

UNION ALL
SELECT 'LC05', 'Lifecycle', 'Integrity', 'Error',
       'Open investigations have no disposition',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.investigations
WHERE investigation_end IS NULL AND disposition IS NOT NULL

UNION ALL
SELECT 'LC06', 'Lifecycle', 'Integrity', 'Error',
       'Closed investigations have a valid disposition',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.investigations
WHERE investigation_end IS NOT NULL
  AND (disposition IS NULL
       OR disposition NOT IN ('False Positive', 'Escalated', 'Monitoring Required', 'Closed - No Issue'))

UNION ALL
SELECT 'LC07', 'Lifecycle', 'Lifecycle', 'Error',
       'Investigation end is not before investigation start',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.investigations
WHERE investigation_end < investigation_start

UNION ALL
SELECT 'LC08', 'Lifecycle', 'Lifecycle', 'Error',
       'Investigation does not start before its alert date',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.investigations i
JOIN core.alerts a ON a.alert_id = i.alert_id
WHERE i.investigation_start::DATE < a.alert_date

UNION ALL
SELECT 'LC09', 'Lifecycle', 'Lifecycle', 'Warning',
       'Investigation starts within 30 days of alert (known synthetic-data limitation)',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.investigations i
JOIN core.alerts a ON a.alert_id = i.alert_id
WHERE i.investigation_start::DATE > a.alert_date + 30

UNION ALL
SELECT 'LC10', 'Lifecycle', 'Integrity', 'Error',
       'Every case links to an existing, completed investigation',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.cases c
LEFT JOIN core.investigations i ON i.investigation_id = c.investigation_id
WHERE i.investigation_id IS NULL OR i.investigation_end IS NULL

UNION ALL
SELECT 'LC11', 'Lifecycle', 'Integrity', 'Error',
       'Case customer matches the investigated alert customer',
       '0 mismatches',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.cases c
JOIN core.investigations i ON i.investigation_id = c.investigation_id
JOIN core.alerts a         ON a.alert_id = i.alert_id
WHERE c.customer_id <> a.customer_id

UNION ALL
SELECT 'LC12', 'Lifecycle', 'Lifecycle', 'Warning',
       'Case opens on/after investigation completion (known limitation: generator opens cases 0-3 days after investigation start)',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.cases c
JOIN core.investigations i ON i.investigation_id = c.investigation_id
WHERE c.case_open_date < i.investigation_end::DATE

UNION ALL
SELECT 'LC17', 'Lifecycle', 'Lifecycle', 'Error',
       'Case closes on/after it opens',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.cases
WHERE case_close_date < case_open_date

UNION ALL
SELECT 'LC13', 'Lifecycle', 'Integrity', 'Error',
       'case_alerts rows reference existing cases and alerts',
       '0 orphans',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.case_alerts ca
LEFT JOIN core.cases  c ON c.case_id  = ca.case_id
LEFT JOIN core.alerts a ON a.alert_id = ca.alert_id
WHERE c.case_id IS NULL OR a.alert_id IS NULL

UNION ALL
SELECT 'LC14', 'Lifecycle', 'Integrity', 'Error',
       'Every SAR links to an existing case for the same customer',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.sar_reports s
LEFT JOIN core.cases c ON c.case_id = s.case_id
WHERE c.case_id IS NULL OR c.customer_id <> s.customer_id

UNION ALL
SELECT 'LC15', 'Lifecycle', 'Integrity', 'Error',
       'At most one SAR per case',
       '0 cases with >1 SAR',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM (
    SELECT case_id FROM core.sar_reports GROUP BY case_id HAVING COUNT(*) > 1
) d

UNION ALL
SELECT 'LC16', 'Lifecycle', 'Lifecycle', 'Error',
       'SAR filing date is on/after case open date',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.sar_reports s
JOIN core.cases c ON c.case_id = s.case_id
WHERE s.filing_date < c.case_open_date

/* ------------------------------------------------------------
   AU — Audit trail
   ------------------------------------------------------------ */
UNION ALL
SELECT 'AU01', 'Audit trail', 'Reconciliation', 'Error',
       'INVESTIGATION_ASSIGNED events = investigations',
       b.investigations::TEXT,
       (SELECT COUNT(*) FROM core.audit_logs WHERE event_type = 'INVESTIGATION_ASSIGNED')::TEXT,
       (SELECT COUNT(*) FROM core.audit_logs WHERE event_type = 'INVESTIGATION_ASSIGNED') = b.investigations
FROM base b

UNION ALL
SELECT 'AU02', 'Audit trail', 'Reconciliation', 'Error',
       'INVESTIGATION_COMPLETED events = completed investigations',
       b.completed_investigations::TEXT,
       (SELECT COUNT(*) FROM core.audit_logs WHERE event_type = 'INVESTIGATION_COMPLETED')::TEXT,
       (SELECT COUNT(*) FROM core.audit_logs WHERE event_type = 'INVESTIGATION_COMPLETED') = b.completed_investigations
FROM base b

UNION ALL
SELECT 'AU03', 'Audit trail', 'Lifecycle', 'Error',
       'No completion event for an open investigation',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.audit_logs al
JOIN core.investigations i ON i.investigation_id = al.related_investigation_id
WHERE al.event_type = 'INVESTIGATION_COMPLETED'
  AND i.investigation_end IS NULL

UNION ALL
SELECT 'AU04', 'Audit trail', 'Integrity', 'Error',
       'Investigator actions reference existing investigations',
       '0 orphans',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM core.investigator_actions ia
LEFT JOIN core.investigations i ON i.investigation_id = ia.investigation_id
WHERE i.investigation_id IS NULL

/* ------------------------------------------------------------
   CR — Customer risk engine
   ------------------------------------------------------------ */
UNION ALL
SELECT 'CR01', 'Customer risk', 'Reconciliation', 'Error',
       'One risk score per customer',
       b.customers::TEXT || ' unique',
       COUNT(DISTINCT r.customer_id)::TEXT || ' unique / ' || COUNT(*)::TEXT || ' rows',
       COUNT(*) = b.customers AND COUNT(DISTINCT r.customer_id) = b.customers
FROM analytics.customer_risk_score r
CROSS JOIN base b
GROUP BY b.customers

UNION ALL
SELECT 'CR02', 'Customer risk', 'Business rule', 'Error',
       'Components within caps (KYC 25, Txn 30, Digital 15, FinCrime 30)',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM analytics.customer_risk_score
WHERE kyc_risk_score         NOT BETWEEN 0 AND 25
   OR transaction_risk_score NOT BETWEEN 0 AND 30
   OR digital_risk_score     NOT BETWEEN 0 AND 15
   OR fincrime_risk_score    NOT BETWEEN 0 AND 30

UNION ALL
SELECT 'CR03', 'Customer risk', 'Business rule', 'Error',
       'Composite score = sum of components and within 0-100',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM analytics.customer_risk_score
WHERE customer_risk_score <> kyc_risk_score + transaction_risk_score + digital_risk_score + fincrime_risk_score
   OR customer_risk_score NOT BETWEEN 0 AND 100

UNION ALL
SELECT 'CR04', 'Customer risk', 'Business rule', 'Error',
       'Risk tier matches score thresholds (Critical >=75, High >=55, Medium >=30)',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM analytics.customer_risk_score
WHERE customer_risk_tier IS DISTINCT FROM
      CASE WHEN customer_risk_score >= 75 THEN 'Critical'
           WHEN customer_risk_score >= 55 THEN 'High'
           WHEN customer_risk_score >= 30 THEN 'Medium'
           ELSE 'Low' END

UNION ALL
SELECT 'CR05', 'Customer risk', 'Reconciliation', 'Error',
       'Risk features reconcile to core (transactions / suspicious / alerts / cases / SARs)',
       b.transactions || ' / ' || b.suspicious_transactions || ' / ' || b.alerts || ' / ' || b.cases || ' / ' || b.sars,
       SUM(r.transaction_count) || ' / ' || SUM(r.suspicious_transaction_count) || ' / ' || SUM(r.alert_count)
           || ' / ' || SUM(r.case_count) || ' / ' || SUM(r.sar_count),
       SUM(r.transaction_count) = b.transactions
   AND SUM(r.suspicious_transaction_count) = b.suspicious_transactions
   AND SUM(r.alert_count) = b.alerts
   AND SUM(r.case_count)  = b.cases
   AND SUM(r.sar_count)   = b.sars
FROM analytics.customer_risk_score r
CROSS JOIN base b
GROUP BY b.transactions, b.suspicious_transactions, b.alerts, b.cases, b.sars

/* ------------------------------------------------------------
   EN — Entity resolution and network
   ------------------------------------------------------------ */
UNION ALL
SELECT 'EN01', 'Entity network', 'Integrity', 'Error',
       'Relationship pairs are canonical (customer_1 < customer_2), so no self-links',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM analytics.entity_relationships
WHERE customer_1 >= customer_2

UNION ALL
SELECT 'EN02', 'Entity network', 'Integrity', 'Error',
       'Relationship pairs are unique',
       '0 duplicates',
       (COUNT(*) - COUNT(DISTINCT (customer_1, customer_2)))::TEXT,
       COUNT(*) = COUNT(DISTINCT (customer_1, customer_2))
FROM analytics.entity_relationships

UNION ALL
SELECT 'EN03', 'Entity network', 'Integrity', 'Error',
       'Relationship customers exist in core.customers',
       '0 orphans',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM analytics.entity_relationships e
LEFT JOIN core.customers c1 ON c1.customer_id = e.customer_1
LEFT JOIN core.customers c2 ON c2.customer_id = e.customer_2
WHERE c1.customer_id IS NULL OR c2.customer_id IS NULL

UNION ALL
SELECT 'EN04', 'Entity network', 'Business rule', 'Error',
       'Every link has rare-IP evidence, common IPs (prevalence > 5) suppressed, strength > 0',
       '0 rows',
       COUNT(*)::TEXT,
       COUNT(*) = 0
FROM analytics.entity_relationships
WHERE shared_rare_ip_count <= 0
   OR rarest_shared_ip_prevalence > 5
   OR relationship_strength_score <= 0

UNION ALL
SELECT 'EN05', 'Entity network', 'Reconciliation', 'Error',
       'Network metrics cover every customer',
       b.customers::TEXT,
       COUNT(*)::TEXT,
       COUNT(*) = b.customers
FROM analytics.customer_network_metrics
CROSS JOIN base b
GROUP BY b.customers

UNION ALL
SELECT 'EN06', 'Entity network', 'Reconciliation', 'Error',
       'Sum of network degree = 2 x relationship pairs',
       (2 * b.relationships)::TEXT,
       SUM(m.network_degree)::TEXT,
       SUM(m.network_degree) = 2 * b.relationships AND MIN(m.network_degree) >= 0
FROM analytics.customer_network_metrics m
CROSS JOIN base b
GROUP BY b.relationships

/* ------------------------------------------------------------
   PB — Power BI semantic layer reconciles to core
   ------------------------------------------------------------ */
UNION ALL
SELECT 'PB01', 'Power BI layer', 'Reconciliation', 'Error',
       'Executive KPI view returns exactly one row',
       '1',
       COUNT(*)::TEXT,
       COUNT(*) = 1
FROM analytics.vw_executive_kpis

UNION ALL
SELECT 'PB02', 'Power BI layer', 'Reconciliation', 'Error',
       'Executive KPIs = core (customers / transactions / alerts / investigations / open / completed / cases / SARs)',
       b.customers || ' / ' || b.transactions || ' / ' || b.alerts || ' / ' || b.investigations || ' / '
           || b.open_investigations || ' / ' || b.completed_investigations || ' / ' || b.cases || ' / ' || b.sars,
       k.total_customers || ' / ' || k.total_transactions || ' / ' || k.total_alerts || ' / ' || k.total_investigations || ' / '
           || k.open_investigations || ' / ' || k.completed_investigations || ' / ' || k.total_cases || ' / ' || k.total_sars,
       k.total_customers = b.customers AND k.total_transactions = b.transactions AND k.total_alerts = b.alerts
   AND k.total_investigations = b.investigations AND k.open_investigations = b.open_investigations
   AND k.completed_investigations = b.completed_investigations AND k.total_cases = b.cases AND k.total_sars = b.sars
FROM analytics.vw_executive_kpis k
CROSS JOIN base b

UNION ALL
SELECT 'PB03', 'Power BI layer', 'Reconciliation', 'Error',
       'Executive volume = SUM(core.transactions.amount)',
       (SELECT SUM(amount) FROM core.transactions)::TEXT,
       k.total_transaction_volume::TEXT,
       k.total_transaction_volume = (SELECT SUM(amount) FROM core.transactions)
FROM analytics.vw_executive_kpis k

UNION ALL
SELECT 'PB04', 'Power BI layer', 'Reconciliation', 'Error',
       'Executive conversion % recomputes from core (inv->case = cases/completed, case->SAR = SARs/cases)',
       ROUND(100.0 * b.cases / NULLIF(b.completed_investigations, 0), 2) || '% / '
           || ROUND(100.0 * b.sars / NULLIF(b.cases, 0), 2) || '%',
       k.investigation_to_case_pct || '% / ' || k.case_to_sar_pct || '%',
       k.investigation_to_case_pct = ROUND(100.0 * b.cases / NULLIF(b.completed_investigations, 0), 2)
   AND k.case_to_sar_pct           = ROUND(100.0 * b.sars  / NULLIF(b.cases, 0), 2)
FROM analytics.vw_executive_kpis k
CROSS JOIN base b

UNION ALL
SELECT 'PB05', 'Power BI layer', 'Reconciliation', 'Error',
       'Executive risk/network KPIs = analytics tables (critical / high / relationships / connected)',
       (SELECT COUNT(*) FROM analytics.customer_risk_score WHERE customer_risk_tier = 'Critical') || ' / '
           || (SELECT COUNT(*) FROM analytics.customer_risk_score WHERE customer_risk_tier = 'High') || ' / '
           || b.relationships || ' / ' || b.connected_customers,
       k.critical_risk_customers || ' / ' || k.high_risk_customers || ' / ' || k.entity_relationships || ' / ' || k.connected_customers,
       k.critical_risk_customers = (SELECT COUNT(*) FROM analytics.customer_risk_score WHERE customer_risk_tier = 'Critical')
   AND k.high_risk_customers     = (SELECT COUNT(*) FROM analytics.customer_risk_score WHERE customer_risk_tier = 'High')
   AND k.entity_relationships    = b.relationships
   AND k.connected_customers     = b.connected_customers
FROM analytics.vw_executive_kpis k
CROSS JOIN base b

UNION ALL
SELECT 'PB06', 'Power BI layer', 'Reconciliation', 'Error',
       'Monthly funnel alerts sum to total alerts',
       b.alerts::TEXT,
       SUM(f.alerts)::TEXT,
       SUM(f.alerts) = b.alerts
FROM analytics.vw_monthly_fincrime_funnel f
CROSS JOIN base b
GROUP BY b.alerts

UNION ALL
SELECT 'PB07', 'Power BI layer', 'Reconciliation', 'Error',
       'TM rule view sums to total alerts / investigations',
       b.alerts || ' / ' || b.investigations,
       SUM(r.alerts) || ' / ' || SUM(r.investigations),
       SUM(r.alerts) = b.alerts AND SUM(r.investigations) = b.investigations
FROM analytics.vw_tm_rule_performance r
CROSS JOIN base b
GROUP BY b.alerts, b.investigations

UNION ALL
SELECT 'PB08', 'Power BI layer', 'Reconciliation', 'Error',
       'Investigator view assignments sum to total investigations',
       b.investigations::TEXT,
       SUM(p.assigned_investigations)::TEXT,
       SUM(p.assigned_investigations) = b.investigations
FROM analytics.vw_investigator_performance p
CROSS JOIN base b
GROUP BY b.investigations

UNION ALL
SELECT 'PB09', 'Power BI layer', 'Reconciliation', 'Error',
       'SLA view has one row per investigation, each with an SLA status',
       b.investigations::TEXT || ' rows, 0 null status',
       COUNT(*) || ' rows, ' || COUNT(*) FILTER (WHERE s.sla_status IS NULL) || ' null status',
       COUNT(*) = b.investigations AND COUNT(*) FILTER (WHERE s.sla_status IS NULL) = 0
FROM analytics.vw_investigation_sla s
CROSS JOIN base b
GROUP BY b.investigations

UNION ALL
SELECT 'PB10', 'Power BI layer', 'Reconciliation', 'Error',
       'Customer risk and network views cover every customer',
       b.customers || ' / ' || b.customers,
       (SELECT COUNT(*) FROM analytics.vw_customer_risk_dashboard) || ' / '
           || (SELECT COUNT(*) FROM analytics.vw_network_customer_metrics),
       (SELECT COUNT(*) FROM analytics.vw_customer_risk_dashboard)  = b.customers
   AND (SELECT COUNT(*) FROM analytics.vw_network_customer_metrics) = b.customers
FROM base b

UNION ALL
SELECT 'PB11', 'Power BI layer', 'Reconciliation', 'Error',
       'Network relationship view = entity_relationships',
       b.relationships::TEXT,
       COUNT(*)::TEXT,
       COUNT(*) = b.relationships
FROM analytics.vw_network_relationships
CROSS JOIN base b
GROUP BY b.relationships

UNION ALL
SELECT 'PB12', 'Power BI layer', 'Reconciliation', 'Error',
       'Threshold simulation baseline (lowest threshold) retains all alerts / SARs',
       b.alerts || ' / ' || b.sars,
       t.alerts_retained || ' / ' || t.sars_retained,
       t.alerts_retained = b.alerts AND t.sars_retained = b.sars
FROM analytics.vw_tm_threshold_simulation t
CROSS JOIN base b
WHERE t.threshold = (SELECT MIN(threshold) FROM analytics.vw_tm_threshold_simulation)

UNION ALL
SELECT 'PB13', 'Power BI layer', 'Business rule', 'Error',
       'Threshold simulation: retained alerts/cases/SARs never increase as threshold rises',
       '0 rows',
       COUNT(*) FILTER (WHERE alerts_retained > prev_alerts OR cases_retained > prev_cases OR sars_retained > prev_sars)::TEXT,
       COUNT(*) FILTER (WHERE alerts_retained > prev_alerts OR cases_retained > prev_cases OR sars_retained > prev_sars) = 0
FROM (
    SELECT alerts_retained, cases_retained, sars_retained,
           LAG(alerts_retained) OVER (ORDER BY threshold) AS prev_alerts,
           LAG(cases_retained)  OVER (ORDER BY threshold) AS prev_cases,
           LAG(sars_retained)   OVER (ORDER BY threshold) AS prev_sars
    FROM analytics.vw_tm_threshold_simulation
) s

/* ------------------------------------------------------------
   SN — v1.0 documented baseline (update deliberately after regeneration)
   ------------------------------------------------------------ */
UNION ALL
SELECT 'SN01', 'Baseline v1.0', 'Snapshot', 'Error',
       'Population: customers / transactions / suspicious transactions',
       '10000 / 500000 / 8500',
       b.customers || ' / ' || b.transactions || ' / ' || b.suspicious_transactions,
       b.customers = 10000 AND b.transactions = 500000 AND b.suspicious_transactions = 8500
FROM base b

UNION ALL
SELECT 'SN02', 'Baseline v1.0', 'Snapshot', 'Error',
       'Workflow: alerts / investigations / open / cases / SARs',
       '53392 / 53392 / 5339 / 18597 / 11103',
       b.alerts || ' / ' || b.investigations || ' / ' || b.open_investigations || ' / ' || b.cases || ' / ' || b.sars,
       b.alerts = 53392 AND b.investigations = 53392 AND b.open_investigations = 5339
   AND b.cases = 18597 AND b.sars = 11103
FROM base b

UNION ALL
SELECT 'SN03', 'Baseline v1.0', 'Snapshot', 'Error',
       'Risk tiers: Critical / High / Medium / Low',
       '3 / 524 / 6454 / 3019',
       COUNT(*) FILTER (WHERE customer_risk_tier = 'Critical') || ' / '
           || COUNT(*) FILTER (WHERE customer_risk_tier = 'High') || ' / '
           || COUNT(*) FILTER (WHERE customer_risk_tier = 'Medium') || ' / '
           || COUNT(*) FILTER (WHERE customer_risk_tier = 'Low'),
       COUNT(*) FILTER (WHERE customer_risk_tier = 'Critical') = 3
   AND COUNT(*) FILTER (WHERE customer_risk_tier = 'High')     = 524
   AND COUNT(*) FILTER (WHERE customer_risk_tier = 'Medium')   = 6454
   AND COUNT(*) FILTER (WHERE customer_risk_tier = 'Low')      = 3019
FROM analytics.customer_risk_score

UNION ALL
SELECT 'SN04', 'Baseline v1.0', 'Snapshot', 'Error',
       'Network: relationships / connected customers',
       '389 / 207',
       b.relationships || ' / ' || b.connected_customers,
       b.relationships = 389 AND b.connected_customers = 207
FROM base b
)

SELECT
    check_id,
    area,
    check_type,
    severity,
    check_name,
    expected,
    actual,
    CASE
        WHEN passed THEN 'PASS'
        WHEN severity = 'Warning' THEN 'WARN'
        ELSE 'FAIL'
    END AS result
FROM checks
ORDER BY
    CASE LEFT(check_id, 2)
        WHEN 'DQ' THEN 1 WHEN 'LC' THEN 2 WHEN 'AU' THEN 3 WHEN 'CR' THEN 4
        WHEN 'EN' THEN 5 WHEN 'PB' THEN 6 ELSE 7
    END,
    check_id;
