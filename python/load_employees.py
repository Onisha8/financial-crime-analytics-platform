from data_generator import engine
from sqlalchemy import text

employees = [
    ("EMP001", "Avery Johnson", "Financial Crime Analyst", "Financial Crime Operations", "BR001"),
    ("EMP002", "Maya Patel", "Senior Investigator", "Financial Crime Operations", "BR001"),
    ("EMP003", "Daniel Smith", "Model Risk Validator", "Model Risk Management", "BR002"),
    ("EMP004", "Priya Shah", "AML Analytics Manager", "Financial Crime Analytics", "BR002"),
    ("EMP005", "Chris Miller", "Credit Risk Analyst", "Credit Risk", "BR003"),
    ("EMP006", "Sophia Brown", "Data Quality Analyst", "Data Governance", "BR004"),
    ("EMP007", "James Wilson", "Transaction Monitoring Lead", "Financial Crime Analytics", "BR005"),
]

with engine.begin() as conn:
    for emp in employees:
        conn.execute(
            text("""
                INSERT INTO core.employees
                (employee_id, employee_name, role_name, department, branch_id)
                VALUES (:employee_id, :employee_name, :role_name, :department, :branch_id)
                ON CONFLICT (employee_id) DO NOTHING;
            """),
            {
                "employee_id": emp[0],
                "employee_name": emp[1],
                "role_name": emp[2],
                "department": emp[3],
                "branch_id": emp[4],
            }
        )

print("Employee seed data loaded successfully.")