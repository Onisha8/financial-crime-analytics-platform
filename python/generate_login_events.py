import random
import pandas as pd
from data_generator import engine

random.seed(42)

devices = pd.read_sql("""
    SELECT device_id, customer_id, first_seen_date
    FROM core.devices
""", engine)

ips = pd.read_sql("""
    SELECT ip_id
    FROM core.ip_addresses
""", engine)

ip_ids = ips["ip_id"].tolist()

rows = []

for _, row in devices.iterrows():
    customer_id = row["customer_id"]
    device_id = row["device_id"]

    # Most devices have repeated login events
    n_logins = random.randint(5, 40)

    for _ in range(n_logins):
        login_timestamp = pd.Timestamp("2023-01-01") + pd.Timedelta(
            days=random.randint(0, 1095),
            hours=random.randint(0, 23),
            minutes=random.randint(0, 59)
        )

        rows.append({
            "customer_id": customer_id,
            "device_id": device_id,
            "ip_id": random.choice(ip_ids),
            "login_timestamp": login_timestamp,
            "login_success": random.choices([True, False], weights=[96, 4])[0],
            "mfa_used": random.choices([True, False], weights=[82, 18])[0],
        })

df = pd.DataFrame(rows)

df.to_sql(
    "login_events",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=5000
)

print(f"Loaded {len(df)} login events into core.login_events")