INSERT INTO reference.alert_rules
(rule_id, rule_name, rule_description, rule_version, threshold_value, severity, effective_date, status, owner_team)
VALUES
('TM001', 'Structuring', 'Multiple cash deposits below reporting threshold within a short time window.', '1.0', 10000, 'High', '2023-01-01', 'Active', 'Financial Crime Analytics'),
('TM002', 'High Risk Geography', 'Transaction involving high-risk origin or destination country.', '1.0', NULL, 'Critical', '2023-01-01', 'Active', 'Financial Crime Analytics'),
('TM003', 'Dormant Account Activity', 'Previously dormant account shows sudden high-value activity.', '1.0', 2500, 'High', '2023-01-01', 'Active', 'Financial Crime Analytics'),
('TM004', 'Rapid Movement of Funds', 'Incoming funds are quickly transferred out within a short time window.', '1.0', 5000, 'High', '2023-01-01', 'Active', 'Financial Crime Analytics'),
('TM005', 'Shared Device Risk', 'Multiple unrelated customers transact using the same device.', '1.0', NULL, 'Medium', '2023-01-01', 'Active', 'Financial Crime Analytics'),
('TM006', 'Large Wire Transfer', 'Wire transfer exceeds high-value monitoring threshold.', '1.0', 25000, 'High', '2023-01-01', 'Active', 'Financial Crime Analytics'),
('TM007', 'Round Dollar Pattern', 'Repeated round-dollar transactions indicate potential layering or structuring.', '1.0', NULL, 'Medium', '2023-01-01', 'Active', 'Financial Crime Analytics'),
('TM008', 'High Risk Merchant', 'Transaction with merchant category or merchant risk rating associated with elevated financial crime risk.', '1.0', NULL, 'Medium', '2023-01-01', 'Active', 'Financial Crime Analytics')
ON CONFLICT (rule_id) DO NOTHING;
