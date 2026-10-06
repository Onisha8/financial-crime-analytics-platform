CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS reference;

CREATE TABLE IF NOT EXISTS core.customers (
    customer_id              VARCHAR(20) PRIMARY KEY,
    customer_since           DATE NOT NULL,
    date_of_birth            DATE NOT NULL,
    state                    VARCHAR(10),
    occupation               VARCHAR(100),
    income_band              VARCHAR(50),
    kyc_risk_rating          VARCHAR(20),
    politically_exposed_person_flag BOOLEAN DEFAULT FALSE,
    customer_segment         VARCHAR(50),
    created_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS core.accounts (
    account_id        VARCHAR(20) PRIMARY KEY,
    customer_id       VARCHAR(20) NOT NULL,
    account_type      VARCHAR(50) NOT NULL,
    open_date         DATE NOT NULL,
    status            VARCHAR(20),
    branch_state      VARCHAR(10),
    current_balance   NUMERIC(18,2),
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_accounts_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id)
);

CREATE TABLE IF NOT EXISTS core.customer_kyc (
    kyc_id                      BIGSERIAL PRIMARY KEY,
    customer_id                 VARCHAR(20) NOT NULL,
    kyc_level                   VARCHAR(30),
    kyc_status                  VARCHAR(30),
    source_of_funds             VARCHAR(100),
    source_of_wealth            VARCHAR(100),
    expected_monthly_income     NUMERIC(18,2),
    expected_monthly_txn_volume NUMERIC(18,2),
    occupation_risk_rating      VARCHAR(20),
    last_review_date            DATE,
    next_review_date            DATE,
    created_at                  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_customer_kyc_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id)
);

CREATE TABLE IF NOT EXISTS core.customer_addresses (
    address_id      BIGSERIAL PRIMARY KEY,
    customer_id     VARCHAR(20) NOT NULL,
    address_type    VARCHAR(30),
    address_line_1  VARCHAR(200),
    city            VARCHAR(100),
    state           VARCHAR(50),
    country         VARCHAR(50),
    postal_code     VARCHAR(20),
    effective_from  DATE,
    effective_to    DATE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_customer_addresses_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id)
);

CREATE TABLE IF NOT EXISTS core.customer_phones (
    phone_id       BIGSERIAL PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    phone_number   VARCHAR(30),
    phone_type     VARCHAR(30),
    is_primary     BOOLEAN DEFAULT FALSE,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_customer_phones_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id)
);

CREATE TABLE IF NOT EXISTS core.customer_emails (
    email_id       BIGSERIAL PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    email_address  VARCHAR(150),
    is_primary     BOOLEAN DEFAULT FALSE,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_customer_emails_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id)
);

CREATE TABLE IF NOT EXISTS core.branches (
    branch_id       VARCHAR(20) PRIMARY KEY,
    branch_name     VARCHAR(100),
    city            VARCHAR(100),
    state           VARCHAR(50),
    country         VARCHAR(50),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS core.employees (
    employee_id     VARCHAR(20) PRIMARY KEY,
    employee_name   VARCHAR(100),
    role_name       VARCHAR(100),
    department      VARCHAR(100),
    branch_id       VARCHAR(20),
    active_flag     BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_employees_branch
        FOREIGN KEY (branch_id)
        REFERENCES core.branches(branch_id)
);

CREATE TABLE IF NOT EXISTS core.cards (
    card_id         VARCHAR(20) PRIMARY KEY,
    account_id      VARCHAR(20) NOT NULL,
    customer_id     VARCHAR(20) NOT NULL,
    card_type       VARCHAR(30),
    card_status     VARCHAR(30),
    credit_limit    NUMERIC(18,2),
    issue_date      DATE,
    expiry_date     DATE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_cards_account
        FOREIGN KEY (account_id)
        REFERENCES core.accounts(account_id),

    CONSTRAINT fk_cards_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id)
);

CREATE TABLE IF NOT EXISTS core.merchants (
    merchant_id             VARCHAR(20) PRIMARY KEY,
    merchant_name           VARCHAR(150),
    merchant_category       VARCHAR(100),
    merchant_country        VARCHAR(50),
    merchant_risk_rating    VARCHAR(20),
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS core.beneficiaries (
    beneficiary_id          VARCHAR(20) PRIMARY KEY,
    customer_id             VARCHAR(20) NOT NULL,
    beneficiary_name        VARCHAR(150),
    beneficiary_bank_country VARCHAR(50),
    relationship_type       VARCHAR(50),
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_beneficiaries_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id)
);

CREATE TABLE IF NOT EXISTS core.loans (
    loan_id                 VARCHAR(20) PRIMARY KEY,
    customer_id             VARCHAR(20) NOT NULL,
    loan_type               VARCHAR(50),
    origination_date        DATE,
    original_balance        NUMERIC(18,2),
    outstanding_balance     NUMERIC(18,2),
    interest_rate           NUMERIC(8,4),
    term_months             INT,
    credit_score_at_origination INT,
    loan_status             VARCHAR(30),
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_loans_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id)
);

CREATE TABLE IF NOT EXISTS core.loan_payments (
    loan_payment_id     BIGSERIAL PRIMARY KEY,
    loan_id             VARCHAR(20) NOT NULL,
    customer_id          VARCHAR(20) NOT NULL,
    payment_due_date     DATE,
    payment_date         DATE,
    due_amount           NUMERIC(18,2),
    paid_amount          NUMERIC(18,2),
    delinquency_days     INT,
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_loan_payments_loan
        FOREIGN KEY (loan_id)
        REFERENCES core.loans(loan_id),

    CONSTRAINT fk_loan_payments_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id)
);

CREATE TABLE IF NOT EXISTS core.devices (
    device_id        VARCHAR(20) PRIMARY KEY,
    customer_id      VARCHAR(20),
    device_type      VARCHAR(50),
    operating_system VARCHAR(50),
    first_seen_date  DATE,
    last_seen_date   DATE,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_devices_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id)
);

CREATE TABLE IF NOT EXISTS core.ip_addresses (
    ip_id            BIGSERIAL PRIMARY KEY,
    ip_address       VARCHAR(50),
    ip_country       VARCHAR(50),
    ip_city          VARCHAR(100),
    risk_rating      VARCHAR(20),
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS core.login_events (
    login_id         BIGSERIAL PRIMARY KEY,
    customer_id      VARCHAR(20) NOT NULL,
    device_id        VARCHAR(20),
    ip_id            BIGINT,
    login_timestamp  TIMESTAMP NOT NULL,
    login_success    BOOLEAN,
    mfa_used         BOOLEAN,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_login_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id),

    CONSTRAINT fk_login_device
        FOREIGN KEY (device_id)
        REFERENCES core.devices(device_id),

    CONSTRAINT fk_login_ip
        FOREIGN KEY (ip_id)
        REFERENCES core.ip_addresses(ip_id)
);

CREATE TABLE IF NOT EXISTS core.transactions (
    transaction_id        VARCHAR(30) PRIMARY KEY,
    account_id            VARCHAR(20) NOT NULL,
    customer_id           VARCHAR(20) NOT NULL,
    card_id               VARCHAR(20),
    merchant_id           VARCHAR(20),
    beneficiary_id        VARCHAR(20),
    device_id             VARCHAR(20),
    ip_id                 BIGINT,
    transaction_timestamp TIMESTAMP NOT NULL,
    transaction_type      VARCHAR(50),
    channel               VARCHAR(50),
    amount                NUMERIC(18,2),
    currency              VARCHAR(10),
    origin_country        VARCHAR(50),
    destination_country   VARCHAR(50),
    transaction_status    VARCHAR(30),
    created_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    suspicious_flag       BOOLEAN DEFAULT FALSE,   -- synthetic scenario label set by sql/01_alert_generation
    scenario_type         VARCHAR(100),

    CONSTRAINT fk_txn_account
        FOREIGN KEY (account_id)
        REFERENCES core.accounts(account_id),

    CONSTRAINT fk_txn_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id),

    CONSTRAINT fk_txn_card
        FOREIGN KEY (card_id)
        REFERENCES core.cards(card_id),

    CONSTRAINT fk_txn_merchant
        FOREIGN KEY (merchant_id)
        REFERENCES core.merchants(merchant_id),

    CONSTRAINT fk_txn_beneficiary
        FOREIGN KEY (beneficiary_id)
        REFERENCES core.beneficiaries(beneficiary_id),

    CONSTRAINT fk_txn_device
        FOREIGN KEY (device_id)
        REFERENCES core.devices(device_id),

    CONSTRAINT fk_txn_ip
        FOREIGN KEY (ip_id)
        REFERENCES core.ip_addresses(ip_id)
);

CREATE TABLE IF NOT EXISTS reference.alert_rules (
    rule_id             VARCHAR(20) PRIMARY KEY,
    rule_name           VARCHAR(150) NOT NULL,
    rule_description    TEXT,
    rule_version        VARCHAR(20),
    threshold_value     NUMERIC(18,2),
    severity            VARCHAR(20),
    effective_date      DATE,
    expiry_date         DATE,
    status              VARCHAR(30),
    owner_team          VARCHAR(100),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS core.alerts (
    alert_id        VARCHAR(30) PRIMARY KEY,
    transaction_id  VARCHAR(30) NOT NULL,
    customer_id     VARCHAR(20) NOT NULL,
    account_id      VARCHAR(20) NOT NULL,
    rule_id         VARCHAR(20),
    alert_date      DATE NOT NULL,
    alert_score     NUMERIC(8,2),
    priority        VARCHAR(20),
    alert_status    VARCHAR(30),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_alert_transaction
        FOREIGN KEY (transaction_id)
        REFERENCES core.transactions(transaction_id),

    CONSTRAINT fk_alert_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id),

    CONSTRAINT fk_alert_account
        FOREIGN KEY (account_id)
        REFERENCES core.accounts(account_id),

    CONSTRAINT fk_alert_rule
        FOREIGN KEY (rule_id)
        REFERENCES reference.alert_rules(rule_id)
);

CREATE TABLE IF NOT EXISTS core.investigations (
    investigation_id    VARCHAR(30) PRIMARY KEY,
    alert_id            VARCHAR(30) NOT NULL,
    investigator_id     VARCHAR(20),
    investigation_start TIMESTAMP,
    investigation_end   TIMESTAMP,
    disposition         VARCHAR(50),
    notes               TEXT,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_investigation_alert
        FOREIGN KEY (alert_id)
        REFERENCES core.alerts(alert_id),

    CONSTRAINT fk_investigation_employee
        FOREIGN KEY (investigator_id)
        REFERENCES core.employees(employee_id)
);

CREATE TABLE IF NOT EXISTS core.cases (
    case_id          VARCHAR(30) PRIMARY KEY,
    customer_id      VARCHAR(20) NOT NULL,
    case_open_date   DATE,
    case_close_date  DATE,
    case_status      VARCHAR(30),
    case_type        VARCHAR(50),
    risk_rating      VARCHAR(20),
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_case_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id)
);

CREATE TABLE IF NOT EXISTS core.case_alerts (
    case_id      VARCHAR(30) NOT NULL,
    alert_id     VARCHAR(30) NOT NULL,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (case_id, alert_id),

    CONSTRAINT fk_case_alert_case
        FOREIGN KEY (case_id)
        REFERENCES core.cases(case_id),

    CONSTRAINT fk_case_alert_alert
        FOREIGN KEY (alert_id)
        REFERENCES core.alerts(alert_id)
);

CREATE TABLE IF NOT EXISTS core.sar_reports (
    sar_id           VARCHAR(30) PRIMARY KEY,
    case_id          VARCHAR(30) NOT NULL,
    customer_id      VARCHAR(20) NOT NULL,
    filing_date      DATE,
    sar_status       VARCHAR(30),
    narrative        TEXT,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_sar_case
        FOREIGN KEY (case_id)
        REFERENCES core.cases(case_id),

    CONSTRAINT fk_sar_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers(customer_id)
);

CREATE INDEX IF NOT EXISTS idx_accounts_customer
ON core.accounts(customer_id);

CREATE INDEX IF NOT EXISTS idx_transactions_customer
ON core.transactions(customer_id);

CREATE INDEX IF NOT EXISTS idx_transactions_account
ON core.transactions(account_id);

CREATE INDEX IF NOT EXISTS idx_transactions_timestamp
ON core.transactions(transaction_timestamp);

CREATE INDEX IF NOT EXISTS idx_transactions_type
ON core.transactions(transaction_type);

CREATE INDEX IF NOT EXISTS idx_transactions_merchant
ON core.transactions(merchant_id);

CREATE INDEX IF NOT EXISTS idx_alerts_customer
ON core.alerts(customer_id);

CREATE INDEX IF NOT EXISTS idx_alerts_transaction
ON core.alerts(transaction_id);

CREATE INDEX IF NOT EXISTS idx_alerts_date
ON core.alerts(alert_date);

CREATE INDEX IF NOT EXISTS idx_alerts_priority
ON core.alerts(priority);

CREATE INDEX IF NOT EXISTS idx_investigations_alert
ON core.investigations(alert_id);

CREATE INDEX IF NOT EXISTS idx_login_customer
ON core.login_events(customer_id);

CREATE INDEX IF NOT EXISTS idx_login_timestamp
ON core.login_events(login_timestamp);
