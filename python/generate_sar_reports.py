import random
import pandas as pd
from data_generator import engine

random.seed(42)

cases = pd.read_sql("""
SELECT
    case_id,
    customer_id,
    risk_rating,
    case_type
FROM core.cases
""", engine)

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
            "sar_id": f"SAR{len(rows)+1:08d}",
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