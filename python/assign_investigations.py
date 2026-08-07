import random

import pandas as pd
from sqlalchemy import text

from data_generator import engine

random.seed(42)


def load_investigators() -> pd.DataFrame:
    return pd.read_sql('''
        SELECT employee_id, role_name, workload_capacity
        FROM core.employees
        WHERE role_name IN ('Investigator I', 'Senior Investigator', 'Lead Investigator')
          AND COALESCE(employment_status, 'Active') = 'Active'
        ORDER BY employee_id;
    ''', engine)


def load_investigations() -> pd.DataFrame:
    return pd.read_sql('''
        SELECT investigation_id
        FROM core.investigations
        ORDER BY investigation_id;
    ''', engine)


def calculate_targets(investigators: pd.DataFrame, total_investigations: int) -> dict:
    total_capacity = int(investigators['workload_capacity'].sum())
    if total_capacity <= 0:
        raise ValueError('Total investigator workload capacity must be greater than zero.')
    if total_investigations > total_capacity:
        raise ValueError(
            f'{total_investigations:,} investigations exceed configured capacity of {total_capacity:,}.'
        )

    x = investigators.copy()
    x['exact_target'] = total_investigations * x['workload_capacity'] / total_capacity
    x['target'] = x['exact_target'].astype(int)
    x['fraction'] = x['exact_target'] - x['target']
    remaining = total_investigations - int(x['target'].sum())
    if remaining > 0:
        idx = x.sort_values(['fraction', 'employee_id'], ascending=[False, True]).head(remaining).index
        x.loc[idx, 'target'] += 1
    return dict(zip(x['employee_id'], x['target'].astype(int)))


def build_assignments(investigations: pd.DataFrame, target_counts: dict) -> pd.DataFrame:
    ids = investigations['investigation_id'].tolist()
    random.shuffle(ids)
    rows = []
    cursor = 0
    for investigator_id in sorted(target_counts):
        count = target_counts[investigator_id]
        for investigation_id in ids[cursor:cursor + count]:
            rows.append({
                'investigation_id': investigation_id,
                'investigator_id': investigator_id,
            })
        cursor += count

    if cursor != len(ids):
        raise RuntimeError(f'Assigned {cursor:,} of {len(ids):,} investigations.')
    return pd.DataFrame(rows)


def bulk_update(assignments: pd.DataFrame):
    assignments.to_sql(
        'tmp_investigator_assignment',
        engine,
        schema='analytics',
        if_exists='replace',
        index=False,
        method='multi',
        chunksize=5000,
    )

    with engine.begin() as conn:
        conn.execute(text('''
            UPDATE core.investigations i
            SET investigator_id = t.investigator_id
            FROM analytics.tmp_investigator_assignment t
            WHERE i.investigation_id = t.investigation_id;
        '''))
        conn.execute(text('DROP TABLE analytics.tmp_investigator_assignment;'))


def validate():
    summary = pd.read_sql('''
        SELECT
            i.investigator_id,
            e.employee_name,
            e.role_name,
            e.workload_capacity,
            COUNT(*) AS assigned_investigations,
            ROUND(COUNT(*)::NUMERIC / NULLIF(e.workload_capacity, 0) * 100, 2) AS capacity_utilization_pct
        FROM core.investigations i
        JOIN core.employees e ON i.investigator_id = e.employee_id
        GROUP BY i.investigator_id, e.employee_name, e.role_name, e.workload_capacity
        ORDER BY assigned_investigations DESC;
    ''', engine)

    unassigned = pd.read_sql('''
        SELECT COUNT(*) AS unassigned_investigations
        FROM core.investigations
        WHERE investigator_id IS NULL;
    ''', engine).iloc[0]['unassigned_investigations']

    print(summary.to_string(index=False))
    print(f'Unassigned investigations: {int(unassigned):,}')


def main():
    investigators = load_investigators()
    investigations = load_investigations()

    if investigators.empty:
        raise RuntimeError('No active investigators found. Run generate_employees.py first.')
    if investigations.empty:
        print('No investigations found. Nothing to assign.')
        return

    targets = calculate_targets(investigators, len(investigations))
    print('Target assignment counts:')
    for employee_id, target in sorted(targets.items()):
        print(f'  {employee_id}: {target:,}')

    assignments = build_assignments(investigations, targets)
    bulk_update(assignments)
    validate()


if __name__ == '__main__':
    main()