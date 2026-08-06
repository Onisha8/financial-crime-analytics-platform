import random
import pandas as pd
from data_generator import engine

random.seed(42)

cases = pd.read_sql("""
    SELECT
        c.case_id,
        c.customer_id,
        c.risk_rating,
        c.case_type
    FROM core.cases c
    LEFT JOIN core.sar_reports s
        ON c.case_id = s.case_id
    WHERE s.sar_id IS NULL
""", engine)

max_sar = pd.read_sql("""
    SELECT COALESCE(
        MAX(CAST(REPLACE(sar_id, 'SAR', '') AS BIGINT)),
        0
    ) AS max_sar
    FROM core.sar_reports
""", engine)

max_sar = int(max_sar.iloc[0]["max_sar"])

rows = []

for _, case in cases.iterrows():

    # Only High and Critical risk cases have a chance of becoming SARs
    if case["risk_rating"] == "Critical":
        probability = 0.90
    elif case["risk_rating"] == "High":
        probability = 0.55
    else:
        probability = 0.10

    if random.random() < probability:

        rows.append({
            "sar_id": f"SAR{max_sar + len(rows) + 1:08d}",
            "case_id": case["case_id"],
            "customer_id": case["customer_id"],
            "filing_date": pd.Timestamp("2026-07-15") + pd.Timedelta(days=random.randint(0,60)),
            "sar_status": random.choices(
                ["Filed", "Under Review"],
                weights=[90,10]
            )[0],
            "narrative": (
                f"Potential suspicious activity identified from "
                f"{case['case_type']} requiring regulatory review."
            )
        })

df = pd.DataFrame(rows)

df.to_sql(
    "sar_reports",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=1000
)

print(f"Loaded {len(df)} SAR reports.")