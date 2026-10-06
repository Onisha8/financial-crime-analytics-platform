import random
from datetime import date, timedelta

import pandas as pd
from faker import Faker

from data_generator import engine

fake = Faker("en_US")
random.seed(42)
Faker.seed(42)

N_CUSTOMERS = 10000

states = ["FL", "NY", "NJ", "TX", "IL", "CA", "GA", "NC", "PA", "AZ"]
occupations = [
    "Software Engineer", "Data Analyst", "Consultant", "Teacher", "Nurse",
    "Small Business Owner", "Restaurant Owner", "Student", "Driver",
    "Accountant", "Retail Associate", "Construction Worker"
]
income_bands = ["<30K", "30K-50K", "50K-75K", "75K-100K", "100K-150K", "150K+"]
kyc_ratings = ["Low", "Medium", "High"]
segments = ["Mass Retail", "Emerging Affluent", "Affluent", "Small Business"]

rows = []

for i in range(1, N_CUSTOMERS + 1):
    customer_id = f"C{i:08d}"
    dob = fake.date_of_birth(minimum_age=18, maximum_age=75)

    rows.append({
        "customer_id": customer_id,
        "customer_since": fake.date_between(start_date="-10y", end_date="-30d"),
        "date_of_birth": dob,
        "state": random.choice(states),
        "occupation": random.choice(occupations),
        "income_band": random.choices(income_bands, weights=[10, 18, 24, 22, 18, 8])[0],
        "kyc_risk_rating": random.choices(kyc_ratings, weights=[75, 20, 5])[0],
        "politically_exposed_person_flag": random.choices([False, True], weights=[985, 15])[0],
        "customer_segment": random.choices(segments, weights=[55, 25, 12, 8])[0],
    })

df = pd.DataFrame(rows)

df.to_sql(
    "customers",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=1000
)

print(f"Loaded {len(df)} customers into core.customers")