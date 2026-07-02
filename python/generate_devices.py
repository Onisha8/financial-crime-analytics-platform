import random
import pandas as pd
from data_generator import engine

random.seed(42)

customers = pd.read_sql(
    "SELECT customer_id, customer_since FROM core.customers",
    engine
)

device_types = ["iPhone", "Android", "Windows Laptop", "MacBook", "Tablet"]
operating_systems = {
    "iPhone": "iOS",
    "Android": "Android",
    "Windows Laptop": "Windows",
    "MacBook": "macOS",
    "Tablet": "iPadOS"
}

rows = []

for _, row in customers.iterrows():
    customer_id = row["customer_id"]

    # Most customers have 1 device, some have 2, few have 3
    n_devices = random.choices([1, 2, 3], weights=[70, 25, 5])[0]

    for _ in range(n_devices):
        device_type = random.choice(device_types)

        rows.append({
            "device_id": f"D{len(rows) + 1:09d}",
            "customer_id": customer_id,
            "device_type": device_type,
            "operating_system": operating_systems[device_type],
            "first_seen_date": row["customer_since"],
            "last_seen_date": None
        })

df = pd.DataFrame(rows)

df.to_sql(
    "devices",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=1000
)

print(f"Loaded {len(df)} devices into core.devices")