import random
import pandas as pd

from data_generator import engine

random.seed(42)

customers = pd.read_sql(
    "SELECT customer_id, customer_segment, customer_since, state FROM core.customers",
    engine
)

account_types = ["Checking", "Savings", "Credit Card", "Business Checking"]

rows = []

for _, row in customers.iterrows():
    customer_id = row["customer_id"]
    segment = row["customer_segment"]

    # Every customer gets a checking account
    rows.append({
        "account_id": f"A{len(rows) + 1:09d}",
        "customer_id": customer_id,
        "account_type": "Checking",
        "open_date": row["customer_since"],
        "status": "Open",
        "branch_state": row["state"],
        "current_balance": round(random.uniform(500, 15000), 2),
    })

    # Most customers get savings
    if random.random() < 0.65:
        rows.append({
            "account_id": f"A{len(rows) + 1:09d}",
            "customer_id": customer_id,
            "account_type": "Savings",
            "open_date": row["customer_since"],
            "status": "Open",
            "branch_state": row["state"],
            "current_balance": round(random.uniform(1000, 50000), 2),
        })

    # Some customers get credit card account
    if random.random() < 0.45:
        rows.append({
            "account_id": f"A{len(rows) + 1:09d}",
            "customer_id": customer_id,
            "account_type": "Credit Card",
            "open_date": row["customer_since"],
            "status": "Open",
            "branch_state": row["state"],
            "current_balance": round(random.uniform(0, 7000), 2),
        })

    # Small business customers may get business checking
    if segment == "Small Business" and random.random() < 0.75:
        rows.append({
            "account_id": f"A{len(rows) + 1:09d}",
            "customer_id": customer_id,
            "account_type": "Business Checking",
            "open_date": row["customer_since"],
            "status": "Open",
            "branch_state": row["state"],
            "current_balance": round(random.uniform(5000, 120000), 2),
        })

accounts = pd.DataFrame(rows)

accounts.to_sql(
    "accounts",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=1000
)

print(f"Loaded {len(accounts)} accounts into core.accounts")