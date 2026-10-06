import random
import pandas as pd
from tqdm import tqdm

from data_generator import engine

random.seed(42)

N_TRANSACTIONS = 500_000

accounts = pd.read_sql("""
    SELECT account_id, customer_id, account_type
    FROM core.accounts
""", engine)

cards = pd.read_sql("""
    SELECT card_id, account_id, customer_id
    FROM core.cards
""", engine)

merchants = pd.read_sql("""
    SELECT merchant_id, merchant_category, merchant_country
    FROM core.merchants
""", engine)

beneficiaries = pd.read_sql("""
    SELECT beneficiary_id, customer_id, beneficiary_bank_country
    FROM core.beneficiaries
""", engine)

devices = pd.read_sql("""
    SELECT device_id, customer_id
    FROM core.devices
""", engine)

ips = pd.read_sql("""
    SELECT ip_id
    FROM core.ip_addresses
""", engine)

account_rows = accounts.to_dict("records")
merchant_rows = merchants.to_dict("records")
ip_ids = ips["ip_id"].tolist()

cards_by_customer = cards.groupby("customer_id").apply(lambda x: x.to_dict("records")).to_dict()
beneficiaries_by_customer = beneficiaries.groupby("customer_id").apply(lambda x: x.to_dict("records")).to_dict()
devices_by_customer = devices.groupby("customer_id").apply(lambda x: x.to_dict("records")).to_dict()

transaction_types = [
    "CARD_PURCHASE",
    "ACH_TRANSFER",
    "WIRE_TRANSFER",
    "ATM_WITHDRAWAL",
    "CASH_DEPOSIT",
    "BILL_PAYMENT",
    "ONLINE_TRANSFER"
]

rows = []

for i in tqdm(range(1, N_TRANSACTIONS + 1)):
    account = random.choice(account_rows)
    customer_id = account["customer_id"]
    account_type = account["account_type"]

    txn_type = random.choices(
        transaction_types,
        weights=[45, 15, 5, 8, 7, 10, 10]
    )[0]

    card_id = None
    merchant_id = None
    beneficiary_id = None
    device_id = None

    if txn_type == "CARD_PURCHASE":
        merchant = random.choice(merchant_rows)
        merchant_id = merchant["merchant_id"]

        customer_cards = cards_by_customer.get(customer_id, [])
        if customer_cards:
            card_id = random.choice(customer_cards)["card_id"]

        amount = round(random.uniform(5, 900), 2)
        channel = random.choice(["POS", "Online", "Mobile"])

    elif txn_type == "WIRE_TRANSFER":
        customer_bens = beneficiaries_by_customer.get(customer_id, [])
        if customer_bens:
            ben = random.choice(customer_bens)
            beneficiary_id = ben["beneficiary_id"]
        amount = round(random.uniform(500, 50000), 2)
        channel = random.choice(["Online", "Branch"])

    elif txn_type == "CASH_DEPOSIT":
        amount = round(random.uniform(100, 12000), 2)
        channel = random.choice(["Branch", "ATM"])

    elif txn_type == "ATM_WITHDRAWAL":
        amount = round(random.uniform(20, 1000), 2)
        channel = "ATM"

    elif txn_type == "ACH_TRANSFER":
        amount = round(random.uniform(100, 15000), 2)
        channel = random.choice(["Online", "Mobile"])

    elif txn_type == "BILL_PAYMENT":
        amount = round(random.uniform(40, 2500), 2)
        channel = random.choice(["Online", "Mobile"])

    else:
        amount = round(random.uniform(50, 20000), 2)
        channel = random.choice(["Online", "Mobile"])

    customer_devices = devices_by_customer.get(customer_id, [])
    if channel in ["Online", "Mobile"] and customer_devices:
        device_id = random.choice(customer_devices)["device_id"]

    txn_timestamp = pd.Timestamp("2023-01-01") + pd.Timedelta(
        days=random.randint(0, 1095),
        hours=random.randint(0, 23),
        minutes=random.randint(0, 59),
        seconds=random.randint(0, 59)
    )

    rows.append({
        "transaction_id": f"T{i:012d}",
        "account_id": account["account_id"],
        "customer_id": customer_id,
        "card_id": card_id,
        "merchant_id": merchant_id,
        "beneficiary_id": beneficiary_id,
        "device_id": device_id,
        "ip_id": random.choice(ip_ids),
        "transaction_timestamp": txn_timestamp,
        "transaction_type": txn_type,
        "channel": channel,
        "amount": amount,
        "currency": "USD",
        "origin_country": "US",
        "destination_country": "US",
        "transaction_status": "Posted",
    })

df = pd.DataFrame(rows)

df.to_sql(
    "transactions",
    engine,
    schema="core",
    if_exists="append",
    index=False,
    method="multi",
    chunksize=5000
)

print(f"Loaded {len(df)} transactions into core.transactions")