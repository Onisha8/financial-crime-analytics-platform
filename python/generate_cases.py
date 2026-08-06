import random
import pandas as pd
from data_generator import engine

random.seed(42)

investigations = pd.read_sql("""
SELECT
    i.investigation_id,
    i.alert_id,
    i.disposition
FROM core.investigations i
LEFT JOIN core.cases c
    ON i.investigation_id = c.investigation_id
WHERE c.case_id IS NULL
""", engine)

alerts = pd.read_sql("""
SELECT
    alert_id,
    customer_id
FROM core.alerts
""", engine)

alerts = alerts.set_index("alert_id")

max_case = pd.read_sql("""
SELECT COALESCE(
    MAX(
        CAST(REPLACE(case_id,'CASE','') AS BIGINT)
    ),
0) AS max_case
FROM core.cases;
""", engine)

max_case = int(max_case.iloc[0]["max_case"])

rows = []

for _, inv in investigations.iterrows():

    # Only some investigations become cases
    if inv["disposition"] in ["Escalated", "Monitoring Required"]:

        customer_id = alerts.loc[inv["alert_id"], "customer_id"]

        rows.append({
            "investigation_id": inv["investigation_id"],
            "case_id": f"CASE{max_case + len(rows) + 1:08d}",
            "customer_id": customer_id,
            "case_open_date": pd.Timestamp("2026-01-01") + pd.Timedelta(days=random.randint(0,180)),
            "case_close_date": None if random.random() < 0.30 else pd.Timestamp("2026-07-01"),
            "case_status": random.choices(
                ["Open", "Closed"],
                weights=[30,70]
            )[0],
            "case_type": random.choice([
                "AML Investigation",
                "Fraud Investigation",
                "Transaction Monitoring"
            ]),
            "risk_rating": random.choices(
                ["Medium","High","Critical"],
                weights=[45,40,15]
            )[0]
        })

df = pd.DataFrame(rows)

df.to_sql(
    "cases",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=1000
)

print(f"Loaded {len(df)} cases.")