import pandas as pd
from data_generator import engine

cases = pd.read_sql("""
SELECT case_id, customer_id
FROM core.cases
""", engine)

alerts = pd.read_sql("""
SELECT alert_id, customer_id
FROM core.alerts
""", engine)

rows = []

alerts_by_customer = alerts.groupby("customer_id")

for _, case in cases.iterrows():
    customer_id = case["customer_id"]

    if customer_id in alerts_by_customer.groups:
        customer_alerts = alerts_by_customer.get_group(customer_id)

        for _, alert in customer_alerts.head(3).iterrows():
            rows.append({
                "case_id": case["case_id"],
                "alert_id": alert["alert_id"]
            })

df = pd.DataFrame(rows)

df.to_sql(
    "case_alerts",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=1000
)

print(f"Loaded {len(df)} case-alert links.")