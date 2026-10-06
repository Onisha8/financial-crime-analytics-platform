-- Run basic transaction data quality checks
-- 1. Total transactions
SELECT COUNT(*) AS transaction_count
FROM core.transactions;

-- 2. Transaction count by type
SELECT transaction_type, COUNT(*) AS txn_count
FROM core.transactions
GROUP BY transaction_type
ORDER BY txn_count DESC;

-- 3. Missing key fields
SELECT
    SUM(CASE WHEN transaction_id IS NULL THEN 1 ELSE 0 END) AS missing_transaction_id,
    SUM(CASE WHEN account_id IS NULL THEN 1 ELSE 0 END) AS missing_account_id,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS missing_customer_id,
    SUM(CASE WHEN transaction_timestamp IS NULL THEN 1 ELSE 0 END) AS missing_timestamp,
    SUM(CASE WHEN amount IS NULL THEN 1 ELSE 0 END) AS missing_amount
FROM core.transactions;

-- 4. Transaction amount range
SELECT
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount,
    AVG(amount) AS avg_amount
FROM core.transactions;

-- 5. Monthly transaction trend
SELECT
    DATE_TRUNC('month', transaction_timestamp)::DATE AS txn_month,
    COUNT(*) AS txn_count,
    SUM(amount) AS total_amount
FROM core.transactions
GROUP BY 1
ORDER BY 1;

-- Create suspicious scenario label columns
ALTER TABLE core.transactions
ADD COLUMN IF NOT EXISTS suspicious_flag BOOLEAN DEFAULT FALSE;

ALTER TABLE core.transactions
ADD COLUMN IF NOT EXISTS scenario_type VARCHAR(100);