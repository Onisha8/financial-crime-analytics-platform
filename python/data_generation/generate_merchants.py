import random
import pandas as pd
from faker import Faker

from data_generator import engine

fake = Faker("en_US")
random.seed(42)
Faker.seed(42)

N_MERCHANTS = 2000

merchant_categories = [
    "Grocery", "Gas", "Restaurant", "Retail", "E-commerce", "Travel",
    "Utilities", "Healthcare", "Electronics", "Luxury Goods",
    "Money Services", "Crypto Exchange", "Gaming", "Jewelry", "Pawn Shop"
]

countries = ["US", "CA", "MX", "GB", "IN", "AE", "CN", "TR", "PA", "KY", "RU", "NG"]
high_risk_countries = {"AE", "TR", "PA", "KY", "RU", "NG"}
high_risk_categories = {"Money Services", "Crypto Exchange", "Gaming", "Jewelry", "Pawn Shop"}

rows = []

for i in range(1, N_MERCHANTS + 1):
    category = random.choice(merchant_categories)
    country = random.choices(
        countries,
        weights=[75, 4, 4, 3, 3, 2, 2, 2, 1, 1, 1, 2]
    )[0]

    if category in high_risk_categories or country in high_risk_countries:
        risk = random.choices(["Medium", "High"], weights=[55, 45])[0]
    else:
        risk = random.choices(["Low", "Medium"], weights=[80, 20])[0]

    rows.append({
        "merchant_id": f"M{i:08d}",
        "merchant_name": fake.company(),
        "merchant_category": category,
        "merchant_country": country,
        "merchant_risk_rating": risk,
    })

df = pd.DataFrame(rows)

df.to_sql(
    "merchants",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=1000
)

print(f"Loaded {len(df)} merchants into core.merchants")