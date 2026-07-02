import random
import pandas as pd
from data_generator import engine

random.seed(42)

loans = pd.read_sql("""
    SELECT loan_id, customer_id, origination_date, original_balance, term_months, loan_status
    FROM core.loans
""", engine)

rows = []

for _, loan in loans.iterrows():
    origination_date = pd.to_datetime(loan["origination_date"])
    monthly_due = float(loan["original_balance"]) / int(loan["term_months"])

    max_months = min(
        36,
        max(1, ((pd.Timestamp("2025-12-31").year - origination_date.year) * 12)
               + (pd.Timestamp("2025-12-31").month - origination_date.month))
    )

    for m in range(max_months):
        due_date = origination_date + pd.DateOffset(months=m)

        if loan["loan_status"] == "Delinquent":
            delinquency_days = random.choices([0, 30, 60, 90], weights=[55, 25, 12, 8])[0]
        else:
            delinquency_days = random.choices([0, 30, 60], weights=[92, 6, 2])[0]

        payment_date = due_date + pd.Timedelta(days=delinquency_days)
        paid_amount = monthly_due if delinquency_days < 90 else round(monthly_due * random.uniform(0, 0.6), 2)

        rows.append({
            "loan_id": loan["loan_id"],
            "customer_id": loan["customer_id"],
            "payment_due_date": due_date.date(),
            "payment_date": payment_date.date(),
            "due_amount": round(monthly_due, 2),
            "paid_amount": round(paid_amount, 2),
            "delinquency_days": delinquency_days,
        })

df = pd.DataFrame(rows)

df.to_sql(
    "loan_payments",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=5000
)

print(f"Loaded {len(df)} loan payment rows into core.loan_payments")