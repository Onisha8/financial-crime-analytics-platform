import random
import pandas as pd
from faker import Faker

from data_generator import engine

fake = Faker("en_US")
random.seed(42)
Faker.seed(42)

customers = pd.read_sql(
    "SELECT customer_id FROM core.customers",
    engine
)

countries = ["US", "CA", "MX", "GB", "IN", "AE", "CN", "TR", "PA", "KY", "RU", "NG"]
relationships = ["Family", "Friend", "Business", "Vendor", "Employee", "Other"]

rows = []

for _, row in customers.iterrows():
    customer_id = row["customer_id"]

    # Not every customer has beneficiaries
    if random.random() < 0.55:
        n_beneficiaries = random.choices([1, 2, 3], weights=[70, 25, 5])[0]

        for _ in range(n_beneficiaries):
            rows.append({
                "beneficiary_id": f"B{len(rows) + 1:09d}",
                "customer_id": customer_id,
                "beneficiary_name": fake.name(),
                "beneficiary_bank_country": random.choices(
                    countries,
                    weights=[75, 4, 4, 3, 3, 2, 2, 2, 1, 1, 1, 2]
                )[0],
                "relationship_type": random.choice(relationships)
            })

df = pd.DataFrame(rows)

df.to_sql(
    "beneficiaries",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=1000
)

print(f"Loaded {len(df)} beneficiaries into core.beneficiaries")