# Project Runbook

How to rebuild the platform from an empty PostgreSQL database, in dependency order, with a checkpoint after each phase.

> **Do not rerun the generators against an existing populated database.** They append data. Rebuild only into an empty database.
>
> The order below was derived from each script's table dependencies. A full from-scratch rebuild has not yet been run
> end to end; the fresh-clone test is part of the v1.0 release checklist.

## 0. Prerequisites

- PostgreSQL 14+ and a client (pgAdmin or psql)
- Python 3.13 (the project venv was built with 3.13)
- Power BI Desktop (to open the report)

```bash
python -m venv venv
venv\Scripts\Activate.ps1          # Windows PowerShell
pip install -r requirements.txt
copy .env.example .env             # then fill in DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
python python/data_generation/data_generator.py   # prints the connected database name
```

## 1. Schema and reference data (SQL)

| Order | File |
|---|---|
| 1 | [`sql/00_setup/01_create_schema.sql`](../sql/00_setup/01_create_schema.sql) |
| 2 | [`sql/00_setup/02_seed_alert_rules.sql`](../sql/00_setup/02_seed_alert_rules.sql) |

**Checkpoint:** `SELECT COUNT(*) FROM reference.alert_rules;` returns 8.

## 2. Banking data (Python)

Run from the repository root, in this order:

```bash
python python/data_generation/load_seed_data.py
python python/data_generation/generate_employees.py
python python/data_generation/generate_customers.py
python python/data_generation/generate_customer_profile_details.py
python python/data_generation/generate_accounts.py
python python/data_generation/generate_cards.py
python python/data_generation/generate_beneficiaries.py
python python/data_generation/generate_devices.py
python python/data_generation/generate_ip_addresses.py
python python/data_generation/generate_login_events.py
python python/data_generation/generate_merchants.py
python python/data_generation/generate_loans.py
python python/data_generation/generate_loan_payments.py
python python/data_generation/generate_transactions.py
```

Then run [`sql/00_setup/03_remediate_onboarding_dates.sql`](../sql/00_setup/03_remediate_onboarding_dates.sql). Its final
SELECT must return `0 | 0` before it commits.

**Checkpoint:** 10,000 customers; 21,501 accounts; 500,000 transactions.

## 3. Transaction monitoring alerts (SQL)

Run [`sql/01_alert_generation/`](../sql/01_alert_generation) files 01 to 06 in order. File 01 labels the planted scenarios
(`suspicious_flag`) and creates TM001/TM004/TM006 alerts.

**Checkpoint:** 53,392 alerts; 8,500 transactions with `suspicious_flag = TRUE`.

## 4. Investigation workflow (Python)

```bash
python python/data_generation/generate_investigations.py
python python/data_generation/assign_investigations.py
python python/data_generation/generate_investigator_actions.py
python python/data_generation/generate_cases.py
python python/data_generation/generate_case_alerts.py
python python/data_generation/generate_sar_reports.py
python python/data_generation/generate_case_notes.py
python python/data_generation/generate_audit_logs.py
```

**Checkpoint:** 53,392 investigations (5,339 open); 18,597 cases; 11,103 SARs.

## 5. Analytics (SQL)

**Required for the dashboards**, in this order:

| Order | File | Creates |
|---|---|---|
| 1 | [`04_customer_risk/47_55_customer_risk_engine.sql`](../sql/04_customer_risk/47_55_customer_risk_engine.sql) | `customer_risk_features`, `customer_risk_score` |
| 2 | [`05_entity_network/56_65_entity_resolution_network_analytics.sql`](../sql/05_entity_network/56_65_entity_resolution_network_analytics.sql) | `entity_relationships`, `customer_network_metrics` |
| 3 | [`06_powerbi_semantic_layer/66_75_powerbi_analytics_layer.sql`](../sql/06_powerbi_semantic_layer/66_75_powerbi_analytics_layer.sql) | 8 reporting views |
| 4 | [`06_powerbi_semantic_layer/76_tm_threshold_simulation.sql`](../sql/06_powerbi_semantic_layer/76_tm_threshold_simulation.sql) | `vw_tm_threshold_simulation` |
| 5 | [`02_tm_performance/77_tm008_tuning_scenarios.sql`](../sql/02_tm_performance/77_tm008_tuning_scenarios.sql) | `vw_tm008_tuning_scenarios` |
| 6 | [`04_customer_risk/78_kyc_profile_review.sql`](../sql/04_customer_risk/78_kyc_profile_review.sql) | `vw_kyc_profile_review` |

Each pack ends with its own validation queries; all should return PASS.

**Analysis library (optional):** the files in [`02_tm_performance`](../sql/02_tm_performance) and
[`03_investigation_operations`](../sql/03_investigation_operations) numbered 01-46 are the exploratory analyses behind the
findings. Run them in numeric order within each folder (10 builds `tm_rule_performance`, which 11-15 and 21 read).

## 6. Validate

```bash
python python/validation/run_validation_suite.py
```

Expected: **62 checks: 60 PASS, 2 WARN, 0 FAIL**. The two warnings (LC09, LC12) are documented in
[limitations.md](limitations.md). The run rewrites [validation_results.md](validation_results.md).
Exit codes: 0 = no failures, 1 = at least one FAIL, 2 = suite could not run (for example, a view is missing).

## 7. Power BI

1. Open [`powerbi/Financial_Crime_Analytics.pbix`](../powerbi/Financial_Crime_Analytics.pbix).
2. Transform data → Data source settings → point the PostgreSQL source at your server and database.
3. Refresh. The KPI cards should match the checkpoints above. See [powerbi/README.md](../powerbi/README.md).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `relation "analytics.vw_..." does not exist` from the validation runner | A view-building file in step 5 was not run, or ran without committing (pgAdmin auto-commit off) |
| `ModuleNotFoundError: data_generator` | Run scripts with the path shown (`python python/data_generation/<script>.py`); they import the shared connection from their own folder |
| Duplicate-key errors from generators | The database already contains data; rebuild into an empty database |
