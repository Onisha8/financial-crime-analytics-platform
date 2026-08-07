import random
import pandas as pd
from data_generator import engine

random.seed(42)

alerts = pd.read_sql("""
    SELECT a.alert_id
    FROM core.alerts a
    LEFT JOIN core.investigations i
        ON a.alert_id = i.alert_id
    WHERE i.investigation_id IS NULL
""", engine)

employees = pd.read_sql("""
SELECT employee_id
FROM core.employees
WHERE department = 'Financial Crime Operations'
   OR department = 'Financial Crime Analytics'
""", engine)

employee_ids = employees["employee_id"].tolist()

max_id = pd.read_sql("""
SELECT
    COALESCE(
        MAX(
            CAST(REPLACE(investigation_id,'INV','') AS BIGINT)
        ),
        0
    ) AS max_id
FROM core.investigations;
""", engine)

max_id = int(max_id.iloc[0]["max_id"])

rows = []

for _, alert in alerts.iterrows():

    disposition = random.choices(
        [
            "False Positive",
            "Escalated",
            "Monitoring Required",
            "Closed - No Issue"
        ],
        weights=[45, 20, 15, 20]
    )[0]

    investigation_start = (
        pd.Timestamp("2026-01-01")
        + pd.Timedelta(days=random.randint(0, 180))
    )

    investigation_duration = random.randint(1, 30)

    investigation_end = (
        investigation_start
        + pd.Timedelta(days=investigation_duration)
    )

    rows.append({
        "investigation_id": f"INV{max_id + len(rows) + 1:09d}",
        "alert_id": alert["alert_id"],
        "investigator_id": None,
        "investigation_start": investigation_start,
        "investigation_end": investigation_end,
        "disposition": disposition,
        "notes": f"Investigation completed with disposition: {disposition}"
    })

df = pd.DataFrame(rows)

df.to_sql(
    "investigations",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=1000
)

print(f"Loaded {len(df)} investigations.")