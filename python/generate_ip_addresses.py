import random
import pandas as pd
from faker import Faker

from data_generator import engine

fake = Faker("en_US")
random.seed(42)
Faker.seed(42)

N_IPS = 20000

countries = ["US", "CA", "MX", "GB", "IN", "AE", "CN", "TR", "PA", "KY", "RU", "NG"]
high_risk_countries = {"AE", "TR", "PA", "KY", "RU", "NG"}

rows = []

for i in range(1, N_IPS + 1):
    country = random.choices(
        countries,
        weights=[78, 4, 3, 3, 3, 2, 2, 1.5, 1, 1, 0.8, 0.7]
    )[0]

    if country in high_risk_countries:
        risk = random.choices(["Medium", "High"], weights=[45, 55])[0]
    else:
        risk = random.choices(["Low", "Medium"], weights=[85, 15])[0]

    rows.append({
        "ip_address": fake.ipv4_public(),
        "ip_country": country,
        "ip_city": fake.city(),
        "risk_rating": risk,
    })

df = pd.DataFrame(rows)

df.to_sql(
    "ip_addresses",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=1000
)

print(f"Loaded {len(df)} IP addresses into core.ip_addresses")