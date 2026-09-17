/* ============================================================
   ENTITY RESOLUTION + NETWORK ANALYTICS
   Analyses 56–65
   ============================================================ */

DROP TABLE IF EXISTS analytics.entity_relationships;
DROP TABLE IF EXISTS analytics.customer_network_metrics;


/* ============================================================
   56. SHARED DEVICE RELATIONSHIPS

   A relationship exists when two different customers have
   activity associated with the same device.

   We derive this from login_events because it captures actual
   observed customer/device usage.
   ============================================================ */

CREATE TEMP TABLE tmp_shared_devices AS

SELECT
    l1.customer_id AS customer_1,
    l2.customer_id AS customer_2,

    COUNT(DISTINCT l1.device_id)
        AS shared_device_count

FROM core.login_events l1

JOIN core.login_events l2
    ON l1.device_id = l2.device_id
   AND l1.customer_id < l2.customer_id

WHERE l1.device_id IS NOT NULL

GROUP BY
    l1.customer_id,
    l2.customer_id;


/* ============================================================
   57. SHARED IP RELATIONSHIPS
   ============================================================ */

CREATE TEMP TABLE tmp_shared_ips AS

SELECT
    l1.customer_id AS customer_1,
    l2.customer_id AS customer_2,

    COUNT(DISTINCT l1.ip_id)
        AS shared_ip_count,

    COUNT(DISTINCT l1.ip_id) FILTER (
        WHERE ip.risk_rating = 'High'
    ) AS shared_high_risk_ip_count

FROM core.login_events l1

JOIN core.login_events l2
    ON l1.ip_id = l2.ip_id
   AND l1.customer_id < l2.customer_id

LEFT JOIN core.ip_addresses ip
    ON l1.ip_id = ip.ip_id

WHERE l1.ip_id IS NOT NULL

GROUP BY
    l1.customer_id,
    l2.customer_id;


/* ============================================================
   58. SHARED BENEFICIARY RELATIONSHIPS

   Multiple customers transacting with the same beneficiary
   can be useful for detecting common counterparties.
   ============================================================ */

CREATE TEMP TABLE tmp_shared_beneficiaries AS

SELECT
    t1.customer_id AS customer_1,
    t2.customer_id AS customer_2,

    COUNT(DISTINCT t1.beneficiary_id)
        AS shared_beneficiary_count

FROM core.transactions t1

JOIN core.transactions t2
    ON t1.beneficiary_id = t2.beneficiary_id
   AND t1.customer_id < t2.customer_id

WHERE t1.beneficiary_id IS NOT NULL

GROUP BY
    t1.customer_id,
    t2.customer_id;


/* ============================================================
   59. CONSOLIDATED ENTITY RELATIONSHIP TABLE
   ============================================================ */

CREATE TABLE analytics.entity_relationships AS

WITH relationship_pairs AS (

    SELECT customer_1, customer_2
    FROM tmp_shared_devices

    UNION

    SELECT customer_1, customer_2
    FROM tmp_shared_ips

    UNION

    SELECT customer_1, customer_2
    FROM tmp_shared_beneficiaries
)

SELECT
    rp.customer_1,
    rp.customer_2,

    COALESCE(sd.shared_device_count, 0)
        AS shared_device_count,

    COALESCE(si.shared_ip_count, 0)
        AS shared_ip_count,

    COALESCE(si.shared_high_risk_ip_count, 0)
        AS shared_high_risk_ip_count,

    COALESCE(sb.shared_beneficiary_count, 0)
        AS shared_beneficiary_count,

    (
        COALESCE(sd.shared_device_count, 0) * 5
        +
        COALESCE(si.shared_ip_count, 0) * 2
        +
        COALESCE(si.shared_high_risk_ip_count, 0) * 5
        +
        COALESCE(sb.shared_beneficiary_count, 0) * 4
    ) AS relationship_strength_score,

    r1.customer_risk_score
        AS customer_1_risk_score,

    r1.customer_risk_tier
        AS customer_1_risk_tier,

    r2.customer_risk_score
        AS customer_2_risk_score,

    r2.customer_risk_tier
        AS customer_2_risk_tier

FROM relationship_pairs rp

LEFT JOIN tmp_shared_devices sd
    ON rp.customer_1 = sd.customer_1
   AND rp.customer_2 = sd.customer_2

LEFT JOIN tmp_shared_ips si
    ON rp.customer_1 = si.customer_1
   AND rp.customer_2 = si.customer_2

LEFT JOIN tmp_shared_beneficiaries sb
    ON rp.customer_1 = sb.customer_1
   AND rp.customer_2 = sb.customer_2

JOIN analytics.customer_risk_score r1
    ON rp.customer_1 = r1.customer_id

JOIN analytics.customer_risk_score r2
    ON rp.customer_2 = r2.customer_id;


CREATE UNIQUE INDEX
    idx_entity_relationship_pair
ON analytics.entity_relationships (
    customer_1,
    customer_2
);


/* ============================================================
   60. RELATIONSHIP TYPE DISTRIBUTION
   ============================================================ */

SELECT
    CASE
        WHEN shared_device_count > 0
         AND shared_ip_count > 0
         AND shared_beneficiary_count > 0
            THEN 'Device + IP + Beneficiary'

        WHEN shared_device_count > 0
         AND shared_ip_count > 0
            THEN 'Device + IP'

        WHEN shared_device_count > 0
         AND shared_beneficiary_count > 0
            THEN 'Device + Beneficiary'

        WHEN shared_ip_count > 0
         AND shared_beneficiary_count > 0
            THEN 'IP + Beneficiary'

        WHEN shared_device_count > 0
            THEN 'Device Only'

        WHEN shared_ip_count > 0
            THEN 'IP Only'

        WHEN shared_beneficiary_count > 0
            THEN 'Beneficiary Only'

        ELSE 'Unknown'
    END AS relationship_type,

    COUNT(*) AS relationship_pairs

FROM analytics.entity_relationships

GROUP BY relationship_type

ORDER BY relationship_pairs DESC;


/* ============================================================
   61. STRONGEST ENTITY RELATIONSHIPS
   ============================================================ */

SELECT
    customer_1,
    customer_2,

    shared_device_count,
    shared_ip_count,
    shared_high_risk_ip_count,
    shared_beneficiary_count,

    relationship_strength_score,

    customer_1_risk_score,
    customer_1_risk_tier,

    customer_2_risk_score,
    customer_2_risk_tier

FROM analytics.entity_relationships

ORDER BY
    relationship_strength_score DESC,
    shared_high_risk_ip_count DESC

LIMIT 25;


/* ============================================================
   62. CUSTOMER NETWORK METRICS

   Degree = number of distinct connected customers.

   This produces a customer-level network feature table that can
   later feed Power BI and graph/network visualization.
   ============================================================ */

CREATE TABLE analytics.customer_network_metrics AS

WITH undirected_edges AS (

    SELECT
        customer_1 AS customer_id,
        customer_2 AS connected_customer,
        relationship_strength_score,
        shared_device_count,
        shared_ip_count,
        shared_high_risk_ip_count,
        shared_beneficiary_count

    FROM analytics.entity_relationships

    UNION ALL

    SELECT
        customer_2,
        customer_1,
        relationship_strength_score,
        shared_device_count,
        shared_ip_count,
        shared_high_risk_ip_count,
        shared_beneficiary_count

    FROM analytics.entity_relationships
),

network AS (

    SELECT
        customer_id,

        COUNT(DISTINCT connected_customer)
            AS network_degree,

        SUM(relationship_strength_score)
            AS total_relationship_strength,

        MAX(relationship_strength_score)
            AS strongest_relationship_score,

        COUNT(DISTINCT connected_customer) FILTER (
            WHERE shared_device_count > 0
        ) AS device_connected_customers,

        COUNT(DISTINCT connected_customer) FILTER (
            WHERE shared_ip_count > 0
        ) AS ip_connected_customers,

        COUNT(DISTINCT connected_customer) FILTER (
            WHERE shared_high_risk_ip_count > 0
        ) AS high_risk_ip_connected_customers,

        COUNT(DISTINCT connected_customer) FILTER (
            WHERE shared_beneficiary_count > 0
        ) AS beneficiary_connected_customers

    FROM undirected_edges

    GROUP BY customer_id
)

SELECT
    r.customer_id,

    r.customer_risk_score,
    r.customer_risk_tier,

    COALESCE(n.network_degree, 0)
        AS network_degree,

    COALESCE(n.total_relationship_strength, 0)
        AS total_relationship_strength,

    COALESCE(n.strongest_relationship_score, 0)
        AS strongest_relationship_score,

    COALESCE(n.device_connected_customers, 0)
        AS device_connected_customers,

    COALESCE(n.ip_connected_customers, 0)
        AS ip_connected_customers,

    COALESCE(
        n.high_risk_ip_connected_customers,
        0
    ) AS high_risk_ip_connected_customers,

    COALESCE(
        n.beneficiary_connected_customers,
        0
    ) AS beneficiary_connected_customers

FROM analytics.customer_risk_score r

LEFT JOIN network n
    ON r.customer_id = n.customer_id;


ALTER TABLE analytics.customer_network_metrics
ADD PRIMARY KEY (customer_id);


/* ============================================================
   63. HIGHLY CONNECTED CUSTOMERS
   ============================================================ */

SELECT
    customer_id,
    customer_risk_score,
    customer_risk_tier,

    network_degree,
    total_relationship_strength,
    strongest_relationship_score,

    device_connected_customers,
    ip_connected_customers,
    high_risk_ip_connected_customers,
    beneficiary_connected_customers

FROM analytics.customer_network_metrics

ORDER BY
    network_degree DESC,
    total_relationship_strength DESC

LIMIT 25;


/* ============================================================
   64. HIGH-RISK NETWORK CONNECTIONS

   Identifies customers connected to High/Critical customers.
   ============================================================ */

WITH undirected AS (

    SELECT customer_1, customer_2
    FROM analytics.entity_relationships

    UNION ALL

    SELECT customer_2, customer_1
    FROM analytics.entity_relationships
)

SELECT
    u.customer_1 AS customer_id,

    r.customer_risk_score,
    r.customer_risk_tier,

    COUNT(DISTINCT u.customer_2)
        AS connected_customers,

    COUNT(DISTINCT u.customer_2) FILTER (
        WHERE cr.customer_risk_tier
              IN ('High', 'Critical')
    ) AS high_risk_connections,

    ROUND(
        AVG(cr.customer_risk_score),
        2
    ) AS avg_connected_customer_risk_score,

    MAX(cr.customer_risk_score)
        AS max_connected_customer_risk_score

FROM undirected u

JOIN analytics.customer_risk_score r
    ON u.customer_1 = r.customer_id

JOIN analytics.customer_risk_score cr
    ON u.customer_2 = cr.customer_id

GROUP BY
    u.customer_1,
    r.customer_risk_score,
    r.customer_risk_tier

HAVING COUNT(DISTINCT u.customer_2) FILTER (
    WHERE cr.customer_risk_tier
          IN ('High', 'Critical')
) > 0

ORDER BY
    high_risk_connections DESC,
    avg_connected_customer_risk_score DESC

LIMIT 25;


/* ============================================================
   65. NETWORK-ENHANCED CUSTOMER RISK

   IMPORTANT:
   We do NOT overwrite customer_risk_score.

   This is an analytical overlay showing how network context can
   complement the primary customer risk engine.
   ============================================================ */

SELECT
    n.customer_id,

    n.customer_risk_score
        AS base_risk_score,

    n.customer_risk_tier
        AS base_risk_tier,

    n.network_degree,

    n.high_risk_ip_connected_customers,

    COALESCE(hr.high_risk_connections, 0)
        AS high_risk_customer_connections,

    LEAST(
        15,

        CASE
            WHEN n.network_degree >= 20 THEN 5
            WHEN n.network_degree >= 10 THEN 3
            WHEN n.network_degree >= 3 THEN 1
            ELSE 0
        END

        +

        CASE
            WHEN n.high_risk_ip_connected_customers >= 3
                THEN 5
            WHEN n.high_risk_ip_connected_customers >= 1
                THEN 3
            ELSE 0
        END

        +

        CASE
            WHEN COALESCE(
                hr.high_risk_connections,
                0
            ) >= 3 THEN 5

            WHEN COALESCE(
                hr.high_risk_connections,
                0
            ) >= 1 THEN 3

            ELSE 0
        END

    ) AS network_risk_overlay

FROM analytics.customer_network_metrics n

LEFT JOIN (

    SELECT
        u.customer_1 AS customer_id,

        COUNT(DISTINCT u.customer_2) FILTER (
            WHERE r.customer_risk_tier
                  IN ('High', 'Critical')
        ) AS high_risk_connections

    FROM (

        SELECT customer_1, customer_2
        FROM analytics.entity_relationships

        UNION ALL

        SELECT customer_2, customer_1
        FROM analytics.entity_relationships

    ) u

    JOIN analytics.customer_risk_score r
        ON u.customer_2 = r.customer_id

    GROUP BY u.customer_1

) hr
    ON n.customer_id = hr.customer_id

ORDER BY
    network_risk_overlay DESC,
    n.customer_risk_score DESC

LIMIT 50;


/* ============================================================
   VALIDATION SUITE
   ============================================================ */


/* V1 — No self relationships */

SELECT
    'No self relationships' AS validation,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.entity_relationships

WHERE customer_1 = customer_2;


/* V2 — Unique relationship pairs */

SELECT
    'Unique relationship pairs' AS validation,

    CASE
        WHEN COUNT(*) =
             COUNT(
                 DISTINCT
                 (customer_1, customer_2)
             )
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS total_relationships,

    COUNT(
        DISTINCT
        (customer_1, customer_2)
    ) AS unique_relationships

FROM analytics.entity_relationships;


/* V3 — Canonical pair ordering */

SELECT
    'Canonical relationship ordering'
        AS validation,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.entity_relationships

WHERE customer_1 >= customer_2;


/* V4 — Every relationship has evidence */

SELECT
    'Relationship evidence'
        AS validation,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.entity_relationships

WHERE shared_device_count = 0
  AND shared_ip_count = 0
  AND shared_beneficiary_count = 0;


/* V5 — Relationship score positive */

SELECT
    'Relationship strength'
        AS validation,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.entity_relationships

WHERE relationship_strength_score <= 0;


/* V6 — Valid customer 1 */

SELECT
    'Valid customer 1'
        AS validation,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.entity_relationships e

LEFT JOIN core.customers c
    ON e.customer_1 = c.customer_id

WHERE c.customer_id IS NULL;


/* V7 — Valid customer 2 */

SELECT
    'Valid customer 2'
        AS validation,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.entity_relationships e

LEFT JOIN core.customers c
    ON e.customer_2 = c.customer_id

WHERE c.customer_id IS NULL;


/* V8 — Network metrics cover all customers */

SELECT
    'Network customer coverage'
        AS validation,

    CASE
        WHEN COUNT(*) = 10000 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS observed_customers

FROM analytics.customer_network_metrics;


/* V9 — Network degree cannot be negative */

SELECT
    'Network degree range'
        AS validation,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS invalid_count

FROM analytics.customer_network_metrics

WHERE network_degree < 0;


/* V10 — Connected customer count */

SELECT
    'Customers with network connections'
        AS validation,

    CASE
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    COUNT(*) AS connected_customers

FROM analytics.customer_network_metrics

WHERE network_degree > 0;


/* ============================================================
   FINAL ENTITY / NETWORK SCORECARD
   ============================================================ */

SELECT
    (SELECT COUNT(*)
     FROM analytics.entity_relationships)
        AS relationship_pairs,

    (SELECT COUNT(*)
     FROM analytics.customer_network_metrics
     WHERE network_degree > 0)
        AS connected_customers,

    (SELECT ROUND(AVG(network_degree), 2)
     FROM analytics.customer_network_metrics
     WHERE network_degree > 0)
        AS avg_degree_connected_customers,

    (SELECT MAX(network_degree)
     FROM analytics.customer_network_metrics)
        AS max_network_degree,

    (SELECT COUNT(*)
     FROM analytics.entity_relationships
     WHERE shared_device_count > 0)
        AS shared_device_relationships,

    (SELECT COUNT(*)
     FROM analytics.entity_relationships
     WHERE shared_ip_count > 0)
        AS shared_ip_relationships,

    (SELECT COUNT(*)
     FROM analytics.entity_relationships
     WHERE shared_beneficiary_count > 0)
        AS shared_beneficiary_relationships,

    (SELECT COUNT(*)
     FROM analytics.entity_relationships
     WHERE shared_high_risk_ip_count > 0)
        AS high_risk_ip_relationships;
