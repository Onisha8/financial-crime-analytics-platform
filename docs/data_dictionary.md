# Data Dictionary

PostgreSQL database with three schemas:

| Schema | Purpose |
|---|---|
| `core` | Normalised banking and operational data: customers, accounts, transactions, alerts, investigations, cases, SARs, audit trail |
| `reference` | Rule metadata |
| `analytics` | Derived features, scores, network tables and the Power BI reporting views |

Row counts are from the v1.0 build. Full column definitions: [`01_create_schema.sql`](../sql/00_setup/01_create_schema.sql)
(the tables marked † are created by their Python generator instead).

## Core: customers and accounts

| Table | Grain | Key / foreign keys | Rows | Business meaning and key columns |
|---|---|---|---:|---|
| `customers` | Customer | PK `customer_id` | 10,000 | Onboarded customer. `customer_since`, `state`, `occupation`, `income_band`, `kyc_risk_rating` (Low/Medium/High), `politically_exposed_person_flag`, `customer_segment` |
| `customer_kyc` | Customer | PK `kyc_id`; FK `customer_id` | 10,000 | KYC profile. `kyc_level` (Standard/Enhanced), `kyc_status` (Approved/Pending Review/Expired), `source_of_funds`, `expected_monthly_income`, `expected_monthly_txn_volume`, `last_review_date`, `next_review_date` |
| `customer_addresses` / `customer_phones` / `customer_emails` | Contact record | PK `*_id`; FK `customer_id` | 10,000 each | Contact details |
| `accounts` | Account | PK `account_id`; FK `customer_id` | 21,501 | `account_type`, `open_date`, `status`, `current_balance` |
| `cards` | Card | PK `card_id`; FK `account_id`, `customer_id` | 4,506 | `card_type`, `card_status`, `credit_limit` |
| `beneficiaries` | Registered payee | PK `beneficiary_id`; FK `customer_id` | 7,388 | `beneficiary_bank_country`, `relationship_type` |
| `loans` / `loan_payments` | Loan / payment | PK `loan_id` / `loan_payment_id` | 3,782 / 78,365 | Credit context; not used by the FinCrime analytics |
| `branches` | Branch | PK `branch_id` | 5 | Branch master |
| `employees` | Employee | PK `employee_id`; FK `branch_id` | 30 | 16 investigators plus managers, analysts and compliance staff. `role_name`, `workload_capacity`, `manager_id` |

## Core: activity

| Table | Grain | Key / foreign keys | Rows | Business meaning and key columns |
|---|---|---|---:|---|
| `transactions` | Transaction | PK `transaction_id`; FK account, customer, card, merchant, beneficiary, device, IP | 500,000 | Jan 2023 - Dec 2025, $2.0956B. `transaction_type` (CARD_PURCHASE, ACH_TRANSFER, BILL_PAYMENT, ONLINE_TRANSFER, ATM_WITHDRAWAL, CASH_DEPOSIT, WIRE_TRANSFER), `amount`, `origin_country`, `destination_country`. `suspicious_flag` / `scenario_type` = planted scenario label (8,500 rows) |
| `merchants` | Merchant | PK `merchant_id` | 2,000 | `merchant_category` (15 categories), `merchant_risk_rating` |
| `devices` | Device | PK `device_id`; FK `customer_id` | 13,608 | `device_type`, `operating_system`, first/last seen |
| `ip_addresses` | IP address | PK `ip_id` | 20,000 | `ip_country`, `risk_rating` (High 752 / Medium 3,492 / Low 15,756) |
| `login_events` | Login | PK `login_id`; FK customer, device, IP | 305,734 | `login_success`, `mfa_used`; input to digital risk and entity resolution |

## Core: monitoring and investigation workflow

| Table | Grain | Key / foreign keys | Rows | Business meaning and key columns |
|---|---|---|---:|---|
| `alerts` | Alert (transaction x rule) | PK `alert_id`; FK transaction, customer, account, `rule_id` | 53,392 | `alert_date`, `alert_score` (65-95), `priority` (High/Medium) |
| `investigations` | Investigation | PK `investigation_id`; FK `alert_id`, `investigator_id` | 53,392 | One per alert. `investigation_start`, `investigation_end` (NULL = open; 5,339), `disposition` |
| `investigator_actions` † | Investigator action | PK `action_id`; FK investigation, alert, investigator | 213,544 | Review steps such as Transaction Review, Escalation Assessment, KYC Review |
| `cases` | Case | PK `case_id`; FK `customer_id`; `investigation_id` | 18,597 | `case_open_date`, `case_close_date`, `case_status` (Open 5,447 / Closed 13,150), `case_type` (by rule), `risk_rating` (Critical/High/Medium) |
| `case_alerts` | Case x alert | PK (`case_id`, `alert_id`) | 54,674 | Alerts grouped into a case |
| `case_notes` † | Note | PK `note_id`; FK case, investigation, author | 98,439 | Case narrative entries |
| `sar_reports` | SAR | PK `sar_id`; FK `case_id`, `customer_id` | 11,103 | At most one per case. `filing_date`, `sar_status` (Filed 10,230 / Under Review 873) |
| `audit_logs` † | Audit event | PK `audit_id`; FK to customer, alert, investigation, case, SAR, employee | 411,231 | ALERT_CREATED, INVESTIGATION_ASSIGNED, INVESTIGATION_COMPLETED, INVESTIGATOR_ACTION_COMPLETED, CASE_CREATED, CASE_CLOSED, SAR_FILED |

## Reference

| Table | Grain | Rows | Business meaning |
|---|---|---:|---|
| `alert_rules` | TM rule | 8 | `rule_id` TM001-TM008, name, description, `threshold_value`, `severity`. See [methodology](methodology.md#2-transaction-monitoring-rules) for implemented logic |

## Analytics: derived tables

| Table | Grain | Rows | Built by | Meaning |
|---|---|---:|---|---|
| `customer_risk_features` | Customer | 10,000 | 47_55 | Raw behavioural, digital and FinCrime-history features |
| `customer_risk_score` | Customer | 10,000 | 47_55 | Features plus the four component scores, composite `customer_risk_score` (0-100), `customer_risk_tier`, `risk_reasons` |
| `entity_relationships` | Customer pair | 389 | 56_65 | Rare shared-IP relationships: `shared_rare_ip_count`, `rarest_shared_ip_prevalence`, `relationship_strength_score`, both customers' risk |
| `customer_network_metrics` | Customer | 10,000 | 56_65 | `network_degree`, relationship strength, high-risk connections, neighbour risk |

Tables such as `tm_rule_performance`, `rule_overlap_analysis` and `investigator_workload_summary` are outputs of the
exploratory analysis files (01-28) in [`sql/02_tm_performance`](../sql/02_tm_performance) and
[`sql/03_investigation_operations`](../sql/03_investigation_operations). The dashboards do not use them.

## Analytics: reporting views (Power BI)

| View | Grain | Rows | Dashboard page | Built by |
|---|---|---:|---|---|
| `vw_executive_kpis` | One row | 1 | Executive Overview | 66_75 |
| `vw_monthly_fincrime_funnel` | Month | 36 | Executive Overview | 66_75 |
| `vw_tm_rule_performance` | TM rule | 8 | TM Model Performance | 66_75 |
| `vw_tm_threshold_simulation` | Score threshold | 6 | TM Model Performance | 76 |
| `vw_investigation_sla` | Investigation (as of 2026-06-30) | 53,392 | Investigation Operations | 66_75 |
| `vw_investigator_performance` | Investigator | 16 | Investigation Operations | 66_75 |
| `vw_customer_risk_dashboard` | Customer | 10,000 | Customer & Network Risk | 66_75 |
| `vw_network_customer_metrics` | Customer | 10,000 | Customer & Network Risk | 66_75 |
| `vw_network_relationships` | Customer pair | 389 | Customer & Network Risk | 66_75 |
| `vw_tm008_tuning_scenarios` | Scenario | 7 | Tuning & KYC Review | 77 |
| `vw_kyc_profile_review` | Customer | 10,000 | Tuning & KYC Review | 78 |

Key derived columns:

| View | Column | Definition |
|---|---|---|
| `vw_investigation_sla` | `sla_days` | Critical 7, High 15, Medium 30, Low 45 |
| | `snapshot_status` | Closed if ended on or before 2026-06-30 23:59:59, else Open |
| | `lifecycle_days` | (end, or snapshot if open) - start, in days |
| | `sla_status` | Closed/Open x Within/Breached SLA |
| `vw_tm_threshold_simulation` | `sars_missed_per_1k_suppressed` | SARs lost per 1,000 alerts suppressed |
| `vw_tm008_tuning_scenarios` | `high_risk_lift` | Share of alerted customers who are KYC High-risk or PEP / population share |
| `vw_kyc_profile_review` | `activity_to_profile_ratio` | Actual average monthly volume / declared expected monthly volume |
| | `review_priority` | P1 / P2 / P3 / No action (see [methodology](methodology.md#8-kyc-profile-review)) |
