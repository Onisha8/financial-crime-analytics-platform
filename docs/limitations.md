# Limitations

This is a portfolio project built on synthetic data. The architecture, SQL, validation and reporting patterns are the
demonstration; the outcome numbers are not evidence about real financial crime. This page lists every known limitation,
what it affects, and what should not be concluded from it.

## 1. What not to read as findings

| Metric | Why it carries no signal |
|---|---|
| False-positive rate by rule (41.6-44.9%) and its flatness across rules and thresholds | Investigation dispositions are drawn from fixed weights (45% False Positive, 20% Escalated, 15% Monitoring, 20% Closed - No Issue), independent of rule, score or customer |
| SAR yield differences between rules or score bands | SAR filing probability uses case risk rating, disposition and a small bonus for alert scores >= 80 / >= 90; the analysis recovers these generator settings |
| Absolute rates (42.5% FP, 59.7% case-to-SAR, ~21% alert-to-SAR) | Chosen generator weights. Real TM programmes typically see false-positive rates above 90% and low single-digit alert-to-SAR yield |
| TM008's 67.7% alert share | A consequence of how broadly the rule was written (see [key_findings.md](key_findings.md)), not tuning evidence from a live system |

## 2. Synthetic data generation

| Area | Limitation | Effect |
|---|---|---|
| Alert scores | Random within a rule-specific band (for example TM008: 72-92) | Threshold simulation shows mechanics, not a real score-to-risk relationship |
| Ground truth | `suspicious_flag` (8,500 transactions) marks planted scenarios for TM001/TM004/TM006 only and uses the same criteria as those rules | Not independent ground truth; recall cannot be measured |
| Risk score input | The transaction component uses `suspicious_flag`, which would not exist in production | Slight label leakage into the customer risk score |
| Behaviour vs risk | Purchase behaviour, KYC rating and declared expected activity are generated independently | Behavioural rules cannot show better targeting (TM008 S3/S4 lift ~1.0); declared profiles do not predict activity (correlation -0.014) |
| IP assignment | 20,000 IPs randomly reused across 305,734 logins | Almost every IP is "common"; the entity network is sparse (389 relationships) |
| Investigation duration | Uniform 1-30 days | A Medium-priority investigation (30-day SLA) cannot breach after closing; all open breaches are High priority |
| Priorities | Only High and Medium alerts exist | Critical (7-day) and Low (45-day) SLA tiers are defined but unused |
| Rule design | All rules are single-transaction except TM003 (dormancy gap) and TM005 (device sharing); TM001 flags single deposits, not multi-deposit structuring | Rules are simpler than production TM scenarios |
| Faker dates | Some generators draw dates relative to the run date | A rebuild produces equivalent but not identical data |

## 3. Known data integrity issues

Each issue below is tracked by a validation check, so it stays visible until fixed.

| Check | Issue | Status |
|---|---|---|
| LC09 (WARN) | 53,257 investigations (99.7%) start more than 30 days after their alert. Alerts span 2023-2025; investigations start Jan-Jun 2026 | Documented. TAT and SLA are measured from investigation start, so they are internally consistent; alert-to-investigation lag is not reported |
| LC12 (WARN) | 17,695 cases (95%) open before their investigation completes. The generator opens cases 0-3 days after investigation **start** | Documented. No reported metric uses case or SAR dates |
| DQ11 (fixed) | 99,358 transactions (19.9%) were dated before the customer was onboarded or the account opened, because onboarding dates were generated relative to the run date | Remediated by [`03_remediate_onboarding_dates.sql`](../sql/00_setup/03_remediate_onboarding_dates.sql); check now passes |
| Rule metadata | `reference.alert_rules.threshold_value` differs from implemented logic for TM003 ($2,500 vs $10,000) and TM004 ($5,000 vs $10,000) | Documented in [methodology.md](methodology.md#2-transaction-monitoring-rules) |
| KYC status | 291 customers have status `Expired` with a future `next_review_date` | Surfaced as a finding in the KYC profile review |

## 4. Reporting assumptions

- SLA thresholds (7/15/30/45 days) and the 2026-06-30 snapshot date are portfolio assumptions, not regulatory requirements.
- Transactions end on 2025-12-31 while the operational snapshot is 2026-06-30, so the snapshot reflects the investigation
  backlog, not recent transaction activity.
- Customer risk tiers, entity-relationship strength and KYC review priorities are analytical constructs, not regulatory or
  production risk ratings.

## 5. Planned v1.1: workflow realism

One generator pass would fix the issues that share a root cause:

1. Give customers a hidden typology label (structuring, mule, funnel account, none) and plant matching behaviour.
2. Derive alert scores from transaction features instead of random bands.
3. Make dispositions and SARs depend on the hidden label plus investigator noise, which produces realistic FP rates and lets
   tuning measure recall.
4. Start investigations within days of the alert (fixes LC09) and open cases at escalation (fixes LC12).
5. Generate onboarding dates in a fixed window before 2023 (permanent fix for DQ11).

The validation suite is reconciliation-based, so it will verify the regenerated data unchanged, apart from the four baseline
checks.
