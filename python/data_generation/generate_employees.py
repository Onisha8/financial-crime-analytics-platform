import random
from datetime import date, timedelta

import pandas as pd
from faker import Faker
from sqlalchemy import text

from data_generator import engine

random.seed(42)
Faker.seed(42)
fake = Faker('en_US')

OFFICES = ['Tampa', 'New York', 'Wilmington', 'Charlotte']


def random_hire_date(years_experience: int) -> date:
    max_days = max(365, years_experience * 365)
    return date.today() - timedelta(days=random.randint(365, max_days))


def ensure_columns():
    statements = [
        "ALTER TABLE core.employees ADD COLUMN IF NOT EXISTS office_location VARCHAR(50);",
        "ALTER TABLE core.employees ADD COLUMN IF NOT EXISTS years_experience INTEGER;",
        "ALTER TABLE core.employees ADD COLUMN IF NOT EXISTS hire_date DATE;",
        "ALTER TABLE core.employees ADD COLUMN IF NOT EXISTS manager_id VARCHAR(20);",
        "ALTER TABLE core.employees ADD COLUMN IF NOT EXISTS employment_status VARCHAR(20);",
        "ALTER TABLE core.employees ADD COLUMN IF NOT EXISTS workload_capacity INTEGER;",
    ]
    with engine.begin() as conn:
        for stmt in statements:
            conn.execute(text(stmt))


def build_employee_rows() -> pd.DataFrame:
    rows = []
    next_num = 1

    manager_id = f'EMP{next_num:03d}'
    manager_exp = random.randint(12, 20)
    rows.append({
        'employee_id': manager_id,
        'employee_name': fake.name(),
        'role_name': 'Investigation Manager',
        'department': 'Financial Crime Operations',
        'branch_id': None,
        'active_flag': True,
        'office_location': random.choice(OFFICES),
        'years_experience': manager_exp,
        'hire_date': random_hire_date(manager_exp),
        'manager_id': None,
        'employment_status': 'Active',
        'workload_capacity': 0,
    })
    next_num += 1

    lead_ids = []
    for _ in range(2):
        emp_id = f'EMP{next_num:03d}'
        exp = random.randint(10, 18)
        lead_ids.append(emp_id)
        rows.append({
            'employee_id': emp_id,
            'employee_name': fake.name(),
            'role_name': 'Lead Investigator',
            'department': 'Financial Crime Operations',
            'branch_id': None,
            'active_flag': True,
            'office_location': random.choice(OFFICES),
            'years_experience': exp,
            'hire_date': random_hire_date(exp),
            'manager_id': manager_id,
            'employment_status': 'Active',
            'workload_capacity': 4500,
        })
        next_num += 1

    senior_ids = []
    for i in range(6):
        emp_id = f'EMP{next_num:03d}'
        exp = random.randint(7, 15)
        senior_ids.append(emp_id)
        rows.append({
            'employee_id': emp_id,
            'employee_name': fake.name(),
            'role_name': 'Senior Investigator',
            'department': 'Financial Crime Operations',
            'branch_id': None,
            'active_flag': True,
            'office_location': random.choice(OFFICES),
            'years_experience': exp,
            'hire_date': random_hire_date(exp),
            'manager_id': lead_ids[i % len(lead_ids)],
            'employment_status': 'Active',
            'workload_capacity': 3800,
        })
        next_num += 1

    for i in range(8):
        emp_id = f'EMP{next_num:03d}'
        exp = random.randint(2, 8)
        rows.append({
            'employee_id': emp_id,
            'employee_name': fake.name(),
            'role_name': 'Investigator I',
            'department': 'Financial Crime Operations',
            'branch_id': None,
            'active_flag': True,
            'office_location': random.choice(OFFICES),
            'years_experience': exp,
            'hire_date': random_hire_date(exp),
            'manager_id': senior_ids[i % len(senior_ids)],
            'employment_status': 'Active',
            'workload_capacity': 3200,
        })
        next_num += 1

    non_ops_specs = [
        ('Analytics Manager', 'Financial Crime Analytics', 1, 10, 18),
        ('Senior Data Analyst', 'Financial Crime Analytics', 2, 6, 12),
        ('Data Analyst', 'Financial Crime Analytics', 3, 2, 7),
        ('Senior Compliance Officer', 'AML Compliance', 1, 10, 18),
        ('Compliance Officer', 'AML Compliance', 3, 4, 10),
        ('Model Risk Manager', 'Model Risk', 1, 10, 18),
        ('Model Validation Analyst', 'Model Risk', 2, 4, 10),
    ]

    department_manager = {}
    for role, dept, count, min_exp, max_exp in non_ops_specs:
        for _ in range(count):
            emp_id = f'EMP{next_num:03d}'
            exp = random.randint(min_exp, max_exp)
            if 'Manager' in role or role == 'Senior Compliance Officer':
                manager = None
                department_manager.setdefault(dept, emp_id)
            else:
                manager = department_manager.get(dept)
            rows.append({
                'employee_id': emp_id,
                'employee_name': fake.name(),
                'role_name': role,
                'department': dept,
                'branch_id': None,
                'active_flag': True,
                'office_location': random.choice(OFFICES),
                'years_experience': exp,
                'hire_date': random_hire_date(exp),
                'manager_id': manager,
                'employment_status': 'Active',
                'workload_capacity': 0,
            })
            next_num += 1

    return pd.DataFrame(rows)


def upsert_employees(df: pd.DataFrame):
    sql = text('''
        INSERT INTO core.employees (
            employee_id, employee_name, role_name, department,
            branch_id, active_flag, office_location, years_experience,
            hire_date, manager_id, employment_status, workload_capacity
        ) VALUES (
            :employee_id, :employee_name, :role_name, :department,
            :branch_id, :active_flag, :office_location, :years_experience,
            :hire_date, :manager_id, :employment_status, :workload_capacity
        )
        ON CONFLICT (employee_id) DO UPDATE SET
            employee_name = EXCLUDED.employee_name,
            role_name = EXCLUDED.role_name,
            department = EXCLUDED.department,
            branch_id = EXCLUDED.branch_id,
            active_flag = EXCLUDED.active_flag,
            office_location = EXCLUDED.office_location,
            years_experience = EXCLUDED.years_experience,
            hire_date = EXCLUDED.hire_date,
            manager_id = EXCLUDED.manager_id,
            employment_status = EXCLUDED.employment_status,
            workload_capacity = EXCLUDED.workload_capacity;
    ''')
    with engine.begin() as conn:
        conn.execute(sql, df.to_dict('records'))


def main():
    ensure_columns()
    employees = build_employee_rows()
    upsert_employees(employees)
    print(f'Upserted {len(employees)} employees.')
    print(employees.groupby(['department', 'role_name']).size().reset_index(name='employee_count').to_string(index=False))


if __name__ == '__main__':
    main()