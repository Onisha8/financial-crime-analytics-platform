import random
import pandas as pd

from data_generator import engine

random.seed(42)


RULE_CONTEXT = {
    "TM001": "structuring activity involving repeated transactions near monitoring thresholds",
    "TM002": "transactions involving elevated-risk geographic exposure",
    "TM003": "significant activity following an extended period of account dormancy",
    "TM004": "rapid movement of funds inconsistent with expected account behavior",
    "TM005": "shared-device activity linking multiple customer relationships",
    "TM006": "large wire-transfer activity requiring enhanced review",
    "TM007": "repeated round-dollar transaction patterns",
    "TM008": "activity involving higher-risk merchant categories",
}


def load_cases_without_sars() -> pd.DataFrame:
    """
    Return cases that do not already have a SAR. This makes the script incremental.
    """
    return pd.read_sql(
        """
        SELECT
            c.case_id,
            c.customer_id,
            c.investigation_id,
            c.case_open_date,
            c.case_close_date,
            c.case_status,
            c.case_type,
            c.risk_rating,
            i.alert_id,
            i.disposition,
            a.rule_id,
            a.alert_score
        FROM core.cases c
        LEFT JOIN core.sar_reports s
            ON c.case_id = s.case_id
        LEFT JOIN core.investigations i
            ON c.investigation_id = i.investigation_id
        LEFT JOIN core.alerts a
            ON i.alert_id = a.alert_id
        WHERE s.sar_id IS NULL
        ORDER BY c.case_id;
        """,
        engine,
    )


def get_max_sar_number() -> int:
    result = pd.read_sql(
        """
        SELECT COALESCE(
            MAX(
                CAST(
                    REPLACE(sar_id, 'SAR', '')
                    AS BIGINT
                )
            ),
            0
        ) AS max_sar
        FROM core.sar_reports;
        """,
        engine,
    )

    return int(result.iloc[0]["max_sar"])


def filing_probability(risk_rating, disposition, alert_score) -> float:
    """
    Estimate SAR filing probability using case risk, disposition, and alert score.
    """
    probability = {
        "Critical": 0.82,
        "High": 0.52,
        "Medium": 0.12,
    }.get(str(risk_rating), 0.08)

    if disposition == "Escalated":
        probability += 0.08
    elif disposition == "Monitoring Required":
        probability -= 0.02

    score = float(alert_score) if pd.notna(alert_score) else 0.0

    if score >= 90:
        probability += 0.05
    elif score >= 80:
        probability += 0.02

    return max(0.01, min(probability, 0.95))


def derive_filing_date(case_row):
    open_date = (
        pd.Timestamp(case_row["case_open_date"])
        if pd.notna(case_row["case_open_date"])
        else pd.Timestamp("2026-01-01")
    )

    if pd.notna(case_row["case_close_date"]):
        reference = pd.Timestamp(case_row["case_close_date"])
    else:
        reference = open_date + pd.Timedelta(
            days=random.randint(10, 35)
        )

    return (
        reference
        + pd.Timedelta(days=random.randint(0, 10))
    ).date()


def build_narrative(case_row) -> str:
    rule_id = case_row["rule_id"]

    activity = RULE_CONTEXT.get(
        rule_id,
        "unusual transaction activity identified through transaction monitoring",
    )

    risk_rating = case_row["risk_rating"]
    case_type = case_row["case_type"]
    customer_id = case_row["customer_id"]

    return (
        f"Case {case_row['case_id']} was opened for customer "
        f"{customer_id} following {activity}. "
        f"The review was classified as {case_type} with a "
        f"{risk_rating} risk rating. Transaction history, customer "
        f"due-diligence information, and relevant alert activity were "
        f"reviewed. The observed activity was determined to warrant "
        f"regulatory reporting based on the overall pattern and risk indicators."
    )


def build_sar_rows(cases: pd.DataFrame, starting_number: int) -> pd.DataFrame:
    rows = []

    for _, case in cases.iterrows():
        probability = filing_probability(
            case["risk_rating"],
            case["disposition"],
            case["alert_score"],
        )

        if random.random() >= probability:
            continue

        sar_number = starting_number + len(rows) + 1

        rows.append(
            {
                "sar_id": f"SAR{sar_number:08d}",
                "case_id": case["case_id"],
                "customer_id": case["customer_id"],
                "filing_date": derive_filing_date(case),
                "sar_status": random.choices(
                    ["Filed", "Under Review"],
                    weights=[92, 8],
                    k=1,
                )[0],
                "narrative": build_narrative(case),
            }
        )

    return pd.DataFrame(rows)


def load_sars(sars: pd.DataFrame):
    if sars.empty:
        print("No new SARs generated.")
        return

    sars.to_sql(
        "sar_reports",
        engine,
        schema="core",
        if_exists="append",
        index=False,
        method="multi",
        chunksize=2000,
    )

    print(
        f"Loaded {len(sars):,} new SAR reports "
        "into core.sar_reports."
    )


def print_validation():
    total = pd.read_sql(
        """
        SELECT
            COUNT(*) AS total_sars,
            COUNT(DISTINCT case_id) AS cases_with_sars,
            COUNT(DISTINCT customer_id) AS customers_with_sars
        FROM core.sar_reports;
        """,
        engine,
    )

    by_status = pd.read_sql(
        """
        SELECT
            sar_status,
            COUNT(*) AS sar_count
        FROM core.sar_reports
        GROUP BY sar_status
        ORDER BY sar_count DESC;
        """,
        engine,
    )

    by_risk = pd.read_sql(
        """
        SELECT
            c.risk_rating,
            COUNT(*) AS sar_count
        FROM core.sar_reports s
        JOIN core.cases c
            ON s.case_id = c.case_id
        GROUP BY c.risk_rating
        ORDER BY sar_count DESC;
        """,
        engine,
    )

    print("\nSAR validation:")
    print(total.to_string(index=False))

    print("\nSAR status distribution:")
    print(by_status.to_string(index=False))

    print("\nSAR distribution by case risk:")
    print(by_risk.to_string(index=False))


def main():
    cases = load_cases_without_sars()

    if cases.empty:
        print("Every existing case has already been evaluated for SAR generation.")
        print_validation()
        return

    max_sar_number = get_max_sar_number()

    sars = build_sar_rows(
        cases,
        max_sar_number,
    )

    load_sars(sars)
    print_validation()


if __name__ == "__main__":
    main()
