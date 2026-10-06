from data_generator import engine
from sqlalchemy import text

branches = [
    ("BR001", "Tampa Main Branch", "Tampa", "FL", "US"),
    ("BR002", "New York Midtown Branch", "New York", "NY", "US"),
    ("BR003", "Jersey City Branch", "Jersey City", "NJ", "US"),
    ("BR004", "Dallas Central Branch", "Dallas", "TX", "US"),
    ("BR005", "Chicago Loop Branch", "Chicago", "IL", "US"),
]

with engine.begin() as conn:
    for branch in branches:
        conn.execute(
            text("""
                INSERT INTO core.branches
                (branch_id, branch_name, city, state, country)
                VALUES (:branch_id, :branch_name, :city, :state, :country)
                ON CONFLICT (branch_id) DO NOTHING;
            """),
            {
                "branch_id": branch[0],
                "branch_name": branch[1],
                "city": branch[2],
                "state": branch[3],
                "country": branch[4],
            }
        )

print("Branch seed data loaded successfully.")