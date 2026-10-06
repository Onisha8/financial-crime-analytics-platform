import random
import pandas as pd
from faker import Faker

from data_generator import engine

fake = Faker("en_US")
random.seed(42)
Faker.seed(42)

customers = pd.read_sql(
    "SELECT customer_id, state, occupation, income_band, kyc_risk_rating FROM core.customers",
    engine
)

source_of_funds = ["Salary", "Business Income", "Investments", "Family Support", "Rental Income", "Savings"]
source_of_wealth = ["Employment", "Business Ownership", "Investments", "Inheritance", "Real Estate"]
phone_types = ["Mobile", "Home", "Work"]

kyc_rows = []
address_rows = []
phone_rows = []
email_rows = []

income_map = {
    "<30K": 25000,
    "30K-50K": 40000,
    "50K-75K": 62500,
    "75K-100K": 87500,
    "100K-150K": 125000,
    "150K+": 180000,
}

for _, row in customers.iterrows():
    customer_id = row["customer_id"]
    annual_income = income_map.get(row["income_band"], 60000)
    expected_monthly_income = annual_income / 12

    kyc_rows.append({
        "customer_id": customer_id,
        "kyc_level": random.choices(["Standard", "Enhanced"], weights=[85, 15])[0],
        "kyc_status": random.choices(["Approved", "Pending Review", "Expired"], weights=[92, 5, 3])[0],
        "source_of_funds": random.choice(source_of_funds),
        "source_of_wealth": random.choice(source_of_wealth),
        "expected_monthly_income": round(expected_monthly_income, 2),
        "expected_monthly_txn_volume": round(expected_monthly_income * random.uniform(0.6, 2.2), 2),
        "occupation_risk_rating": random.choices(["Low", "Medium", "High"], weights=[70, 24, 6])[0],
        "last_review_date": fake.date_between(start_date="-2y", end_date="-30d"),
        "next_review_date": fake.date_between(start_date="+30d", end_date="+2y"),
    })

    address_rows.append({
        "customer_id": customer_id,
        "address_type": "Primary",
        "address_line_1": fake.street_address(),
        "city": fake.city(),
        "state": row["state"],
        "country": "US",
        "postal_code": fake.postcode(),
        "effective_from": fake.date_between(start_date="-8y", end_date="-30d"),
        "effective_to": None,
    })

    phone_rows.append({
        "customer_id": customer_id,
        "phone_number": fake.phone_number(),
        "phone_type": random.choice(phone_types),
        "is_primary": True,
    })

    email_rows.append({
        "customer_id": customer_id,
        "email_address": fake.email(),
        "is_primary": True,
    })

pd.DataFrame(kyc_rows).to_sql(
    "customer_kyc", engine, schema="core", if_exists="append",
    index=False, method="multi", chunksize=1000
)

pd.DataFrame(address_rows).to_sql(
    "customer_addresses", engine, schema="core", if_exists="append",
    index=False, method="multi", chunksize=1000
)

pd.DataFrame(phone_rows).to_sql(
    "customer_phones", engine, schema="core", if_exists="append",
    index=False, method="multi", chunksize=1000
)

pd.DataFrame(email_rows).to_sql(
    "customer_emails", engine, schema="core", if_exists="append",
    index=False, method="multi", chunksize=1000
)

print("Loaded customer KYC, address, phone, and email details.")