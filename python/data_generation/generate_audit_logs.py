import pandas as pd
from sqlalchemy import text

from data_generator import engine


def ensure_audit_log_table():
    """
    Create a reusable audit log table for major Financial Crime workflow events.
    The source_record_id + event_type combination is used to make generation
    idempotent when this script is rerun.
    """
    with engine.begin() as conn:
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS core.audit_logs (
                    audit_id BIGSERIAL PRIMARY KEY,
                    event_type VARCHAR(100) NOT NULL,
                    entity_type VARCHAR(50) NOT NULL,
                    source_record_id VARCHAR(50) NOT NULL,
                    related_customer_id VARCHAR(20),
                    related_alert_id VARCHAR(30),
                    related_investigation_id VARCHAR(30),
                    related_case_id VARCHAR(30),
                    related_sar_id VARCHAR(30),
                    performed_by VARCHAR(20),
                    event_timestamp TIMESTAMP NOT NULL,
                    old_value TEXT,
                    new_value TEXT,
                    event_description TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

                    CONSTRAINT fk_audit_logs_customer
                        FOREIGN KEY (related_customer_id)
                        REFERENCES core.customers(customer_id),

                    CONSTRAINT fk_audit_logs_alert
                        FOREIGN KEY (related_alert_id)
                        REFERENCES core.alerts(alert_id),

                    CONSTRAINT fk_audit_logs_investigation
                        FOREIGN KEY (related_investigation_id)
                        REFERENCES core.investigations(investigation_id),

                    CONSTRAINT fk_audit_logs_case
                        FOREIGN KEY (related_case_id)
                        REFERENCES core.cases(case_id),

                    CONSTRAINT fk_audit_logs_sar
                        FOREIGN KEY (related_sar_id)
                        REFERENCES core.sar_reports(sar_id),

                    CONSTRAINT fk_audit_logs_employee
                        FOREIGN KEY (performed_by)
                        REFERENCES core.employees(employee_id)
                );
                """
            )
        )

        conn.execute(
            text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_audit_event_source
                ON core.audit_logs(event_type, entity_type, source_record_id);
                """
            )
        )

        conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp
                ON core.audit_logs(event_timestamp);
                """
            )
        )

        conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_audit_logs_customer
                ON core.audit_logs(related_customer_id);
                """
            )
        )

        conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_audit_logs_alert
                ON core.audit_logs(related_alert_id);
                """
            )
        )

        conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_audit_logs_investigation
                ON core.audit_logs(related_investigation_id);
                """
            )
        )

        conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_audit_logs_case
                ON core.audit_logs(related_case_id);
                """
            )
        )


def load_existing_keys():
    existing = pd.read_sql(
        """
        SELECT
            event_type,
            entity_type,
            source_record_id
        FROM core.audit_logs;
        """,
        engine,
    )

    if existing.empty:
        return set()

    return set(
        zip(
            existing["event_type"],
            existing["entity_type"],
            existing["source_record_id"],
        )
    )


def add_event(rows, existing_keys, event):
    key = (
        event["event_type"],
        event["entity_type"],
        event["source_record_id"],
    )

    if key not in existing_keys:
        rows.append(event)
        existing_keys.add(key)


def generate_alert_events(rows, existing_keys):
    alerts = pd.read_sql(
        """
        SELECT
            alert_id,
            customer_id,
            alert_date,
            alert_status,
            rule_id
        FROM core.alerts;
        """,
        engine,
    )

    for _, row in alerts.iterrows():
        timestamp = pd.Timestamp(row["alert_date"]) + pd.Timedelta(hours=8)

        add_event(
            rows,
            existing_keys,
            {
                "event_type": "ALERT_CREATED",
                "entity_type": "ALERT",
                "source_record_id": row["alert_id"],
                "related_customer_id": row["customer_id"],
                "related_alert_id": row["alert_id"],
                "related_investigation_id": None,
                "related_case_id": None,
                "related_sar_id": None,
                "performed_by": None,
                "event_timestamp": timestamp,
                "old_value": None,
                "new_value": row["alert_status"],
                "event_description": (
                    f"Alert {row['alert_id']} created under rule "
                    f"{row['rule_id']}."
                ),
            },
        )


def generate_investigation_events(rows, existing_keys):
    investigations = pd.read_sql(
        """
        SELECT
            i.investigation_id,
            i.alert_id,
            i.investigator_id,
            i.investigation_start,
            i.investigation_end,
            i.disposition,
            a.customer_id
        FROM core.investigations i
        JOIN core.alerts a
            ON i.alert_id = a.alert_id;
        """,
        engine,
    )

    for _, row in investigations.iterrows():
        start_ts = (
            pd.Timestamp(row["investigation_start"])
            if pd.notna(row["investigation_start"])
            else pd.Timestamp("2026-01-01")
        )

        add_event(
            rows,
            existing_keys,
            {
                "event_type": "INVESTIGATION_ASSIGNED",
                "entity_type": "INVESTIGATION",
                "source_record_id": row["investigation_id"],
                "related_customer_id": row["customer_id"],
                "related_alert_id": row["alert_id"],
                "related_investigation_id": row["investigation_id"],
                "related_case_id": None,
                "related_sar_id": None,
                "performed_by": row["investigator_id"],
                "event_timestamp": start_ts,
                "old_value": None,
                "new_value": row["investigator_id"],
                "event_description": (
                    f"Investigation {row['investigation_id']} assigned to "
                    f"{row['investigator_id']}."
                ),
            },
        )

        if pd.notna(row["investigation_end"]):
            end_ts = pd.Timestamp(row["investigation_end"])

            add_event(
                rows,
                existing_keys,
                {
                    "event_type": "INVESTIGATION_COMPLETED",
                    "entity_type": "INVESTIGATION",
                    "source_record_id": row["investigation_id"],
                    "related_customer_id": row["customer_id"],
                    "related_alert_id": row["alert_id"],
                    "related_investigation_id": row["investigation_id"],
                    "related_case_id": None,
                    "related_sar_id": None,
                    "performed_by": row["investigator_id"],
                    "event_timestamp": end_ts,
                    "old_value": "Open",
                    "new_value": row["disposition"],
                    "event_description": (
                        f"Investigation {row['investigation_id']} completed "
                        f"with disposition: {row['disposition']}."
                    ),
                },
            )


def generate_case_events(rows, existing_keys):
    cases = pd.read_sql(
        """
        SELECT
            c.case_id,
            c.customer_id,
            c.investigation_id,
            c.case_open_date,
            c.case_close_date,
            c.case_status,
            c.risk_rating,
            i.alert_id,
            i.investigator_id
        FROM core.cases c
        LEFT JOIN core.investigations i
            ON c.investigation_id = i.investigation_id;
        """,
        engine,
    )

    for _, row in cases.iterrows():
        open_ts = pd.Timestamp(row["case_open_date"]) + pd.Timedelta(hours=9)

        add_event(
            rows,
            existing_keys,
            {
                "event_type": "CASE_CREATED",
                "entity_type": "CASE",
                "source_record_id": row["case_id"],
                "related_customer_id": row["customer_id"],
                "related_alert_id": (
                    row["alert_id"] if pd.notna(row["alert_id"]) else None
                ),
                "related_investigation_id": (
                    row["investigation_id"]
                    if pd.notna(row["investigation_id"])
                    else None
                ),
                "related_case_id": row["case_id"],
                "related_sar_id": None,
                "performed_by": (
                    row["investigator_id"]
                    if pd.notna(row["investigator_id"])
                    else None
                ),
                "event_timestamp": open_ts,
                "old_value": None,
                "new_value": row["risk_rating"],
                "event_description": (
                    f"Case {row['case_id']} created with "
                    f"{row['risk_rating']} risk rating."
                ),
            },
        )

        if pd.notna(row["case_close_date"]):
            close_ts = pd.Timestamp(row["case_close_date"]) + pd.Timedelta(hours=16)

            add_event(
                rows,
                existing_keys,
                {
                    "event_type": "CASE_CLOSED",
                    "entity_type": "CASE",
                    "source_record_id": row["case_id"],
                    "related_customer_id": row["customer_id"],
                    "related_alert_id": (
                        row["alert_id"] if pd.notna(row["alert_id"]) else None
                    ),
                    "related_investigation_id": (
                        row["investigation_id"]
                        if pd.notna(row["investigation_id"])
                        else None
                    ),
                    "related_case_id": row["case_id"],
                    "related_sar_id": None,
                    "performed_by": (
                        row["investigator_id"]
                        if pd.notna(row["investigator_id"])
                        else None
                    ),
                    "event_timestamp": close_ts,
                    "old_value": "Open",
                    "new_value": "Closed",
                    "event_description": (
                        f"Case {row['case_id']} closed."
                    ),
                },
            )


def generate_sar_events(rows, existing_keys):
    sars = pd.read_sql(
        """
        SELECT
            s.sar_id,
            s.case_id,
            s.customer_id,
            s.filing_date,
            s.sar_status,
            c.investigation_id,
            i.alert_id,
            i.investigator_id
        FROM core.sar_reports s
        JOIN core.cases c
            ON s.case_id = c.case_id
        LEFT JOIN core.investigations i
            ON c.investigation_id = i.investigation_id;
        """,
        engine,
    )

    for _, row in sars.iterrows():
        filing_ts = pd.Timestamp(row["filing_date"]) + pd.Timedelta(hours=14)

        add_event(
            rows,
            existing_keys,
            {
                "event_type": "SAR_FILED",
                "entity_type": "SAR",
                "source_record_id": row["sar_id"],
                "related_customer_id": row["customer_id"],
                "related_alert_id": (
                    row["alert_id"] if pd.notna(row["alert_id"]) else None
                ),
                "related_investigation_id": (
                    row["investigation_id"]
                    if pd.notna(row["investigation_id"])
                    else None
                ),
                "related_case_id": row["case_id"],
                "related_sar_id": row["sar_id"],
                "performed_by": (
                    row["investigator_id"]
                    if pd.notna(row["investigator_id"])
                    else None
                ),
                "event_timestamp": filing_ts,
                "old_value": None,
                "new_value": row["sar_status"],
                "event_description": (
                    f"SAR {row['sar_id']} recorded for case "
                    f"{row['case_id']} with status {row['sar_status']}."
                ),
            },
        )


def generate_action_events(rows, existing_keys):
    """
    If core.investigator_actions exists, add action-completion events.
    """
    exists = pd.read_sql(
        """
        SELECT EXISTS (
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = 'core'
              AND table_name = 'investigator_actions'
        ) AS exists_flag;
        """,
        engine,
    ).iloc[0]["exists_flag"]

    if not exists:
        return

    actions = pd.read_sql(
        """
        SELECT
            ia.action_id,
            ia.investigation_id,
            ia.alert_id,
            ia.investigator_id,
            ia.action_type,
            ia.action_timestamp,
            ia.action_outcome,
            a.customer_id,
            c.case_id
        FROM core.investigator_actions ia
        JOIN core.alerts a
            ON ia.alert_id = a.alert_id
        LEFT JOIN core.cases c
            ON ia.investigation_id = c.investigation_id;
        """,
        engine,
    )

    for _, row in actions.iterrows():
        add_event(
            rows,
            existing_keys,
            {
                "event_type": "INVESTIGATOR_ACTION_COMPLETED",
                "entity_type": "ACTION",
                "source_record_id": str(row["action_id"]),
                "related_customer_id": row["customer_id"],
                "related_alert_id": row["alert_id"],
                "related_investigation_id": row["investigation_id"],
                "related_case_id": (
                    row["case_id"] if pd.notna(row["case_id"]) else None
                ),
                "related_sar_id": None,
                "performed_by": row["investigator_id"],
                "event_timestamp": pd.Timestamp(row["action_timestamp"]),
                "old_value": None,
                "new_value": row["action_outcome"],
                "event_description": (
                    f"{row['action_type']} completed with outcome: "
                    f"{row['action_outcome']}."
                ),
            },
        )


def load_audit_events(rows):
    if not rows:
        print("No new audit events to insert.")
        return

    df = pd.DataFrame(rows)

    df.to_sql(
        "audit_logs",
        engine,
        schema="core",
        if_exists="append",
        index=False,
        method="multi",
        chunksize=5000,
    )

    print(f"Loaded {len(df):,} audit events into core.audit_logs.")


def print_validation():
    summary = pd.read_sql(
        """
        SELECT
            event_type,
            COUNT(*) AS event_count
        FROM core.audit_logs
        GROUP BY event_type
        ORDER BY event_count DESC;
        """,
        engine,
    )

    total = pd.read_sql(
        """
        SELECT
            COUNT(*) AS total_audit_events,
            COUNT(DISTINCT related_customer_id) AS customers_covered,
            COUNT(DISTINCT related_investigation_id) AS investigations_covered,
            COUNT(DISTINCT related_case_id) AS cases_covered
        FROM core.audit_logs;
        """,
        engine,
    )

    print("\nAudit log validation:")
    print(total.to_string(index=False))

    print("\nEvent distribution:")
    print(summary.to_string(index=False))


def main():
    ensure_audit_log_table()

    existing_keys = load_existing_keys()
    rows = []

    generate_alert_events(rows, existing_keys)
    generate_investigation_events(rows, existing_keys)
    generate_case_events(rows, existing_keys)
    generate_sar_events(rows, existing_keys)
    generate_action_events(rows, existing_keys)

    load_audit_events(rows)
    print_validation()


if __name__ == "__main__":
    main()
