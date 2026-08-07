import random
import pandas as pd

from data_generator import engine

random.seed(42)

CASE_ELIGIBLE_DISPOSITIONS = {"Escalated", "Monitoring Required"}

CASE_TYPE_BY_RULE = {
    "TM001": "Structuring Investigation",
    "TM002": "High-Risk Geography Investigation",
    "TM003": "Dormant Account Investigation",
    "TM004": "Rapid Movement of Funds Investigation",
    "TM005": "Shared Device Investigation",
    "TM006": "Large Wire Investigation",
    "TM007": "Round Dollar Pattern Investigation",
    "TM008": "High-Risk Merchant Investigation",
}


def load_eligible_investigations() -> pd.DataFrame:
    """
    Return only eligible investigations that do not already have a case.
    This keeps the generator incremental and safe to rerun.
    """
    return pd.read_sql(
        """
        SELECT
            i.investigation_id,
            i.alert_id,
            i.disposition,
            i.investigation_start,
            i.investigation_end,
            a.customer_id,
            a.rule_id,
            a.alert_score,
            a.priority
        FROM core.investigations i
        JOIN core.alerts a
            ON i.alert_id = a.alert_id
        LEFT JOIN core.cases c
            ON i.investigation_id = c.investigation_id
        WHERE c.case_id IS NULL
          AND i.disposition IN ('Escalated', 'Monitoring Required')
        ORDER BY i.investigation_id;
        """,
        engine,
    )


def get_max_case_number() -> int:
    result = pd.read_sql(
        """
        SELECT COALESCE(
            MAX(
                CAST(
                    REPLACE(case_id, 'CASE', '')
                    AS BIGINT
                )
            ),
            0
        ) AS max_case
        FROM core.cases;
        """,
        engine,
    )
    return int(result.iloc[0]["max_case"])


def derive_risk_rating(alert_score, priority, disposition) -> str:
    """
    Derive case risk using the upstream alert information instead of assigning
    it completely at random.
    """
    score = float(alert_score) if pd.notna(alert_score) else 0.0
    priority = str(priority or "")
    disposition = str(disposition or "")

    risk_points = 0

    if score >= 90:
        risk_points += 3
    elif score >= 80:
        risk_points += 2
    elif score >= 70:
        risk_points += 1

    if priority.lower() == "high":
        risk_points += 2
    elif priority.lower() == "medium":
        risk_points += 1

    if disposition == "Escalated":
        risk_points += 2
    elif disposition == "Monitoring Required":
        risk_points += 1

    if risk_points >= 6:
        return "Critical"
    if risk_points >= 4:
        return "High"
    return "Medium"


def derive_case_status(disposition) -> str:
    """
    Escalated investigations are slightly more likely to remain open.
    """
    if disposition == "Escalated":
        return random.choices(["Open", "Closed"], weights=[35, 65], k=1)[0]

    return random.choices(["Open", "Closed"], weights=[20, 80], k=1)[0]


def safe_timestamp(value, fallback):
    if pd.isna(value):
        return pd.Timestamp(fallback)
    return pd.Timestamp(value)


def build_case_rows(investigations: pd.DataFrame, starting_number: int) -> pd.DataFrame:
    rows = []

    for _, inv in investigations.iterrows():
        case_number = starting_number + len(rows) + 1

        investigation_start = safe_timestamp(
            inv["investigation_start"],
            "2026-01-01",
        )

        investigation_end = (
            pd.Timestamp(inv["investigation_end"])
            if pd.notna(inv["investigation_end"])
            else None
        )

        # Open a case on or shortly after the investigation begins.
        case_open_ts = investigation_start + pd.Timedelta(
            days=random.randint(0, 3)
        )

        case_status = derive_case_status(inv["disposition"])

        if case_status == "Closed":
            earliest_close = case_open_ts + pd.Timedelta(days=1)

            if investigation_end is not None and investigation_end >= earliest_close:
                latest_close = investigation_end + pd.Timedelta(days=random.randint(0, 5))
            else:
                latest_close = earliest_close + pd.Timedelta(days=random.randint(2, 20))

            close_span = max(
                1,
                (latest_close.normalize() - earliest_close.normalize()).days,
            )

            case_close_ts = earliest_close + pd.Timedelta(
                days=random.randint(0, close_span)
            )
            case_close_date = case_close_ts.date()
        else:
            case_close_date = None

        rule_id = inv["rule_id"]
        case_type = CASE_TYPE_BY_RULE.get(
            rule_id,
            "Transaction Monitoring Investigation",
        )

        rows.append(
            {
                "case_id": f"CASE{case_number:08d}",
                "customer_id": inv["customer_id"],
                "case_open_date": case_open_ts.date(),
                "case_close_date": case_close_date,
                "case_status": case_status,
                "case_type": case_type,
                "risk_rating": derive_risk_rating(
                    inv["alert_score"],
                    inv["priority"],
                    inv["disposition"],
                ),
                "investigation_id": inv["investigation_id"],
            }
        )

    return pd.DataFrame(rows)


def load_cases(cases: pd.DataFrame):
    if cases.empty:
        print("No new eligible investigations require cases.")
        return

    cases.to_sql(
        "cases",
        engine,
        schema="core",
        if_exists="append",
        index=False,
        method="multi",
        chunksize=2000,
    )

    print(f"Loaded {len(cases):,} new cases into core.cases.")


def print_validation():
    validation = pd.read_sql(
        """
        SELECT
            COUNT(*) AS total_cases,
            COUNT(investigation_id) AS cases_with_investigation,
            COUNT(*) - COUNT(investigation_id) AS legacy_cases_without_investigation
        FROM core.cases;
        """,
        engine,
    )

    by_status = pd.read_sql(
        """
        SELECT
            case_status,
            risk_rating,
            COUNT(*) AS case_count
        FROM core.cases
        GROUP BY case_status, risk_rating
        ORDER BY case_status, risk_rating;
        """,
        engine,
    )

    print("\nCase linkage validation:")
    print(validation.to_string(index=False))

    print("\nCase distribution:")
    print(by_status.to_string(index=False))


def main():
    investigations = load_eligible_investigations()

    if investigations.empty:
        print("No new eligible investigations found.")
        print_validation()
        return

    max_case_number = get_max_case_number()

    cases = build_case_rows(
        investigations,
        max_case_number,
    )

    load_cases(cases)
    print_validation()


if __name__ == "__main__":
    main()