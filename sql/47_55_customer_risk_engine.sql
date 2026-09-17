/* ============================================================
   CUSTOMER RISK SCORING ENGINE
   Analyses 47–55

   47 - Customer Transaction Features
   48 - Digital Risk Features
   49 - FinCrime History Features
   50 - Customer Feature Mart
   51 - Component Risk Scores
   52 - Composite Customer Risk Score
   53 - Risk Tier Distribution
   54 - High-Risk Customer Analysis
   55 - Risk Driver / Validation Analysis

   DESIGN
   ------
   KYC Risk          0–25
   Transaction Risk  0–30
   Digital Risk      0–15
   FinCrime Risk     0–30
                     ----
   Total             0–100

   IMPORTANT:
   This is a transparent synthetic portfolio scoring framework.
   It is not a regulatory model or production bank methodology.
   ============================================================ */


CREATE SCHEMA IF NOT EXISTS analytics;


/* ============================================================
   CLEAN REBUILD

   These are derived analytics tables, so rebuilding them is safe.
   ============================================================ */

DROP TABLE IF EXISTS analytics.customer_risk_score;
DROP TABLE IF EXISTS analytics.customer_risk_features;


/* ============================================================
   47–50. CUSTOMER FEATURE MART
   ============================================================ */

CREATE TABLE analytics.customer_risk_features AS

WITH transaction_features AS (

    SELECT
        t.customer_id,

        COUNT(*) AS transaction_count,

        ROUND(SUM(t.amount), 2)
            AS transaction_volume,

        ROUND(AVG(t.amount), 2)
            AS avg_transaction_amount,

        ROUND(MAX(t.amount), 2)
            AS max_transaction_amount,

        COUNT(*) FILTER (
            WHERE t.suspicious_flag = TRUE
        ) AS suspicious_transaction_count,

        ROUND(
            SUM(t.amount) FILTER (
                WHERE t.suspicious_flag = TRUE
            ),
            2
        ) AS suspicious_transaction_volume,

        COUNT(*) FILTER (
            WHERE t.destination_country <> 'US'
        ) AS cross_border_transaction_count,

        ROUND(
            SUM(t.amount) FILTER (
                WHERE t.destination_country <> 'US'
            ),
            2
        ) AS cross_border_volume,

        COUNT(*) FILTER (
            WHERE t.transaction_type = 'WIRE_TRANSFER'
        ) AS wire_transfer_count,

        ROUND(
            SUM(t.amount) FILTER (
                WHERE t.transaction_type = 'WIRE_TRANSFER'
            ),
            2
        ) AS wire_transfer_volume,

        COUNT(*) FILTER (
            WHERE m.merchant_risk_rating = 'High'
        ) AS high_risk_merchant_transactions,

        COUNT(DISTINCT t.beneficiary_id) FILTER (
            WHERE t.beneficiary_id IS NOT NULL
        ) AS distinct_beneficiaries,

        COUNT(DISTINCT t.device_id) FILTER (
            WHERE t.device_id IS NOT NULL
        ) AS transaction_devices,

        COUNT(DISTINCT t.ip_id) FILTER (
            WHERE t.ip_id IS NOT NULL
        ) AS transaction_ips

    FROM core.transactions t

    LEFT JOIN core.merchants m
        ON t.merchant_id = m.merchant_id

    GROUP BY t.customer_id
),


digital_features AS (

    SELECT
        le.customer_id,

        COUNT(*) AS login_count,

        COUNT(*) FILTER (
            WHERE le.login_success = FALSE
        ) AS failed_login_count,

        COUNT(*) FILTER (
            WHERE le.login_success = TRUE
              AND le.mfa_used = FALSE
        ) AS successful_non_mfa_logins,

        COUNT(*) FILTER (
            WHERE ip.risk_rating = 'High'
        ) AS high_risk_ip_logins,

        COUNT(DISTINCT le.device_id) FILTER (
            WHERE le.device_id IS NOT NULL
        ) AS login_devices,

        COUNT(DISTINCT le.ip_id) FILTER (
            WHERE le.ip_id IS NOT NULL
        ) AS login_ips

    FROM core.login_events le

    LEFT JOIN core.ip_addresses ip
        ON le.ip_id = ip.ip_id

    GROUP BY le.customer_id
),


registered_devices AS (

    SELECT
        customer_id,
        COUNT(DISTINCT device_id)
            AS registered_device_count

    FROM core.devices

    GROUP BY customer_id
),


beneficiary_features AS (

    SELECT
        customer_id,

        COUNT(DISTINCT beneficiary_id)
            AS registered_beneficiary_count,

        COUNT(DISTINCT beneficiary_bank_country) FILTER (
            WHERE beneficiary_bank_country <> 'US'
        ) AS foreign_beneficiary_countries

    FROM core.beneficiaries

    GROUP BY customer_id
),


account_features AS (

    SELECT
        customer_id,

        COUNT(*) AS account_count,

        COUNT(*) FILTER (
            WHERE status = 'Active'
        ) AS active_account_count,

        ROUND(SUM(current_balance), 2)
            AS total_current_balance

    FROM core.accounts

    GROUP BY customer_id
),


alert_features AS (

    SELECT
        customer_id,

        COUNT(*) AS alert_count,

        COUNT(DISTINCT rule_id)
            AS distinct_tm_rules,

        ROUND(AVG(alert_score), 2)
            AS avg_alert_score,

        ROUND(MAX(alert_score), 2)
            AS max_alert_score,

        COUNT(*) FILTER (
            WHERE priority = 'High'
        ) AS high_priority_alerts,

        COUNT(*) FILTER (
            WHERE priority = 'Medium'
        ) AS medium_priority_alerts

    FROM core.alerts

    GROUP BY customer_id
),


case_features AS (

    SELECT
        customer_id,

        COUNT(*) AS case_count,

        COUNT(*) FILTER (
            WHERE risk_rating = 'Critical'
        ) AS critical_cases,

        COUNT(*) FILTER (
            WHERE risk_rating = 'High'
        ) AS high_risk_cases

    FROM core.cases

    GROUP BY customer_id
),


sar_features AS (

    SELECT
        customer_id,

        COUNT(*) AS sar_count,

        COUNT(*) FILTER (
            WHERE sar_status = 'Filed'
        ) AS filed_sar_count

    FROM core.sar_reports

    GROUP BY customer_id
)


SELECT
    c.customer_id,

    /* ---------- KYC ---------- */

    c.customer_since,
    c.state,
    c.occupation,
    c.income_band,
    c.kyc_risk_rating,
    c.politically_exposed_person_flag,
    c.customer_segment,

    /* ---------- Accounts ---------- */

    COALESCE(ac.account_count, 0)
        AS account_count,

    COALESCE(ac.active_account_count, 0)
        AS active_account_count,

    COALESCE(ac.total_current_balance, 0)
        AS total_current_balance,

    /* ---------- Transactions ---------- */

    COALESCE(tf.transaction_count, 0)
        AS transaction_count,

    COALESCE(tf.transaction_volume, 0)
        AS transaction_volume,

    COALESCE(tf.avg_transaction_amount, 0)
        AS avg_transaction_amount,

    COALESCE(tf.max_transaction_amount, 0)
        AS max_transaction_amount,

    COALESCE(tf.suspicious_transaction_count, 0)
        AS suspicious_transaction_count,

    COALESCE(tf.suspicious_transaction_volume, 0)
        AS suspicious_transaction_volume,

    COALESCE(tf.cross_border_transaction_count, 0)
        AS cross_border_transaction_count,

    COALESCE(tf.cross_border_volume, 0)
        AS cross_border_volume,

    COALESCE(tf.wire_transfer_count, 0)
        AS wire_transfer_count,

    COALESCE(tf.wire_transfer_volume, 0)
        AS wire_transfer_volume,

    COALESCE(tf.high_risk_merchant_transactions, 0)
        AS high_risk_merchant_transactions,

    COALESCE(
        tf.distinct_beneficiaries,
        0
    ) AS transacted_beneficiaries,

    COALESCE(tf.transaction_devices, 0)
        AS transaction_devices,

    COALESCE(tf.transaction_ips, 0)
        AS transaction_ips,

    /* ---------- Beneficiaries ---------- */

    COALESCE(
        bf.registered_beneficiary_count,
        0
    ) AS registered_beneficiary_count,

    COALESCE(
        bf.foreign_beneficiary_countries,
        0
    ) AS foreign_beneficiary_countries,

    /* ---------- Digital ---------- */

    COALESCE(df.login_count, 0)
        AS login_count,

    COALESCE(df.failed_login_count, 0)
        AS failed_login_count,

    COALESCE(
        df.successful_non_mfa_logins,
        0
    ) AS successful_non_mfa_logins,

    COALESCE(df.high_risk_ip_logins, 0)
        AS high_risk_ip_logins,

    COALESCE(df.login_devices, 0)
        AS login_devices,

    COALESCE(df.login_ips, 0)
        AS login_ips,

    COALESCE(
        rd.registered_device_count,
        0
    ) AS registered_device_count,

    /* ---------- FinCrime ---------- */

    COALESCE(af.alert_count, 0)
        AS alert_count,

    COALESCE(af.distinct_tm_rules, 0)
        AS distinct_tm_rules,

    COALESCE(af.avg_alert_score, 0)
        AS avg_alert_score,

    COALESCE(af.max_alert_score, 0)
        AS max_alert_score,

    COALESCE(af.high_priority_alerts, 0)
        AS high_priority_alerts,

    COALESCE(af.medium_priority_alerts, 0)
        AS medium_priority_alerts,

    COALESCE(cf.case_count, 0)
        AS case_count,

    COALESCE(cf.critical_cases, 0)
        AS critical_cases,

    COALESCE(cf.high_risk_cases, 0)
        AS high_risk_cases,

    COALESCE(sf.sar_count, 0)
        AS sar_count,

    COALESCE(sf.filed_sar_count, 0)
        AS filed_sar_count

FROM core.customers c

LEFT JOIN transaction_features tf
    ON c.customer_id = tf.customer_id

LEFT JOIN digital_features df
    ON c.customer_id = df.customer_id

LEFT JOIN registered_devices rd
    ON c.customer_id = rd.customer_id

LEFT JOIN beneficiary_features bf
    ON c.customer_id = bf.customer_id

LEFT JOIN account_features ac
    ON c.customer_id = ac.customer_id

LEFT JOIN alert_features af
    ON c.customer_id = af.customer_id

LEFT JOIN case_features cf
    ON c.customer_id = cf.customer_id

LEFT JOIN sar_features sf
    ON c.customer_id = sf.customer_id;


/* Primary key for downstream analytics */

ALTER TABLE analytics.customer_risk_features
ADD PRIMARY KEY (customer_id);


/* ============================================================
   51–52. COMPONENT + COMPOSITE RISK SCORING

   Scores are deliberately capped by component.

   KYC          25
   Transaction  30
   Digital      15
   FinCrime     30
                ---
                100
   ============================================================ */

CREATE TABLE analytics.customer_risk_score AS

WITH scored AS (

    SELECT
        f.*,


        /* ====================================================
           KYC RISK — MAX 25
           ==================================================== */

        LEAST(
            25,

            CASE f.kyc_risk_rating
                WHEN 'High' THEN 18
                WHEN 'Medium' THEN 9
                WHEN 'Low' THEN 2
                ELSE 0
            END

            +

            CASE
                WHEN f.politically_exposed_person_flag = TRUE
                    THEN 7
                ELSE 0
            END

        )::NUMERIC AS kyc_risk_score,


        /* ====================================================
           TRANSACTION RISK — MAX 30

           Suspicious activity receives the strongest weight.
           Cross-border, wires and high-risk merchants add
           secondary behavioral risk signals.
           ==================================================== */

        LEAST(
            30,

            CASE
                WHEN f.suspicious_transaction_count >= 5 THEN 12
                WHEN f.suspicious_transaction_count >= 3 THEN 9
                WHEN f.suspicious_transaction_count >= 1 THEN 5
                ELSE 0
            END

            +

            CASE
                WHEN f.cross_border_transaction_count >= 5 THEN 6
                WHEN f.cross_border_transaction_count >= 2 THEN 4
                WHEN f.cross_border_transaction_count >= 1 THEN 2
                ELSE 0
            END

            +

            CASE
                WHEN f.wire_transfer_volume >= 100000 THEN 5
                WHEN f.wire_transfer_volume >= 50000 THEN 3
                WHEN f.wire_transfer_volume > 0 THEN 1
                ELSE 0
            END

            +

            CASE
                WHEN f.high_risk_merchant_transactions >= 5 THEN 4
                WHEN f.high_risk_merchant_transactions >= 2 THEN 3
                WHEN f.high_risk_merchant_transactions >= 1 THEN 1
                ELSE 0
            END

            +

            CASE
                WHEN f.foreign_beneficiary_countries >= 3 THEN 3
                WHEN f.foreign_beneficiary_countries >= 1 THEN 1
                ELSE 0
            END

        )::NUMERIC AS transaction_risk_score,


        /* ====================================================
           DIGITAL RISK — MAX 15
           ==================================================== */

        LEAST(
            15,

            CASE
                WHEN f.failed_login_count >= 5 THEN 4
                WHEN f.failed_login_count >= 2 THEN 2
                WHEN f.failed_login_count >= 1 THEN 1
                ELSE 0
            END

            +

            CASE
                WHEN f.high_risk_ip_logins >= 5 THEN 6
                WHEN f.high_risk_ip_logins >= 2 THEN 4
                WHEN f.high_risk_ip_logins >= 1 THEN 2
                ELSE 0
            END

            +

            CASE
                WHEN f.successful_non_mfa_logins >= 10 THEN 3
                WHEN f.successful_non_mfa_logins >= 3 THEN 2
                WHEN f.successful_non_mfa_logins >= 1 THEN 1
                ELSE 0
            END

            +

            CASE
                WHEN f.login_devices >= 5 THEN 2
                WHEN f.login_devices >= 3 THEN 1
                ELSE 0
            END

        )::NUMERIC AS digital_risk_score,


        /* ====================================================
           FINCRIME RISK — MAX 30
           ==================================================== */

        LEAST(
            30,

            CASE
                WHEN f.alert_count >= 10 THEN 6
                WHEN f.alert_count >= 5 THEN 4
                WHEN f.alert_count >= 1 THEN 2
                ELSE 0
            END

            +

            CASE
                WHEN f.distinct_tm_rules >= 4 THEN 4
                WHEN f.distinct_tm_rules >= 2 THEN 2
                WHEN f.distinct_tm_rules >= 1 THEN 1
                ELSE 0
            END

            +

            CASE
                WHEN f.high_priority_alerts >= 3 THEN 4
                WHEN f.high_priority_alerts >= 1 THEN 2
                ELSE 0
            END

            +

            CASE
                WHEN f.critical_cases >= 1 THEN 6
                WHEN f.high_risk_cases >= 1 THEN 4
                WHEN f.case_count >= 1 THEN 2
                ELSE 0
            END

            +

            CASE
                WHEN f.sar_count >= 2 THEN 10
                WHEN f.sar_count = 1 THEN 8
                ELSE 0
            END

        )::NUMERIC AS fincrime_risk_score

    FROM analytics.customer_risk_features f
),


composite AS (

    SELECT
        s.*,

        (
            s.kyc_risk_score
            + s.transaction_risk_score
            + s.digital_risk_score
            + s.fincrime_risk_score
        )::NUMERIC AS customer_risk_score

    FROM scored s
)


SELECT
    c.*,

    CASE
        WHEN c.customer_risk_score >= 75
            THEN 'Critical'

        WHEN c.customer_risk_score >= 55
            THEN 'High'

        WHEN c.customer_risk_score >= 30
            THEN 'Medium'

        ELSE 'Low'
    END AS customer_risk_tier,


    /* ========================================================
       Explainability / reason flags
       ======================================================== */

    CONCAT_WS(
        '; ',

        CASE
            WHEN c.kyc_risk_rating = 'High'
                THEN 'High KYC risk'
        END,

        CASE
            WHEN c.politically_exposed_person_flag = TRUE
                THEN 'PEP'
        END,

        CASE
            WHEN c.suspicious_transaction_count > 0
                THEN 'Suspicious transactions'
        END,

        CASE
            WHEN c.cross_border_transaction_count > 0
                THEN 'Cross-border activity'
        END,

        CASE
            WHEN c.high_risk_merchant_transactions > 0
                THEN 'High-risk merchant exposure'
        END,

        CASE
            WHEN c.high_risk_ip_logins > 0
                THEN 'High-risk IP activity'
        END,

        CASE
            WHEN c.failed_login_count >= 2
                THEN 'Repeated failed logins'
        END,

        CASE
            WHEN c.high_priority_alerts > 0
                THEN 'High-priority TM alerts'
        END,

        CASE
            WHEN c.critical_cases > 0
                THEN 'Critical FinCrime case'
        END,

        CASE
            WHEN c.high_risk_cases > 0
                THEN 'High-risk FinCrime case'
        END,

        CASE
            WHEN c.sar_count > 0
                THEN 'SAR history'
        END

    ) AS risk_reasons

FROM composite c;


ALTER TABLE analytics.customer_risk_score
ADD PRIMARY KEY (customer_id);


/* ============================================================
   53. RISK TIER DISTRIBUTION
   ============================================================ */

SELECT
    customer_risk_tier,

    COUNT(*) AS customers,

    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS customer_pct,

    ROUND(
        AVG(customer_risk_score),
        2
    ) AS avg_risk_score,

    ROUND(
        AVG(kyc_risk_score),
        2
    ) AS avg_kyc_score,

    ROUND(
        AVG(transaction_risk_score),
        2
    ) AS avg_transaction_score,

    ROUND(
        AVG(digital_risk_score),
        2
    ) AS avg_digital_score,

    ROUND(
        AVG(fincrime_risk_score),
        2
    ) AS avg_fincrime_score,

    SUM(alert_count)
        AS alerts,

    SUM(case_count)
        AS cases,

    SUM(sar_count)
        AS sars

FROM analytics.customer_risk_score

GROUP BY customer_risk_tier

ORDER BY
    CASE customer_risk_tier
        WHEN 'Critical' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Medium' THEN 3
        WHEN 'Low' THEN 4
    END;


/* ============================================================
   54. TOP-RISK CUSTOMERS
   ============================================================ */

SELECT
    customer_id,
    customer_risk_score,
    customer_risk_tier,

    kyc_risk_score,
    transaction_risk_score,
    digital_risk_score,
    fincrime_risk_score,

    kyc_risk_rating,
    politically_exposed_person_flag,

    transaction_count,
    suspicious_transaction_count,
    cross_border_transaction_count,
    high_risk_merchant_transactions,

    failed_login_count,
    high_risk_ip_logins,

    alert_count,
    distinct_tm_rules,
    high_priority_alerts,

    case_count,
    critical_cases,
    high_risk_cases,
    sar_count,

    risk_reasons

FROM analytics.customer_risk_score

ORDER BY
    customer_risk_score DESC,
    sar_count DESC,
    case_count DESC,
    alert_count DESC

LIMIT 25;


/* ============================================================
   55A. RISK DRIVER PREVALENCE
   ============================================================ */

SELECT
    COUNT(*) AS customers,

    COUNT(*) FILTER (
        WHERE kyc_risk_rating = 'High'
    ) AS high_kyc_customers,

    COUNT(*) FILTER (
        WHERE politically_exposed_person_flag = TRUE
    ) AS pep_customers,

    COUNT(*) FILTER (
        WHERE suspicious_transaction_count > 0
    ) AS customers_with_suspicious_transactions,

    COUNT(*) FILTER (
        WHERE cross_border_transaction_count > 0
    ) AS customers_with_cross_border_activity,

    COUNT(*) FILTER (
        WHERE high_risk_merchant_transactions > 0
    ) AS customers_with_high_risk_merchants,

    COUNT(*) FILTER (
        WHERE high_risk_ip_logins > 0
    ) AS customers_with_high_risk_ip_activity,

    COUNT(*) FILTER (
        WHERE alert_count > 0
    ) AS alerted_customers,

    COUNT(*) FILTER (
        WHERE case_count > 0
    ) AS customers_with_cases,

    COUNT(*) FILTER (
        WHERE sar_count > 0
    ) AS customers_with_sars

FROM analytics.customer_risk_score;


/* ============================================================
   55B. SCORE DISTRIBUTION
   ============================================================ */

SELECT
    FLOOR(customer_risk_score / 10) * 10
        AS score_band_start,

    COUNT(*) AS customers,

    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS customer_pct

FROM analytics.customer_risk_score

GROUP BY FLOOR(customer_risk_score / 10)

ORDER BY score_band_start;


/* ============================================================
   VALIDATION SUITE
   ============================================================ */


/* V1 — Every customer receives one feature record */

SELECT
    'Customer feature coverage' AS validation,

    CASE
        WHEN COUNT(*) = 10000
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS observed

FROM analytics.customer_risk_features;


/* V2 — Every customer receives one risk score */

SELECT
    'Customer score coverage' AS validation,

    CASE
        WHEN COUNT(*) = 10000
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS observed

FROM analytics.customer_risk_score;


/* V3 — Customer IDs unique */

SELECT
    'Unique customer risk records' AS validation,

    CASE
        WHEN COUNT(*) =
             COUNT(DISTINCT customer_id)
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS total_records,

    COUNT(DISTINCT customer_id)
        AS unique_customers

FROM analytics.customer_risk_score;


/* V4 — Score must remain between 0 and 100 */

SELECT
    'Composite score range' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count,

    MIN(customer_risk_score)
        AS min_score,

    MAX(customer_risk_score)
        AS max_score

FROM analytics.customer_risk_score

WHERE customer_risk_score < 0
   OR customer_risk_score > 100;


/* V5 — KYC component */

SELECT
    'KYC score range' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.customer_risk_score

WHERE kyc_risk_score < 0
   OR kyc_risk_score > 25;


/* V6 — Transaction component */

SELECT
    'Transaction score range' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.customer_risk_score

WHERE transaction_risk_score < 0
   OR transaction_risk_score > 30;


/* V7 — Digital component */

SELECT
    'Digital score range' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.customer_risk_score

WHERE digital_risk_score < 0
   OR digital_risk_score > 15;


/* V8 — FinCrime component */

SELECT
    'FinCrime score range' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.customer_risk_score

WHERE fincrime_risk_score < 0
   OR fincrime_risk_score > 30;


/* V9 — Composite arithmetic */

SELECT
    'Composite score arithmetic' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.customer_risk_score

WHERE customer_risk_score <>
      (
          kyc_risk_score
          + transaction_risk_score
          + digital_risk_score
          + fincrime_risk_score
      );


/* V10 — Risk tier present */

SELECT
    'Risk tier completeness' AS validation,

    CASE
        WHEN COUNT(*) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.customer_risk_score

WHERE customer_risk_tier IS NULL;


/* V11 — Transaction reconciliation */

SELECT
    'Transaction feature reconciliation'
        AS validation,

    CASE
        WHEN SUM(transaction_count) = 500000
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    SUM(transaction_count)
        AS observed_transactions

FROM analytics.customer_risk_score;


/* V12 — Alert reconciliation */

SELECT
    'Alert feature reconciliation'
        AS validation,

    CASE
        WHEN SUM(alert_count) = 53392
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    SUM(alert_count) AS observed_alerts

FROM analytics.customer_risk_score;


/* V13 — Case reconciliation */

SELECT
    'Case feature reconciliation'
        AS validation,

    CASE
        WHEN SUM(case_count) = 18597
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    SUM(case_count) AS observed_cases

FROM analytics.customer_risk_score;


/* V14 — SAR reconciliation */

SELECT
    'SAR feature reconciliation'
        AS validation,

    CASE
        WHEN SUM(sar_count) = 11103
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    SUM(sar_count) AS observed_sars

FROM analytics.customer_risk_score;


/* V15 — Suspicious transaction reconciliation */

SELECT
    'Suspicious transaction reconciliation'
        AS validation,

    CASE
        WHEN SUM(suspicious_transaction_count) = 8500
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    SUM(suspicious_transaction_count)
        AS observed_suspicious_transactions

FROM analytics.customer_risk_score;


/* ============================================================
   FINAL CUSTOMER RISK SCORECARD
   ============================================================ */

SELECT
    COUNT(*) AS customers,

    ROUND(
        AVG(customer_risk_score),
        2
    ) AS avg_customer_risk_score,

    MIN(customer_risk_score)
        AS min_customer_risk_score,

    MAX(customer_risk_score)
        AS max_customer_risk_score,

    COUNT(*) FILTER (
        WHERE customer_risk_tier = 'Critical'
    ) AS critical_customers,

    COUNT(*) FILTER (
        WHERE customer_risk_tier = 'High'
    ) AS high_risk_customers,

    COUNT(*) FILTER (
        WHERE customer_risk_tier = 'Medium'
    ) AS medium_risk_customers,

    COUNT(*) FILTER (
        WHERE customer_risk_tier = 'Low'
    ) AS low_risk_customers,

    COUNT(*) FILTER (
        WHERE sar_count > 0
    ) AS customers_with_sars,

    COUNT(*) FILTER (
        WHERE suspicious_transaction_count > 0
    ) AS customers_with_suspicious_transactions

FROM analytics.customer_risk_score;
