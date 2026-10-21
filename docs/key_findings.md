# Key Findings

Business-facing findings from the v1.0 data. Each finding gives the evidence, what it means, and its caveat.
The data is synthetic: these findings show the analysis an analyst would run and how they would reason about it.
They are not claims about real-world financial crime. See [limitations.md](limitations.md).

| # | Finding | Area |
|---|---|---|
| 1 | TM008 generates two-thirds of all alerts and cannot distinguish risky customers | TM tuning |
| 2 | Repeat-pattern and risk-segmented redesigns cut TM008 volume by more than 90% | TM tuning |
| 3 | Score-threshold suppression has a rising, non-trivial SAR cost | TM tuning |
| 4 | SLA breaches sit entirely in High-priority work | Operations |
| 5 | Naive shared-IP linkage overstated the network about 5,800-fold | Entity resolution |
| 6 | 80% of high-risk customers are not on enhanced due diligence | KYC |
| 7 | Declared KYC activity profiles do not predict behaviour | KYC / data quality |
| 8 | Customer risk is concentrated in a small High/Critical tier | Customer risk |
| 9 | Data quality issues found and handled through validation | Data quality |

---

## 1. TM008 generates two-thirds of all alerts and cannot distinguish risky customers

**Evidence**
- 36,164 of 53,392 alerts (67.7%), alerting on 9,475 of 10,000 customers (94.8%).
- The $500 trigger sits just above the median card purchase ($453); about 45% of all card purchases are >= $500.
- The alert rate is ~94% in every KYC risk tier (High 93.4%, Medium 94.4%, Low 94.9%). Targeting lift = 0.99.
- 2,319 alerts come from ordinary categories (luxury goods, utilities, travel, grocery, ...) whose merchant happens to be rated High.

**So what:** A rule that alerts on almost every customer adds workload without adding risk insight. The trigger, not
duplication, is the problem: consolidating to one alert per customer per month removes only 5.5%.

## 2. Repeat-pattern and risk-segmented redesigns cut TM008 volume by more than 90%

| Scenario | Alerts | Reduction | Customers alerted | High-risk lift |
|---|---:|---:|---:|---:|
| S0 Current | 36,164 | - | 94.8% | 0.99 |
| S2 High-risk categories only | 33,845 | 6.4% | 93.9% | 0.99 |
| S3 Repeat pattern (2+ / $1.5K in 30 days) | 942 | 97.4% | 8.7% | 1.00 |
| S5 KYC High-risk / PEP only | 2,142 | 94.1% | 5.6% | 16.72 |
| **S6 Hybrid (S3 + S5)** | **3,084** | **91.5%** | 13.8% | 6.81 |

**So what:** The hybrid design keeps every KYC High-risk/PEP customer alerted today while requiring repeated behaviour from
everyone else. The trade-off is explicit: about 8,100 standard-risk customers would no longer alert on a single purchase.
That is a risk-appetite decision, not an analytical one.

**Caveat:** S5/S6 lift comes from segmenting on KYC risk by design. Repeat-pattern rules alone (S3/S4) do not target better
(lift 1.00-1.14), because synthetic behaviour is independent of KYC risk. Outcome-based comparison (SAR yield) is not
possible on this data. Full detail: [`77_tm008_tuning_scenarios.sql`](../sql/02_tm_performance/77_tm008_tuning_scenarios.sql).

## 3. Score-threshold suppression has a rising, non-trivial SAR cost

| Threshold | Workload reduction | SARs retained | SARs missed | SARs missed per 1,000 alerts suppressed |
|---:|---:|---:|---:|---:|
| 70 | 2.0% | 99.4% | 69 | 64 |
| 75 | 17.8% | 87.5% | 1,385 | 146 |
| 80 | 41.8% | 68.5% | 3,502 | 157 |
| 85 | 67.3% | 39.9% | 6,675 | 186 |
| 90 | 89.9% | 14.4% | 9,503 | 198 |

**So what:** No threshold removes only low-value alerts. At 75, every 1,000 alerts suppressed costs about 146 SARs. A global
score threshold is a blunt lever; rule-specific redesign (finding 2) cuts far more volume.

**Caveat:** Alert scores are random within rule bands, so the curve shows the method rather than a real score-risk relationship.

## 4. SLA breaches sit entirely in High-priority work

**Evidence (snapshot 2026-06-30)**
- 7,179 investigations open at the snapshot; 1,543 breach SLA (78.5% open SLA compliance).
- All 1,543 open breaches are High priority: 44.5% of open High-priority investigations (15-day SLA) are past SLA, versus 0% of
  Medium (30-day SLA).
- Average TAT is 15.4 days for High and 15.3 for Medium. High-priority work is handled no faster than Medium.
- Workload across the 16 investigators ranges from 2,976 to 4,186 assigned investigations.

**So what:** Prioritisation is not working: High-priority alerts wait as long as Medium ones. The fix is routing (work High
first, or a dedicated High queue), not more capacity overall.

**Caveat:** The generator draws every investigation's duration uniformly from 1-30 days regardless of priority. Equal TAT across
priorities is therefore built in, and so is the fact that Medium never breaches after closing. The deliverable is the method:
comparing TAT and breach rates by priority is how a prioritisation failure would be detected.

## 5. Naive shared-IP linkage overstated the network about 5,800-fold

**Evidence**
- Linking every pair of customers who shared an IP produced 2,240,183 relationships.
- 19,956 of 20,000 IPs are used by more than 5 customers (up to 37): shared infrastructure, not shared identity.
- Restricting linkage evidence to rare IPs (2-5 customers) leaves 389 relationships among 207 customers (max degree 4);
  40 involve a High/Critical-tier customer.

**So what:** Without a prevalence check, entity resolution would have flagged nearly every customer as connected, and every
downstream network metric would have been noise. This was the most important correction in the project.

## 6. 80% of high-risk customers are not on enhanced due diligence

**Evidence:** 373 of 468 KYC High-risk customers (79.7%) are on Standard KYC. Including PEPs, 484 customers have an EDD gap.
The share on Standard KYC is similar for Low (84.2%) and Medium (85.3%) customers: KYC level is not aligned with risk.

**So what:** In a real bank this is a control gap and would be escalated. The KYC review queue ranks these customers first
(49 at P1, where the EDD gap coincides with activity of 2x profile or more).

## 7. Declared KYC activity profiles do not predict behaviour

**Evidence**
- Correlation between declared expected monthly volume and actual average monthly volume: -0.014.
- 986 customers (9.9%) average at least 2x their declared volume; 377 (3.8%) exceed 3x.
- 291 customers have KYC status `Expired` with a future next-review date (a status/date conflict).

**So what:** Profile-based monitoring ("activity exceeds expected") would be noise until profiles are refreshed. The review
queue of 2,106 customers (P1 49, P2 517, P3 1,540) prioritises which profiles to refresh first.

**Caveat:** The synthetic generator sets declared and actual activity independently, so the zero correlation is partly by
construction. The method, a profile-versus-activity reconciliation, is the deliverable.

## 8. Customer risk is concentrated in a small High/Critical tier

**Evidence:** Average score 35.71 (range 2-77). Tiers: 3 Critical, 524 High, 6,454 Medium, 3,019 Low.
Every customer carries readable `risk_reasons`.

**So what:** 527 customers (5.3%) form a manageable priority population for enhanced monitoring, and each score can be
explained component by component.

## 9. Data quality issues found and handled through validation

The 62-check validation suite ([results](validation_results.md)) surfaced issues that earlier pack-level checks missed:

| Issue | Scale | Handling |
|---|---|---|
| Transactions before onboarding / account opening | 99,358 transactions, 3,465 customers | Remediated with a repeatable SQL script; check DQ11 passes |
| Investigations starting long after alerts | 53,257 investigations | Documented warning (LC09); fix planned for v1.1 |
| Cases opened before investigation completion | 17,695 cases | Documented warning (LC12); fix planned for v1.1 |
| Rule metadata differs from implementation (TM003, TM004) | 2 rules | Documented |
| Scenario columns added by an `ALTER` hidden in a checks script | Schema | Moved into the schema DDL |
| Threshold simulation stored as hard-coded values | 7 rows | Replaced with a computed view |
