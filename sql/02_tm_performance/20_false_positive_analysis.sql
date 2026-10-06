DROP TABLE IF EXISTS analytics.false_positive_analysis;

CREATE TABLE analytics.false_positive_analysis AS
WITH alert_outcomes AS (
    SELECT
        a.alert_id,
        a.rule_id,
        a.alert_score,
        i.disposition,
        CASE
            WHEN i.disposition IN (
                'False Positive',
                'Closed - No Issue'
            )
            THEN 1
            ELSE 0
        END AS false_positive_flag,
        CASE
            WHEN ca.case_id IS NOT NULL
            THEN 1
            ELSE 0
        END AS case_flag,
        CASE
            WHEN s.sar_id IS NOT NULL
            THEN 1
            ELSE 0
        END AS sar_flag
    FROM core.alerts a
    LEFT JOIN core.investigations i
        ON a.alert_id = i.alert_id
    LEFT JOIN core.case_alerts ca
        ON a.alert_id = ca.alert_id
    LEFT JOIN core.sar_reports s
        ON ca.case_id = s.case_id
),
deduplicated_alerts AS (
    SELECT
        alert_id,
        rule_id,
        alert_score,
        disposition,
        MAX(false_positive_flag) AS false_positive_flag,
        MAX(case_flag) AS case_flag,
        MAX(sar_flag) AS sar_flag
    FROM alert_outcomes
    GROUP BY
        alert_id,
        rule_id,
        alert_score,
        disposition
)
SELECT
    d.rule_id,
    r.rule_name,
    COUNT(*) AS total_alerts,
    SUM(d.false_positive_flag) AS false_positive_alerts,
    COUNT(*) - SUM(d.false_positive_flag) AS non_false_positive_alerts,
    ROUND( SUM(d.false_positive_flag)::NUMERIC/ NULLIF(COUNT(*), 0)* 100,2) AS false_positive_rate,
    SUM(d.case_flag) AS case_alerts,
    SUM(d.sar_flag) AS sar_alerts,
    ROUND( AVG(d.alert_score) FILTER (WHERE d.false_positive_flag = 1),2 ) AS average_false_positive_score,
    ROUND( AVG(d.alert_score) FILTER (WHERE d.sar_flag = 1),2) AS average_sar_alert_score,
    CASE
        WHEN
            SUM(d.false_positive_flag)::NUMERIC/ NULLIF(COUNT(*), 0) >= 0.70
            THEN 'Critical Tuning Priority'
        WHEN
            SUM(d.false_positive_flag)::NUMERIC/ NULLIF(COUNT(*), 0) >= 0.50
            THEN 'High Tuning Priority'
        WHEN
            SUM(d.false_positive_flag)::NUMERIC/ NULLIF(COUNT(*), 0) >= 0.30
            THEN 'Moderate Tuning Priority'
        ELSE 'Acceptable'
    END AS tuning_priority
FROM deduplicated_alerts d
JOIN reference.alert_rules r
    ON d.rule_id = r.rule_id
GROUP BY
    d.rule_id,
    r.rule_name;