import random
import pandas as pd
from data_generator import engine

random.seed(42)

accounts = pd.read_sql("""
    SELECT a.account_id, a.customer_id, c.income_band
    FROM core.accounts a
    JOIN core.customers c
        ON a.customer_id = c.customer_id
    WHERE a.account_type = 'Credit Card'
""", engine)

limit_map = {
    "<30K": (500, 2500),
    "30K-50K": (1000, 5000),
    "50K-75K": (2000, 8000),
    "75K-100K": (5000, 12000),
    "100K-150K": (8000, 20000),
    "150K+": (15000, 35000),
}

rows = []

for _, row in accounts.iterrows():
    low, high = limit_map.get(row["income_band"], (1000, 5000))

    rows.append({
        "card_id": f"CRD{len(rows) + 1:08d}",
        "account_id": row["account_id"],
        "customer_id": row["customer_id"],
        "card_type": random.choice(["Rewards", "Cashback", "Travel", "Secured"]),
        "card_status": "Active",
        "credit_limit": round(random.uniform(low, high), 2),
        "issue_date": pd.Timestamp.today().date(),
        "expiry_date": (pd.Timestamp.today() + pd.DateOffset(years=4)).date()
    })

df = pd.DataFrame(rows)

df.to_sql(
    "cards",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=1000
)

print(f"Loaded {len(df)} cards into core.cards")