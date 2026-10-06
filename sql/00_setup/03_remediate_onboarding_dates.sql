/* ============================================================
   03. DATA REMEDIATION — ONBOARDING DATES BEFORE FIRST ACTIVITY
   ------------------------------------------------------------
   Run after the Python generators have loaded customers, accounts
   and transactions (see docs/project_runbook.md).

   Issue (validation check DQ11):
     generate_customers.py draws customer_since relative to the date
     the script is run (Faker "-10y" .. "-30d"), while transactions
     are fixed to Jan 2023 - Dec 2025. Accounts inherit customer_since
     as open_date. Result: 99,358 transactions (19.9%) for 3,465
     customers are dated before the customer was onboarded and the
     account was opened; 435 customers "joined" in 2026.

   Remediation:
     For affected customers only, move customer_since to 30-729 days
     before their first transaction (deterministic per customer, so the
     script is repeatable), and align account open dates and the stored
     copy in analytics.customer_risk_score.
     Tenure is not used in any score or reported metric, so no KPI changes.

   Permanent fix (v1.1): generate customer_since within a fixed window
   that ends before Jan 2023.
   ============================================================ */

BEGIN;

WITH first_txn AS (
    SELECT customer_id, MIN(transaction_timestamp)::DATE AS first_txn_date
    FROM core.transactions
    GROUP BY customer_id
)
UPDATE core.customers c
SET customer_since = f.first_txn_date - (30 + ABS(HASHTEXT(c.customer_id)) % 700)
FROM first_txn f
WHERE f.customer_id = c.customer_id
  AND c.customer_since > f.first_txn_date;

UPDATE core.accounts a
SET open_date = c.customer_since
FROM core.customers c
WHERE c.customer_id = a.customer_id
  AND a.open_date > c.customer_since;

UPDATE analytics.customer_risk_score r
SET customer_since = c.customer_since
FROM core.customers c
WHERE c.customer_id = r.customer_id
  AND r.customer_since IS DISTINCT FROM c.customer_since;

/* Verify before committing: both counts must be 0 */
SELECT
    (SELECT COUNT(*) FROM core.transactions t JOIN core.customers c USING (customer_id)
     WHERE t.transaction_timestamp::DATE < c.customer_since)          AS txn_before_customer_since,
    (SELECT COUNT(*) FROM core.transactions t JOIN core.accounts a USING (account_id)
     WHERE t.transaction_timestamp::DATE < a.open_date)               AS txn_before_account_open;

COMMIT;
