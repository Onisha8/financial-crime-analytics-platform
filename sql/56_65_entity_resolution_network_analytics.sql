/* ============================================================
   ENTITY RESOLUTION + NETWORK ANALYTICS — V2
   Analyses 56–65

   Key correction:
   Shared IP is considered entity-linkage evidence only when
   the IP is observed across <= 5 distinct customers.

   Common IPs remain useful risk indicators, but are NOT treated
   as evidence that customers are related.

   Synthetic portfolio methodology — not a production bank model.
   ============================================================ */

DROP TABLE IF EXISTS analytics.entity_relationships;
DROP TABLE IF EXISTS analytics.customer_network_metrics;

DROP TABLE IF EXISTS tmp_ip_frequency;
DROP TABLE IF EXISTS tmp_shared_ips;


/* ============================================================
   56. IP PREVALENCE
   ============================================================ */

CREATE TEMP TABLE tmp_ip_frequency AS
SELECT
    le.ip_id,
    COUNT(DISTINCT le.customer_id) AS customer_count
FROM core.login_events le
WHERE le.ip_id IS NOT NULL
GROUP BY le.ip_id;


/* ============================================================
   57. RARE SHARED-IP RELATIONSHIPS

   <= 5 customers per IP = ER candidate.
   > 5 customers = suppressed as common infrastructure.
   ============================================================ */

CREATE TEMP TABLE tmp_shared_ips AS
SELECT
    a.customer_id AS customer_1,
    b.customer_id AS customer_2,

    COUNT(DISTINCT a.ip_id) AS shared_rare_ip_count,

    COUNT(DISTINCT a.ip_id) FILTER (
        WHERE ip.risk_rating = 'High'
    ) AS shared_high_risk_rare_ip_count,

    MIN(f.customer_count) AS rarest_shared_ip_prevalence

FROM (
    SELECT DISTINCT customer_id, ip_id
    FROM core.login_events
    WHERE ip_id IS NOT NULL
) a

JOIN (
    SELECT DISTINCT customer_id, ip_id
    FROM core.login_events
    WHERE ip_id IS NOT NULL
) b
    ON a.ip_id = b.ip_id
   AND a.customer_id < b.customer_id

JOIN tmp_ip_frequency f
    ON a.ip_id = f.ip_id

LEFT JOIN core.ip_addresses ip
    ON a.ip_id = ip.ip_id

WHERE f.customer_count BETWEEN 2 AND 5

GROUP BY
    a.customer_id,
    b.customer_id;


/* ============================================================
   58. CONSOLIDATED ENTITY RELATIONSHIPS

   Relationship strength:
   rare shared IP             = 4 points each
   rare + high-risk shared IP = additional 3 points each

   High-risk status strengthens an existing rare-IP relationship;
   it does not create an entity relationship by itself.
   ============================================================ */

CREATE TABLE analytics.entity_relationships AS
SELECT
    s.customer_1,
    s.customer_2,

    s.shared_rare_ip_count,
    s.shared_high_risk_rare_ip_count,
    s.rarest_shared_ip_prevalence,

    (
        s.shared_rare_ip_count * 4
        +
        s.shared_high_risk_rare_ip_count * 3
    ) AS relationship_strength_score,

    r1.customer_risk_score AS customer_1_risk_score,
    r1.customer_risk_tier AS customer_1_risk_tier,

    r2.customer_risk_score AS customer_2_risk_score,
    r2.customer_risk_tier AS customer_2_risk_tier

FROM tmp_shared_ips s

JOIN analytics.customer_risk_score r1
    ON s.customer_1 = r1.customer_id

JOIN analytics.customer_risk_score r2
    ON s.customer_2 = r2.customer_id;


CREATE UNIQUE INDEX idx_entity_relationship_pair
ON analytics.entity_relationships (
    customer_1,
    customer_2
);


/* ============================================================
   59. ENTITY RESOLUTION SUMMARY
   ============================================================ */

SELECT
    COUNT(*) AS relationship_pairs,

    COUNT(DISTINCT customer_1)
        AS customers_as_customer_1,

    COUNT(DISTINCT customer_2)
        AS customers_as_customer_2,

    SUM(shared_rare_ip_count)
        AS shared_rare_ip_evidence,

    COUNT(*) FILTER (
        WHERE shared_high_risk_rare_ip_count > 0
    ) AS relationships_with_high_risk_ip,

    ROUND(
        AVG(relationship_strength_score),
        2
    ) AS avg_relationship_strength,

    MAX(relationship_strength_score)
        AS max_relationship_strength

FROM analytics.entity_relationships;


/* ============================================================
   60. RELATIONSHIP STRENGTH DISTRIBUTION
   ============================================================ */

SELECT
    relationship_strength_score,
    COUNT(*) AS relationship_pairs,

    ROUND(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (),
        2
    ) AS relationship_pct

FROM analytics.entity_relationships

GROUP BY relationship_strength_score

ORDER BY relationship_strength_score DESC;


/* ============================================================
   61. STRONGEST RELATIONSHIPS
   ============================================================ */

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
    customer_2_risk_tier

FROM analytics.entity_relationships

ORDER BY
    relationship_strength_score DESC,
    shared_high_risk_rare_ip_count DESC,
    customer_1_risk_score + customer_2_risk_score DESC

LIMIT 25;


/* ============================================================
   62. CUSTOMER NETWORK METRICS
   ============================================================ */

CREATE TABLE analytics.customer_network_metrics AS

WITH undirected_edges AS (

    SELECT
        customer_1 AS customer_id,
        customer_2 AS connected_customer,
        relationship_strength_score,
        shared_rare_ip_count,
        shared_high_risk_rare_ip_count

    FROM analytics.entity_relationships

    UNION ALL

    SELECT
        customer_2 AS customer_id,
        customer_1 AS connected_customer,
        relationship_strength_score,
        shared_rare_ip_count,
        shared_high_risk_rare_ip_count

    FROM analytics.entity_relationships
),

network AS (

    SELECT
        e.customer_id,

        COUNT(DISTINCT e.connected_customer)
            AS network_degree,

        SUM(e.relationship_strength_score)
            AS total_relationship_strength,

        MAX(e.relationship_strength_score)
            AS strongest_relationship_score,

        SUM(e.shared_rare_ip_count)
            AS rare_ip_link_count,

        SUM(e.shared_high_risk_rare_ip_count)
            AS high_risk_rare_ip_link_count,

        COUNT(DISTINCT e.connected_customer) FILTER (
            WHERE cr.customer_risk_tier
                  IN ('High', 'Critical')
        ) AS high_risk_customer_connections,

        ROUND(
            AVG(cr.customer_risk_score),
            2
        ) AS avg_connected_customer_risk_score,

        MAX(cr.customer_risk_score)
            AS max_connected_customer_risk_score

    FROM undirected_edges e

    JOIN analytics.customer_risk_score cr
        ON e.connected_customer = cr.customer_id

    GROUP BY e.customer_id
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

    COALESCE(n.rare_ip_link_count, 0)
        AS rare_ip_link_count,

    COALESCE(n.high_risk_rare_ip_link_count, 0)
        AS high_risk_rare_ip_link_count,

    COALESCE(n.high_risk_customer_connections, 0)
        AS high_risk_customer_connections,

    COALESCE(n.avg_connected_customer_risk_score, 0)
        AS avg_connected_customer_risk_score,

    COALESCE(n.max_connected_customer_risk_score, 0)
        AS max_connected_customer_risk_score

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

    rare_ip_link_count,
    high_risk_rare_ip_link_count,

    high_risk_customer_connections,
    avg_connected_customer_risk_score,
    max_connected_customer_risk_score

FROM analytics.customer_network_metrics

WHERE network_degree > 0

ORDER BY
    network_degree DESC,
    total_relationship_strength DESC,
    customer_risk_score DESC

LIMIT 25;


/* ============================================================
   64. HIGH-RISK NETWORK EXPOSURE
   ============================================================ */

SELECT
    customer_id,
    customer_risk_score,
    customer_risk_tier,

    network_degree,
    high_risk_customer_connections,

    ROUND(
        100.0 * high_risk_customer_connections
        / NULLIF(network_degree, 0),
        2
    ) AS high_risk_connection_pct,

    avg_connected_customer_risk_score,
    max_connected_customer_risk_score,

    high_risk_rare_ip_link_count

FROM analytics.customer_network_metrics

WHERE high_risk_customer_connections > 0

ORDER BY
    high_risk_customer_connections DESC,
    high_risk_connection_pct DESC,
    customer_risk_score DESC

LIMIT 25;


/* ============================================================
   65. NETWORK RISK OVERLAY

   Separate analytical overlay.
   DOES NOT overwrite customer_risk_score.

   Max overlay = 15.
   ============================================================ */

SELECT
    customer_id,

    customer_risk_score
        AS base_risk_score,

    customer_risk_tier
        AS base_risk_tier,

    network_degree,

    high_risk_customer_connections,

    high_risk_rare_ip_link_count,

    LEAST(
        15,

        CASE
            WHEN network_degree >= 10 THEN 5
            WHEN network_degree >= 5 THEN 3
            WHEN network_degree >= 1 THEN 1
            ELSE 0
        END

        +

        CASE
            WHEN high_risk_customer_connections >= 3 THEN 5
            WHEN high_risk_customer_connections >= 1 THEN 3
            ELSE 0
        END

        +

        CASE
            WHEN high_risk_rare_ip_link_count >= 3 THEN 5
            WHEN high_risk_rare_ip_link_count >= 1 THEN 3
            ELSE 0
        END

    ) AS network_risk_overlay

FROM analytics.customer_network_metrics

ORDER BY
    network_risk_overlay DESC,
    customer_risk_score DESC,
    network_degree DESC

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
             COUNT(DISTINCT (customer_1, customer_2))
            THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS total_relationships,
    COUNT(DISTINCT (customer_1, customer_2))
        AS unique_relationships
FROM analytics.entity_relationships;


/* V3 — Canonical pair ordering */

SELECT
    'Canonical relationship ordering' AS validation,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS invalid_count
FROM analytics.entity_relationships
WHERE customer_1 >= customer_2;


/* V4 — Every edge has rare-IP evidence */

SELECT
    'Rare IP evidence' AS validation,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS invalid_count
FROM analytics.entity_relationships
WHERE shared_rare_ip_count <= 0;


/* V5 — Suppression threshold respected */

SELECT
    'Common IP suppression' AS validation,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS invalid_count
FROM analytics.entity_relationships
WHERE rarest_shared_ip_prevalence > 5;


/* V6 — Positive relationship score */

SELECT
    'Positive relationship strength' AS validation,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS invalid_count
FROM analytics.entity_relationships
WHERE relationship_strength_score <= 0;


/* V7 — Customer references valid */

SELECT
    'Valid relationship customers' AS validation,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS invalid_count
FROM analytics.entity_relationships e
LEFT JOIN core.customers c1
    ON e.customer_1 = c1.customer_id
LEFT JOIN core.customers c2
    ON e.customer_2 = c2.customer_id
WHERE c1.customer_id IS NULL
   OR c2.customer_id IS NULL;


/* V8 — Network table covers all customers */

SELECT
    'Network customer coverage' AS validation,
    CASE
        WHEN COUNT(*) = 10000 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS observed_customers
FROM analytics.customer_network_metrics;


/* V9 — Degree non-negative */

SELECT
    'Network degree range' AS validation,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS invalid_count
FROM analytics.customer_network_metrics
WHERE network_degree < 0;


/* V10 — Degree reconciliation

   Every undirected edge contributes degree to two customers.
   Therefore:
   SUM(network_degree) = 2 * relationship_pairs
*/

SELECT
    'Network degree reconciliation' AS validation,
    CASE
        WHEN
            (SELECT SUM(network_degree)
             FROM analytics.customer_network_metrics)
            =
            2 * (
                SELECT COUNT(*)
                FROM analytics.entity_relationships
            )
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result,

    (SELECT SUM(network_degree)
     FROM analytics.customer_network_metrics)
        AS observed_total_degree,

    2 * (
        SELECT COUNT(*)
        FROM analytics.entity_relationships
    ) AS expected_total_degree;


/* V11 — Customers with connections exist */

SELECT
    'Connected customer population' AS validation,
    CASE
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS connected_customers
FROM analytics.customer_network_metrics
WHERE network_degree > 0;


/* ============================================================
   FINAL SCORECARD
   ============================================================ */

SELECT
    (SELECT COUNT(*)
     FROM analytics.entity_relationships)
        AS relationship_pairs,

    (SELECT COUNT(*)
     FROM analytics.customer_network_metrics
     WHERE network_degree > 0)
        AS connected_customers,

    (SELECT ROUND(
         100.0 * COUNT(*) / 10000,
         2
     )
     FROM analytics.customer_network_metrics
     WHERE network_degree > 0)
        AS connected_customer_pct,

    (SELECT ROUND(AVG(network_degree), 2)
     FROM analytics.customer_network_metrics
     WHERE network_degree > 0)
        AS avg_degree_connected_customers,

    (SELECT MAX(network_degree)
     FROM analytics.customer_network_metrics)
        AS max_network_degree,

    (SELECT COUNT(*)
     FROM analytics.entity_relationships
     WHERE shared_high_risk_rare_ip_count > 0)
        AS high_risk_rare_ip_relationships,

    (SELECT COUNT(*)
     FROM analytics.customer_network_metrics
     WHERE high_risk_customer_connections > 0)
        AS customers_connected_to_high_risk_customers,

    (SELECT MAX(relationship_strength_score)
     FROM analytics.entity_relationships)
        AS max_relationship_strength;
