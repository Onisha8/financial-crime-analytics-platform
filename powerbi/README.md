# Power BI Report

[`Financial_Crime_Analytics.pbix`](Financial_Crime_Analytics.pbix) reads only from the PostgreSQL reporting views in the
`analytics` schema (Import mode). Business logic lives in SQL, so every figure can be traced to a view and is reconciled by
the [validation suite](../docs/validation_results.md). Navigation buttons on each page switch between pages.

## Pages

### 1. Executive Overview
![Executive Overview](screenshots/01_executive_overview.png)

Enterprise volumes and the alert → investigation → case → SAR funnel, monthly alert trend and customer risk mix.
Source: `vw_executive_kpis`, `vw_monthly_fincrime_funnel`, `vw_customer_risk_dashboard`.

### 2. TM Model Performance
![TM Model Performance](screenshots/02_tm_model_performance.png)

Alert volume and customer reach by rule (TM008 alerts 94.8% of customers), rule outcome rates, and the alert-score
threshold trade-off (workload reduction vs SAR retention). Source: `vw_tm_rule_performance`, `vw_tm_threshold_simulation`.
The threshold visual covers all rules; the Rule ID slicer does not filter it.

### 3. Investigation Operations
![Investigation Operations](screenshots/03_investigation_operations.png)

Investigator workload, backlog, capacity utilisation, turnaround time and SLA status as of the 2026-06-30 snapshot.
Source: `vw_investigation_sla`, `vw_investigator_performance`.

### 4. Customer & Network Risk
![Customer & Network Risk](screenshots/04_customer_network_risk.png)

Customer risk tiers, score distribution, risk components by tier, rare-IP entity relationships and high-risk customer detail.
Source: `vw_customer_risk_dashboard`, `vw_network_customer_metrics`, `vw_network_relationships`.

### 5. Tuning & KYC Review
![Tuning & KYC Review](screenshots/05_tuning_kyc_review.png)

TM008 redesign scenarios (alerts, reduction, high-risk lift) and the KYC profile review queue (EDD gaps, activity versus
declared profile, P1-P3 priorities). Source: `vw_tm008_tuning_scenarios`, `vw_kyc_profile_review`.

## Assumptions shown on the report

- **SLA thresholds** (synthetic): Critical 7 days, High 15, Medium 30, Low 45; point-in-time snapshot 2026-06-30.
- **Customer risk**: transparent 0-100 score (KYC 25, Transaction 30, Digital 15, FinCrime 30); tiers Critical >= 75,
  High >= 55, Medium >= 30.
- **Entity relationships**: rare shared-IP evidence only (IP used by 2-5 customers); common IPs suppressed.
- All data is synthetic; outcome rates are generator settings. See [limitations](../docs/limitations.md).

## Refreshing

1. Build the database and views ([runbook](../docs/project_runbook.md)).
2. Transform data → Data source settings → set your PostgreSQL server and database.
3. Refresh, then run `python python/validation/run_validation_suite.py` to confirm the report's sources reconcile.
