import random
import pandas as pd
from data_generator import engine

random.seed(42)

customers = pd.read_sql("""
    SELECT customer_id, income_band
    FROM core.customers
""", engine)

loan_types = ["Personal Loan", "Auto Loan", "Mortgage", "Small Business Loan"]

balance_ranges = {
    "Personal Loan": (3000, 35000),
    "Auto Loan": (8000, 60000),
    "Mortgage": (120000, 650000),
    "Small Business Loan": (25000, 250000),
}

rows = []

for _, row in customers.iterrows():
    if random.random() < 0.38:
        loan_type = random.choices(
            loan_types,
            weights=[40, 30, 20, 10]
        )[0]

        low, high = balance_ranges[loan_type]
        original_balance = round(random.uniform(low, high), 2)

        rows.append({
            "loan_id": f"L{len(rows) + 1:09d}",
            "customer_id": row["customer_id"],
            "loan_type": loan_type,
            "origination_date": pd.Timestamp("2023-01-01") + pd.Timedelta(days=random.randint(0, 900)),
            "original_balance": original_balance,
            "outstanding_balance": round(original_balance * random.uniform(0.55, 0.98), 2),
            "interest_rate": round(random.uniform(0.045, 0.185), 4),
            "term_months": random.choice([36, 48, 60, 120, 180, 360]),
            "credit_score_at_origination": random.randint(560, 820),
            "loan_status": random.choices(["Current", "Delinquent", "Closed"], weights=[82, 10, 8])[0],
        })

df = pd.DataFrame(rows)

df.to_sql(
    "loans",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=1000
)

print(f"Loaded {len(df)} loans into core.loans")