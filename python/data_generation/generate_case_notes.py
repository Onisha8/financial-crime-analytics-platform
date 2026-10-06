import random
import pandas as pd
from sqlalchemy import text

from data_generator import engine

random.seed(42)

NOTE_TEMPLATES = {
    "OPENED": [
        "Case opened following escalation from transaction monitoring review.",
        "Case initiated for enhanced review of identified suspicious activity.",
        "Investigation escalated to case management for additional analysis.",
    ],
    "CUSTOMER_REVIEW": [
        "Customer profile, KYC information, and account history reviewed.",
        "Reviewed customer occupation, expected activity, KYC risk, and account tenure.",
        "Customer due-diligence profile reviewed against observed transaction behavior.",
    ],
    "TRANSACTION_REVIEW": [
        "Transaction history reviewed for unusual value, frequency, and behavioral changes.",
        "Reviewed recent transaction activity and compared it with the customer's historical pattern.",
        "Transaction pattern analysis completed for the relevant monitoring period.",
    ],
    "RULE_REVIEW": [
        "Reviewed the transaction monitoring scenario that generated the originating alert.",
        "Alert rationale and triggering rule parameters reviewed as part of case analysis.",
        "Monitoring rule output reviewed for consistency with the observed activity.",
    ],
    "KYC_REVIEW": [
        "KYC information reviewed for source of funds, source of wealth, and expected activity.",
        "Customer KYC profile compared with observed account activity.",
        "Due-diligence information reviewed for potential inconsistencies with transaction behavior.",
    ],
    "DEVICE_REVIEW": [
        "Device and digital banking activity reviewed for shared-device or access anomalies.",
        "Digital access history reviewed for device linkage and unusual login behavior.",
        "Device information reviewed to identify potential links with other customers.",
    ],
    "GEOGRAPHY_REVIEW": [
        "Geographic exposure reviewed for transactions involving elevated-risk jurisdictions.",
        "Origin and destination countries reviewed against geographic risk indicators.",
        "International transaction activity reviewed for unusual geographic exposure.",
    ],
    "MERCHANT_REVIEW": [
        "Merchant activity reviewed for elevated-risk categories and unusual spending behavior.",
        "Transactions involving higher-risk merchant categories reviewed in detail.",
        "Merchant exposure reviewed against the customer's normal transaction profile.",
    ],
    "ESCALATION": [
        "Case findings support continued escalation and enhanced review.",
        "Observed activity warrants additional financial-crime review.",
        "Case retained for further review based on identified risk indicators.",
    ],
    "CLOSURE": [
        "Case review completed and documented prior to closure.",
        "Investigation findings documented and case closed.",
        "Case closed after completion of required review and documentation.",
    ],
}


def ensure_case_notes_table():
    with engine.begin() as conn:
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS core.case_notes (
                    note_id BIGSERIAL PRIMARY KEY,
                    case_id VARCHAR(30) NOT NULL,
                    investigation_id VARCHAR(30),
                    author_employee_id VARCHAR(20),
                    note_timestamp TIMESTAMP NOT NULL,
                    note_type VARCHAR(50) NOT NULL,
                    note_text TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

                    CONSTRAINT fk_case_notes_case
                        FOREIGN KEY (case_id)
                        REFERENCES core.cases(case_id),

                    CONSTRAINT fk_case_notes_investigation
                        FOREIGN KEY (investigation_id)
                        REFERENCES core.investigations(investigation_id),

                    CONSTRAINT fk_case_notes_employee
                        FOREIGN KEY (author_employee_id)
                        REFERENCES core.employees(employee_id)
                );
                """
            )
        )

        conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_case_notes_case
                ON core.case_notes(case_id);
                """
            )
        )

        conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_case_notes_investigation
                ON core.case_notes(investigation_id);
                """
            )
        )

        conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_case_notes_timestamp
                ON core.case_notes(note_timestamp);
                """
            )
        )


def load_cases_without_notes() -> pd.DataFrame:
    """
    Generate notes only for cases that currently have none, making the script
    safe to rerun.
    """
    return pd.read_sql(
        """
        SELECT
            c.case_id,
            c.investigation_id,
            c.case_open_date,
            c.case_close_date,
            c.case_status,
            c.case_type,
            c.risk_rating,
            i.investigator_id,
            a.rule_id
        FROM core.cases c
        LEFT JOIN core.investigations i
            ON c.investigation_id = i.investigation_id
        LEFT JOIN core.alerts a
            ON i.alert_id = a.alert_id
        LEFT JOIN core.case_notes n
            ON c.case_id = n.case_id
        WHERE n.note_id IS NULL
        ORDER BY c.case_id;
        """,
        engine,
    )


def note_sequence(rule_id, case_status, risk_rating):
    sequence = [
        "OPENED",
        "CUSTOMER_REVIEW",
        "TRANSACTION_REVIEW",
        "RULE_REVIEW",
    ]

    if rule_id in {"TM002"}:
        sequence.append("GEOGRAPHY_REVIEW")

    if rule_id in {"TM005"}:
        sequence.append("DEVICE_REVIEW")

    if rule_id in {"TM008"}:
        sequence.append("MERCHANT_REVIEW")

    if risk_rating in {"High", "Critical"}:
        sequence.append("KYC_REVIEW")

    if case_status == "Open":
        sequence.append("ESCALATION")
    else:
        sequence.append("CLOSURE")

    # Target 4-7 notes while preserving the important opening/closing events.
    minimum = 4
    maximum = min(7, len(sequence))
    target = random.randint(minimum, maximum)

    if target < len(sequence):
        first = sequence[0]
        last = sequence[-1]
        middle = sequence[1:-1]

        selected_middle = random.sample(
            middle,
            k=max(0, target - 2),
        )

        sequence = [first] + selected_middle + [last]

    return sequence


def distribute_timestamps(case_open_date, case_close_date, count):
    start = pd.Timestamp(case_open_date)

    if pd.notna(case_close_date):
        end = pd.Timestamp(case_close_date) + pd.Timedelta(hours=17)
    else:
        # Give open cases a realistic working window after case opening.
        end = start + pd.Timedelta(days=random.randint(5, 30), hours=17)

    if end <= start:
        end = start + pd.Timedelta(days=1)

    total_seconds = max(1, int((end - start).total_seconds()))

    timestamps = []
    for i in range(count):
        fraction = (i + 1) / (count + 1)
        base_seconds = int(total_seconds * fraction)

        jitter = random.randint(-7200, 7200)
        seconds = min(
            total_seconds - 1,
            max(1, base_seconds + jitter),
        )

        timestamps.append(start + pd.Timedelta(seconds=seconds))

    return sorted(timestamps)


def build_notes(cases: pd.DataFrame) -> pd.DataFrame:
    rows = []

    for _, case in cases.iterrows():
        sequence = note_sequence(
            case["rule_id"],
            case["case_status"],
            case["risk_rating"],
        )

        timestamps = distribute_timestamps(
            case["case_open_date"],
            case["case_close_date"],
            len(sequence),
        )

        for note_type, timestamp in zip(sequence, timestamps):
            rows.append(
                {
                    "case_id": case["case_id"],
                    "investigation_id": (
                        case["investigation_id"]
                        if pd.notna(case["investigation_id"])
                        else None
                    ),
                    "author_employee_id": (
                        case["investigator_id"]
                        if pd.notna(case["investigator_id"])
                        else None
                    ),
                    "note_timestamp": timestamp,
                    "note_type": note_type,
                    "note_text": random.choice(
                        NOTE_TEMPLATES[note_type]
                    ),
                }
            )

    return pd.DataFrame(rows)


def load_notes(notes: pd.DataFrame):
    if notes.empty:
        print("No new case notes to generate.")
        return

    notes.to_sql(
        "case_notes",
        engine,
        schema="core",
        if_exists="append",
        index=False,
        method="multi",
        chunksize=5000,
    )

    print(f"Loaded {len(notes):,} case notes into core.case_notes.")


def print_validation():
    summary = pd.read_sql(
        """
        SELECT
            COUNT(*) AS total_notes,
            COUNT(DISTINCT case_id) AS cases_with_notes,
            ROUND(
                COUNT(*)::NUMERIC
                / NULLIF(COUNT(DISTINCT case_id), 0),
                2
            ) AS average_notes_per_case
        FROM core.case_notes;
        """,
        engine,
    )

    distribution = pd.read_sql(
        """
        SELECT
            note_type,
            COUNT(*) AS note_count
        FROM core.case_notes
        GROUP BY note_type
        ORDER BY note_count DESC;
        """,
        engine,
    )

    print("\nCase-note validation:")
    print(summary.to_string(index=False))

    print("\nNote type distribution:")
    print(distribution.to_string(index=False))


def main():
    ensure_case_notes_table()

    cases = load_cases_without_notes()

    if cases.empty:
        print("Every existing case already has notes.")
        print_validation()
        return

    notes = build_notes(cases)
    load_notes(notes)
    print_validation()


if __name__ == "__main__":
    main()
