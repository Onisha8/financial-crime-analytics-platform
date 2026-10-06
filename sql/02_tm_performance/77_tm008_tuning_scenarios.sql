/* ============================================================
   77. TM008 HIGH-RISK MERCHANT — TUNING SCENARIOS
   ------------------------------------------------------------
   Current TM008 logic (sql/01_alert_generation/06_tm008_high_risk_merchant.sql):
     one alert per CARD_PURCHASE >= $500 where the merchant is
     rated High OR is in Money Services, Crypto Exchange, Gaming,
     Jewelry, Pawn Shop.

   Diagnosis (see 77a queries at the end of this file):
     - TM008 produces 67.7% of all TM alerts and has alerted on
       ~95% of all customers.
     - The $500 trigger sits just above the median card purchase
       ($453), so it fires on ordinary spend: ~45% of all card
       purchases are >= $500.
     - Alerted customers are no riskier than the customer base:
       the KYC High / PEP share of alerted customers equals the
       population rate (lift ~1.0), and the alert rate is ~94%
       in every KYC risk tier.
     - The rule is single-transaction: it ignores repetition.
       Only 868 customers ever show a 2+ purchase / $1.5K pattern
       within 30 days, and only 190 show 3+ purchases.

   Results summary (v1.0 data):
     - Consolidation alone (S1) or narrowing categories (S2) cuts
       volume by only ~6%: the problem is the trigger, not duplicates.
     - Repeat-pattern rules (S3/S4) cut volume 97-99% but do NOT
       target higher-risk profiles better (lift 1.00-1.14): in this
       synthetic data, purchase behaviour is independent of KYC risk.
     - The hybrid (S6) cuts volume 91% while keeping every
       KYC High-risk / PEP customer alerted today. Its targeting
       lift comes from segmenting on KYC risk by design, not from
       a discovered pattern. The trade-off is that ~8,100 standard-
       risk customers would no longer alert on a single purchase:
       a risk-appetite decision, not an analytical one.

   Scenarios compared (retrospective, on the same transactions):
     S0  Current rule (one alert per qualifying transaction)
     S1  Current rule, consolidated to one alert per customer per month
     S2  High-risk categories only (drops ordinary merchants rated High)
     S3  Pattern: >= 2 qualifying high-risk-category purchases within
         30 days totalling >= $1,500 (one alert per customer per month)
     S4  Pattern: >= 3 qualifying purchases within 30 days
         (one alert per customer per month)
     S5  Risk-segmented: current single-transaction logic only for
         KYC High-risk or PEP customers
     S6  Hybrid (proposed): S3 for all customers, plus S5 for
         KYC High-risk / PEP customers

   Effectiveness measure:
     Investigation outcomes (case/SAR) are NOT used to compare
     scenarios: synthetic dispositions are randomly assigned and
     carry no signal (see docs/limitations). Scenarios are compared
     on workload and on targeting: the share of alerted customers
     who are KYC High-risk or PEP, versus the population rate
     (lift). KYC rating and PEP status are set at onboarding and
     are independent of TM alert history.
   ============================================================ */

DROP VIEW IF EXISTS analytics.vw_tm008_tuning_scenarios;

CREATE VIEW analytics.vw_tm008_tuning_scenarios AS

WITH customers AS (
    SELECT
        customer_id,
        (kyc_risk_rating = 'High' OR politically_exposed_person_flag) AS is_high_risk_profile
    FROM core.customers
),

/* Every transaction that meets current TM008 conditions */
qualifying AS (
    SELECT
        t.transaction_id,
        t.customer_id,
        t.transaction_timestamp,
        t.amount,
        m.merchant_category IN ('Money Services', 'Crypto Exchange', 'Gaming', 'Jewelry', 'Pawn Shop')
            AS is_high_risk_category
    FROM core.transactions t
    JOIN core.merchants m ON m.merchant_id = t.merchant_id
    WHERE t.transaction_type = 'CARD_PURCHASE'
      AND t.amount >= 500
      AND (
            m.merchant_risk_rating = 'High'
            OR m.merchant_category IN ('Money Services', 'Crypto Exchange', 'Gaming', 'Jewelry', 'Pawn Shop')
          )
),

/* Rolling 30-day behaviour per customer, evaluated at each transaction */
windowed AS (
    SELECT
        q.*,
        COUNT(*) OVER w30                                        AS purchases_30d,
        COUNT(*) FILTER (WHERE is_high_risk_category) OVER w30   AS hr_category_purchases_30d,
        SUM(amount) FILTER (WHERE is_high_risk_category) OVER w30 AS hr_category_amount_30d
    FROM qualifying q
    WINDOW w30 AS (
        PARTITION BY customer_id
        ORDER BY transaction_timestamp
        RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW
    )
),

/* Alert rows per scenario.
   alert_key = the unit that becomes one alert:
     transaction-level  -> transaction_id
     consolidated       -> customer + calendar month */
scenario_alerts AS (
    SELECT 'S0' AS scenario_id, customer_id, transaction_id AS alert_key
    FROM windowed

    UNION ALL
    SELECT 'S1', customer_id, customer_id || '|' || TO_CHAR(transaction_timestamp, 'YYYY-MM')
    FROM windowed

    UNION ALL
    SELECT 'S2', customer_id, transaction_id
    FROM windowed
    WHERE is_high_risk_category

    UNION ALL
    SELECT 'S3', customer_id, customer_id || '|' || TO_CHAR(transaction_timestamp, 'YYYY-MM')
    FROM windowed
    WHERE is_high_risk_category
      AND hr_category_purchases_30d >= 2
      AND hr_category_amount_30d >= 1500

    UNION ALL
    SELECT 'S4', customer_id, customer_id || '|' || TO_CHAR(transaction_timestamp, 'YYYY-MM')
    FROM windowed
    WHERE purchases_30d >= 3

    UNION ALL
    SELECT 'S5', w.customer_id, w.transaction_id
    FROM windowed w
    JOIN customers c USING (customer_id)
    WHERE c.is_high_risk_profile

    UNION ALL   -- S6 = S3 pattern alerts + S5 single-transaction alerts
    SELECT 'S6', customer_id, customer_id || '|' || TO_CHAR(transaction_timestamp, 'YYYY-MM')
    FROM windowed
    WHERE is_high_risk_category
      AND hr_category_purchases_30d >= 2
      AND hr_category_amount_30d >= 1500
    UNION ALL
    SELECT 'S6', w.customer_id, w.transaction_id
    FROM windowed w
    JOIN customers c USING (customer_id)
    WHERE c.is_high_risk_profile
),

scenario_summary AS (
    SELECT
        s.scenario_id,
        COUNT(DISTINCT s.alert_key)                                         AS alerts,
        COUNT(DISTINCT s.customer_id)                                       AS customers_alerted,
        COUNT(DISTINCT s.customer_id) FILTER (WHERE c.is_high_risk_profile) AS high_risk_customers_alerted
    FROM scenario_alerts s
    JOIN customers c USING (customer_id)
    GROUP BY s.scenario_id
),

population AS (
    SELECT
        COUNT(*)                                       AS customers,
        COUNT(*) FILTER (WHERE is_high_risk_profile)   AS high_risk_customers
    FROM customers
),

labels AS (
    SELECT * FROM (VALUES
        ('S0', 'Current rule',               'Transaction',     'Card purchase >= $500 at a High-rated merchant or high-risk category'),
        ('S1', 'Current + consolidation',    'Customer-month',  'Same conditions; one alert per customer per month'),
        ('S2', 'High-risk categories only',  'Transaction',     'Drops ordinary merchants (grocery, utilities, ...) that are rated High'),
        ('S3', 'Repeat pattern (2+ / $1.5K)','Customer-month',  '>= 2 high-risk-category purchases within 30 days totalling >= $1,500'),
        ('S4', 'Repeat pattern (3+)',        'Customer-month',  '>= 3 qualifying purchases within 30 days'),
        ('S5', 'Risk-segmented',             'Transaction',     'Current logic for KYC High-risk or PEP customers only'),
        ('S6', 'Hybrid (proposed)',          'Mixed',           'S3 pattern for all customers + S5 for KYC High-risk / PEP customers')
    ) AS l(scenario_id, scenario_name, alert_unit, scenario_logic)
)

SELECT
    l.scenario_id,
    l.scenario_name,
    l.alert_unit,
    l.scenario_logic,

    /* Workload */
    s.alerts,
    ROUND(100.0 - 100.0 * s.alerts / b.alerts, 2)                           AS alert_reduction_pct,
    s.customers_alerted,
    ROUND(100.0 * s.customers_alerted / p.customers, 2)                     AS pct_of_customer_base,

    /* Targeting */
    s.high_risk_customers_alerted,
    ROUND(100.0 * s.high_risk_customers_alerted / s.customers_alerted, 2)   AS high_risk_share_pct,
    ROUND(100.0 * p.high_risk_customers / p.customers, 2)                   AS population_high_risk_share_pct,
    ROUND(
        (1.0 * s.high_risk_customers_alerted / s.customers_alerted)
        / (1.0 * p.high_risk_customers / p.customers), 2)                   AS high_risk_lift,
    ROUND(100.0 * s.high_risk_customers_alerted / b.high_risk_customers_alerted, 2)
                                                                            AS high_risk_coverage_vs_current_pct
FROM labels l
JOIN scenario_summary s USING (scenario_id)
CROSS JOIN population p
CROSS JOIN (SELECT alerts, high_risk_customers_alerted FROM scenario_summary WHERE scenario_id = 'S0') b;


/* ============================================================
   77a. DIAGNOSTIC QUERIES (evidence for the header findings)
   ============================================================ */

/* Share of all TM alerts and of all customers */
SELECT
    COUNT(*) FILTER (WHERE rule_id = 'TM008')                                    AS tm008_alerts,
    ROUND(100.0 * COUNT(*) FILTER (WHERE rule_id = 'TM008') / COUNT(*), 2)       AS pct_of_all_alerts,
    COUNT(DISTINCT customer_id) FILTER (WHERE rule_id = 'TM008')                 AS customers_alerted,
    ROUND(100.0 * COUNT(DISTINCT customer_id) FILTER (WHERE rule_id = 'TM008')
          / (SELECT COUNT(*) FROM core.customers), 2)                            AS pct_of_customers
FROM core.alerts;

/* Where the $500 trigger sits in the card purchase distribution */
SELECT
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY amount)::NUMERIC, 2) AS median_card_purchase,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY amount)::NUMERIC, 2) AS p95_card_purchase,
    ROUND(100.0 * COUNT(*) FILTER (WHERE amount >= 500) / COUNT(*), 2)       AS pct_card_purchases_at_or_above_500
FROM core.transactions
WHERE transaction_type = 'CARD_PURCHASE';

/* TM008 alert rate is the same in every KYC risk tier */
SELECT
    c.kyc_risk_rating,
    COUNT(*)                                                         AS customers,
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM core.alerts a
        WHERE a.customer_id = c.customer_id AND a.rule_id = 'TM008')) AS customers_with_tm008,
    ROUND(100.0 * COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM core.alerts a
        WHERE a.customer_id = c.customer_id AND a.rule_id = 'TM008')) / COUNT(*), 2) AS pct_alerted
FROM core.customers c
GROUP BY c.kyc_risk_rating
ORDER BY pct_alerted DESC;

/* Alerts at ordinary merchant categories (in scope only because the merchant is rated High) */
SELECT
    m.merchant_category,
    COUNT(*) AS tm008_alerts
FROM core.alerts a
JOIN core.transactions t ON t.transaction_id = a.transaction_id
JOIN core.merchants m    ON m.merchant_id = t.merchant_id
WHERE a.rule_id = 'TM008'
  AND m.merchant_category NOT IN ('Money Services', 'Crypto Exchange', 'Gaming', 'Jewelry', 'Pawn Shop')
GROUP BY m.merchant_category
ORDER BY tm008_alerts DESC;
