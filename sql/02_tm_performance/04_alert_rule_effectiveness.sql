--------------------------------------------------------
-- Alert Rule Effectiveness Dashboard
--------------------------------------------------------
SELECT
    ar.rule_id,
    ar.rule_name,
    COUNT(DISTINCT a.alert_id) AS alerts_generated,
    COUNT(DISTINCT i.investigation_id) AS investigations,
    COUNT(DISTINCT ca.case_id) AS cases,
    COUNT(DISTINCT s.sar_id) AS sar_reports,
    ROUND(AVG(a.alert_score),2) AS average_alert_score,
    ROUND(
        COUNT(DISTINCT ca.case_id)::numeric/ NULLIF(COUNT(DISTINCT a.alert_id),0)*100
    ,2) AS case_conversion_rate,
    ROUND(
        COUNT(DISTINCT s.sar_id)::numeric/ NULLIF(COUNT(DISTINCT a.alert_id),0)*100
    ,2) AS sar_conversion_rate
FROM reference.alert_rules ar
LEFT JOIN core.alerts a
ON ar.rule_id = a.rule_id
LEFT JOIN core.investigations i
ON a.alert_id = i.alert_id
LEFT JOIN core.case_alerts ca
ON a.alert_id = ca.alert_id
LEFT JOIN core.sar_reports s
ON ca.case_id = s.case_id
GROUP BY
    ar.rule_id,
    ar.rule_name
ORDER BY alerts_generated DESC;