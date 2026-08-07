import random
import pandas as pd
from sqlalchemy import text

from data_generator import engine

random.seed(42)

ACTION_LIBRARY = {
    "TM001": [
        "Transaction Review",
        "Cash Activity Review",
        "KYC Review",
        "Customer Profile Review",
        "Escalation Assessment",
    ],
    "TM002": [
        "Transaction Review",
        "Geography Review",
        "KYC Review",
        "Customer Profile Review",
        "Escalation Assessment",
    ],
    "TM003": [
        "Transaction Review",
        "Account History Review",
        "Dormancy Review",
        "KYC Review",
        "Escalation Assessment",
    ],
    "TM004": [
        "Transaction Review",
        "Velocity Analysis",
        "Source and Use of Funds Review",
        "Customer Profile Review",
        "Escalation Assessment",
    ],
    "TM005": [
        "Transaction Review",
        "Device Analysis",
        "Login Activity Review",
        "Related Customer Review",
        "Escalation Assessment",
    ],
    "TM006": [
        "Transaction Review",
        "Wire Transfer Review",
        "Beneficiary Review",
        "KYC Review",
        "Escalation Assessment",
    ],
    "TM007": [
        "Transaction Review",
        "Pattern Analysis",
        "Round-Dollar Activity Review",
        "Customer Profile Review",
        "Escalation Assessment",
    ],
    "TM008": [
        "Transaction Review",
        "Merchant Risk Review",
        "Merchant Category Review",
        "Customer Profile Review",
        "Escalation Assessment",
    ],
}

ACTION_OUTCOMES = {
    "Transaction Review": ["Completed", "No Issue", "Requires Follow-up"],
    "Cash Activity Review": ["Completed", "Pattern Confirmed", "No Issue"],
    "Geography Review": ["Completed", "Elevated Risk", "No Issue"],
    "KYC Review": ["Completed", "Mismatch Identified", "Consistent"],
    "Customer Profile Review": ["Completed", "Consistent", "Inconsistency Identified"],
    "Escalation Assessment": ["Escalated", "Monitoring Required", "Closed - No Issue"],
    "Account History Review": ["Completed", "Behavior Change Identified", "No Issue"],
    "Dormancy Review": ["Completed", "Dormant Activity Confirmed", "No Issue"],
    "Velocity Analysis": ["Completed", "High Velocity Confirmed", "No Issue"],
    "Source and Use of Funds Review": ["Completed", "Needs Clarification", "Consistent"],
    "Device Analysis": ["Completed", "Shared Device Confirmed", "No Issue"],
    "Login Activity Review": ["Completed", "Anomaly Identified", "No Issue"],
    "Related Customer Review": ["Completed", "Relationship Identified", "No Link Found"],
    "Wire Transfer Review": ["Completed", "High-Risk Pattern", "No Issue"],
    "Beneficiary Review": ["Completed", "Beneficiary Risk Identified", "No Issue"],
    "Pattern Analysis": ["Completed", "Pattern Confirmed", "No Issue"],
    "Round-Dollar Activity Review": ["Completed", "Pattern Confirmed", "No Issue"],
    "Merchant Risk Review": ["Completed", "Elevated Risk", "No Issue"],
    "Merchant Category Review": ["Completed", "High-Risk Category Confirmed", "No Issue"],
}


def ensure_table():
    with engine.begin() as conn:
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS core.investigator_actions (
                    action_id BIGSERIAL PRIMARY KEY,
                    investigation_id VARCHAR(30) NOT NULL,
                    alert_id VARCHAR(30) NOT NULL,
                    investigator_id VARCHAR(20),
                    action_type VARCHAR(100) NOT NULL,
                    action_timestamp TIMESTAMP NOT NULL,
                    action_outcome VARCHAR(100),
                    action_notes TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

                    CONSTRAINT fk_investigator_actions_investigation
                        FOREIGN KEY (investigation_id)
                        REFERENCES core.investigations(investigation_id),

                    CONSTRAINT fk_investigator_actions_alert
                        FOREIGN KEY (alert_id)
                        REFERENCES core.alerts(alert_id),

                    CONSTRAINT fk_investigator_actions_employee
                        FOREIGN KEY (investigator_id)
                        REFERENCES core.employees(employee_id)
                );
                """
            )
        )

        conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_investigator_actions_investigation
                ON core.investigator_actions(investigation_id);
                """
            )
        )

        conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_investigator_actions_investigator
                ON core.investigator_actions(investigator_id);
                """
            )
        )

        conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_investigator_actions_timestamp
                ON core.investigator_actions(action_timestamp);
                """
            )
        )


def load_investigations_without_actions() -> pd.DataFrame:
    return pd.read_sql(
        """
        SELECT
            i.investigation_id,
            i.alert_id,
            i.investigator_id,
            i.investigation_start,
            i.investigation_end,
            i.disposition,
            a.rule_id
        FROM core.investigations i
        JOIN core.alerts a
            ON i.alert_id = a.alert_id
        LEFT JOIN core.investigator_actions ia
            ON i.investigation_id = ia.investigation_id
        WHERE ia.action_id IS NULL
        ORDER BY i.investigation_id;
        """,
        engine,
    )


def build_action_sequence(rule_id: str, disposition: str):
    base = ACTION_LIBRARY.get(
        rule_id,
        [
            "Transaction Review",
            "Customer Profile Review",
            "KYC Review",
            "Escalation Assessment",
        ],
    )

    # Keep 3-5 actions per investigation.
    min_actions = 3
    max_actions = min(5, len(base))
    count = random.randint(min_actions, max_actions)

    if count == len(base):
        sequence = list(base)
    else:
        # Always keep Transaction Review first and Escalation Assessment last if present.
        first = base[0]
        last = base[-1]
        middle = base[1:-1]
        selected_middle = random.sample(
            middle,
            k=max(0, count - 2),
        )
        sequence = [first] + selected_middle + [last]

    # Align the final action to the investigation's actual disposition.
    if "Escalation Assessment" not in sequence:
        sequence.append("Escalation Assessment")

    return sequence


def distribute_timestamps(start_value, end_value, count):
    start = (
        pd.Timestamp(start_value)
        if pd.notna(start_value)
        else pd.Timestamp("2026-01-01")
    )

    if pd.notna(end_value):
        end = pd.Timestamp(end_value)
    else:
        end = start + pd.Timedelta(days=random.randint(2, 20))

    if end <= start:
        end = start + pd.Timedelta(days=1)

    span_seconds = max(1, int((end - start).total_seconds()))
    timestamps = []

    for i in range(count):
        frac = (i + 1) / (count + 1)
        seconds = int(span_seconds * frac)
        jitter = random.randint(-3600, 3600)
        seconds = min(span_seconds - 1, max(1, seconds + jitter))
        timestamps.append(start + pd.Timedelta(seconds=seconds))

    return sorted(timestamps)


def action_outcome(action_type: str, disposition: str):
    if action_type == "Escalation Assessment":
        return disposition

    return random.choice(
        ACTION_OUTCOMES.get(action_type, ["Completed"])
    )


def build_actions(investigations: pd.DataFrame) -> pd.DataFrame:
    rows = []

    for _, inv in investigations.iterrows():
        sequence = build_action_sequence(
            inv["rule_id"],
            inv["disposition"],
        )

        timestamps = distribute_timestamps(
            inv["investigation_start"],
            inv["investigation_end"],
            len(sequence),
        )

        for action_type, action_ts in zip(sequence, timestamps):
            outcome = action_outcome(
                action_type,
                inv["disposition"],
            )

            rows.append(
                {
                    "investigation_id": inv["investigation_id"],
                    "alert_id": inv["alert_id"],
                    "investigator_id": inv["investigator_id"],
                    "action_type": action_type,
                    "action_timestamp": action_ts,
                    "action_outcome": outcome,
                    "action_notes": (
                        f"{action_type} completed with outcome: {outcome}."
                    ),
                }
            )

    return pd.DataFrame(rows)


def load_actions(actions: pd.DataFrame):
    if actions.empty:
        print("No new investigator actions to generate.")
        return

    actions.to_sql(
        "investigator_actions",
        engine,
        schema="core",
        if_exists="append",
        index=False,
        method="multi",
        chunksize=5000,
    )

    print(
        f"Loaded {len(actions):,} investigator actions "
        "into core.investigator_actions."
    )


def print_validation():
    summary = pd.read_sql(
        """
        SELECT
            COUNT(*) AS total_actions,
            COUNT(DISTINCT investigation_id) AS investigations_with_actions,
            ROUND(
                COUNT(*)::NUMERIC
                / NULLIF(COUNT(DISTINCT investigation_id), 0),
                2
            ) AS avg_actions_per_investigation
        FROM core.investigator_actions;
        """,
        engine,
    )

    action_dist = pd.read_sql(
        """
        SELECT
            action_type,
            COUNT(*) AS action_count
        FROM core.investigator_actions
        GROUP BY action_type
        ORDER BY action_count DESC;
        """,
        engine,
    )

    print("\nInvestigator-action validation:")
    print(summary.to_string(index=False))

    print("\nAction type distribution:")
    print(action_dist.to_string(index=False))


def main():
    ensure_table()

    investigations = load_investigations_without_actions()

    if investigations.empty:
        print("Every existing investigation already has actions.")
        print_validation()
        return

    actions = build_actions(investigations)
    load_actions(actions)
    print_validation()


if __name__ == "__main__":
    main()
