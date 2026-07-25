import pandas as pd
from data_generator import engine

queries = {
    "Transaction Summary": """
        SELECT
            COUNT(*) AS total_transactions,
            SUM(amount) AS total_amount,
            AVG(amount) AS average_amount
        FROM core.transactions;
    """,

    "Alert Summary": """
        SELECT
            r.rule_name,
            COUNT(*) AS alert_count,
            ROUND(AVG(a.alert_score), 2) AS average_alert_score
        FROM core.alerts a
        JOIN reference.alert_rules r
            ON a.rule_id = r.rule_id
        GROUP BY r.rule_name
        ORDER BY alert_count DESC;
    """,

    "Investigation Outcomes": """
        SELECT
            disposition,
            COUNT(*) AS investigation_count
        FROM core.investigations
        GROUP BY disposition
        ORDER BY investigation_count DESC;
    """,

    "Alert Funnel": """
        SELECT
            (SELECT COUNT(*) FROM core.alerts) AS alerts,
            (SELECT COUNT(*) FROM core.investigations) AS investigations,
            (SELECT COUNT(*) FROM core.cases) AS cases,
            (SELECT COUNT(*) FROM core.sar_reports) AS sar_reports;
    """
}

for title, query in queries.items():
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)

    df = pd.read_sql(query, engine)
    print(df)