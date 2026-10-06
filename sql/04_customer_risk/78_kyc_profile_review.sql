/* ============================================================
   78. KYC PROFILE REVIEW — EXPECTED vs ACTUAL ACTIVITY
   ------------------------------------------------------------
   Question answered:
     Which customers' KYC profiles need review, and why?

   Inputs:
     core.customer_kyc   declared expected monthly activity, KYC level,
                         status and review dates (set at onboarding)
     core.transactions   observed activity (Jan 2023 - Dec 2025)
     core.customers      KYC risk rating and PEP flag
     analytics.customer_risk_score  composite risk tier

   Findings flagged per customer:
     EDD gap               KYC High-risk or PEP customer on Standard
                           (not Enhanced) due diligence
     Activity > profile    average monthly activity >= 2x declared
                           expected monthly volume
     Status/date conflict  KYC status 'Expired' while next review
                           date is still in the future

   Review priority (as of the 2026-06-30 reporting snapshot):
     P1  EDD gap AND activity >= 2x profile
     P2  EDD gap, OR activity >= 2x profile for a High/Critical-tier customer
     P3  Activity >= 2x profile, status/date conflict, or KYC not Approved
     --  No action

   Average monthly activity = total transaction amount / months from the
   customer's first transaction month through Dec 2025, so customers who
   started transacting later are not understated.
   ============================================================ */

DROP VIEW IF EXISTS analytics.vw_kyc_profile_review;

CREATE VIEW analytics.vw_kyc_profile_review AS

WITH monthly AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', transaction_timestamp)::DATE AS txn_month,
        SUM(amount)                                      AS month_volume
    FROM core.transactions
    GROUP BY 1, 2
),

activity AS (
    SELECT
        customer_id,
        MIN(txn_month)                                                       AS first_txn_month,
        (DATE_PART('year', AGE(DATE '2025-12-01', MIN(txn_month))) * 12
         + DATE_PART('month', AGE(DATE '2025-12-01', MIN(txn_month))) + 1)::INTEGER AS active_months,
        SUM(month_volume)                                                    AS total_volume,
        MAX(month_volume)                                                    AS peak_month_volume
    FROM monthly
    GROUP BY customer_id
),

profile AS (
    SELECT
        c.customer_id,
        c.kyc_risk_rating,
        c.politically_exposed_person_flag                           AS is_pep,
        r.customer_risk_tier,
        k.kyc_level,
        k.kyc_status,
        k.last_review_date,
        k.next_review_date,
        k.expected_monthly_txn_volume,
        a.active_months,
        ROUND(a.total_volume / a.active_months, 2)                  AS actual_avg_monthly_volume,
        ROUND(a.peak_month_volume, 2)                               AS peak_monthly_volume,
        ROUND(a.total_volume / a.active_months
              / NULLIF(k.expected_monthly_txn_volume, 0), 2)        AS activity_to_profile_ratio,
        (SELECT COUNT(*) FROM monthly m
         WHERE m.customer_id = c.customer_id
           AND m.month_volume >= 3 * k.expected_monthly_txn_volume) AS months_over_3x_profile
    FROM core.customers c
    JOIN core.customer_kyc k              ON k.customer_id = c.customer_id
    LEFT JOIN activity a                  ON a.customer_id = c.customer_id
    LEFT JOIN analytics.customer_risk_score r ON r.customer_id = c.customer_id
),

flagged AS (
    SELECT
        p.*,
        (p.kyc_risk_rating = 'High' OR p.is_pep) AND p.kyc_level = 'Standard'      AS edd_gap,
        COALESCE(p.activity_to_profile_ratio >= 2, FALSE)                          AS activity_exceeds_profile,
        p.kyc_status = 'Expired' AND p.next_review_date > DATE '2026-06-30'        AS status_date_conflict
    FROM profile p
)

SELECT
    f.*,

    CASE
        WHEN f.activity_to_profile_ratio IS NULL THEN 'No activity'
        WHEN f.activity_to_profile_ratio < 1.5   THEN '1. Within profile (<1.5x)'
        WHEN f.activity_to_profile_ratio < 2     THEN '2. Above profile (1.5-2x)'
        WHEN f.activity_to_profile_ratio < 3     THEN '3. Exceeds profile (2-3x)'
        ELSE                                          '4. Far exceeds profile (3x+)'
    END AS activity_band,

    CASE
        WHEN f.edd_gap AND f.activity_exceeds_profile THEN 'P1'
        WHEN f.edd_gap
          OR (f.activity_exceeds_profile AND f.customer_risk_tier IN ('High', 'Critical')) THEN 'P2'
        WHEN f.activity_exceeds_profile
          OR f.status_date_conflict
          OR f.kyc_status <> 'Approved' THEN 'P3'
        ELSE 'No action'
    END AS review_priority,

    CONCAT_WS('; ',
        CASE WHEN f.edd_gap THEN 'High-risk/PEP on Standard KYC (EDD gap)' END,
        CASE WHEN f.activity_exceeds_profile
             THEN 'Activity ' || f.activity_to_profile_ratio || 'x declared profile' END,
        CASE WHEN f.status_date_conflict THEN 'Expired status with future review date' END,
        CASE WHEN f.kyc_status = 'Pending Review' THEN 'KYC pending review' END
    ) AS review_reasons

FROM flagged f;


/* ============================================================
   78a. SUMMARY QUERIES
   ============================================================ */

/* Review queue by priority */
SELECT
    review_priority,
    COUNT(*)                                          AS customers,
    COUNT(*) FILTER (WHERE edd_gap)                   AS edd_gaps,
    COUNT(*) FILTER (WHERE activity_exceeds_profile)  AS activity_exceeds_profile,
    COUNT(*) FILTER (WHERE status_date_conflict)      AS status_date_conflicts
FROM analytics.vw_kyc_profile_review
GROUP BY review_priority
ORDER BY review_priority;

/* Activity versus declared profile */
SELECT
    activity_band,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_customers
FROM analytics.vw_kyc_profile_review
GROUP BY activity_band
ORDER BY activity_band;

/* Due-diligence level by KYC risk rating (EDD gap evidence) */
SELECT
    kyc_risk_rating,
    COUNT(*) FILTER (WHERE kyc_level = 'Enhanced') AS enhanced_dd,
    COUNT(*) FILTER (WHERE kyc_level = 'Standard') AS standard_dd,
    ROUND(100.0 * COUNT(*) FILTER (WHERE kyc_level = 'Standard') / COUNT(*), 2) AS pct_on_standard
FROM analytics.vw_kyc_profile_review
GROUP BY kyc_risk_rating
ORDER BY kyc_risk_rating;

/* Is the declared profile predictive of actual activity? (correlation near 0 = profile not calibrated) */
SELECT
    ROUND(CORR(actual_avg_monthly_volume, expected_monthly_txn_volume)::NUMERIC, 3) AS correlation_actual_vs_expected
FROM analytics.vw_kyc_profile_review;
