-- E11. Должность
CREATE TABLE positions (
    position_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    position_code VARCHAR(20) NOT NULL UNIQUE,
    position_name VARCHAR(100) NOT NULL UNIQUE
        CHECK (position_name IN ('менеджер', 'бухгалтер', 'коллектор', 'администратор'))
);

-- E10. Сотрудник
CREATE TABLE employees (
    employee_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(200) NOT NULL,
    passport_number VARCHAR(10) NOT NULL UNIQUE CHECK (passport_number ~ '^[0-9]{10}$'),
    position_id BIGINT NOT NULL REFERENCES positions(position_id) ON DELETE RESTRICT,
    phone TEXT NOT NULL,
    email TEXT NOT NULL,
    hire_date DATE NOT NULL,
    fire_date DATE,
    hired_by_employee_id BIGINT REFERENCES employees(employee_id) ON DELETE RESTRICT,
    fired_by_employee_id BIGINT REFERENCES employees(employee_id) ON DELETE RESTRICT,
    CHECK (fire_date IS NULL OR fire_date >= hire_date),
    CHECK ((fire_date IS NULL) = (fired_by_employee_id IS NULL))
);

-- E3. Отделение
CREATE TABLE departments (
    department_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    address TEXT NOT NULL UNIQUE,
    admin_employee_id BIGINT NOT NULL UNIQUE REFERENCES employees(employee_id) ON DELETE RESTRICT,
    phone TEXT NOT NULL,
    extra_info TEXT
);

-- E1. Должник
CREATE TABLE debtors (
    debtor_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(200) NOT NULL,
    passport_number VARCHAR(10) NOT NULL UNIQUE CHECK (passport_number ~ '^[0-9]{10}$'),
    phone TEXT NOT NULL,
    trusted_person_phone TEXT,
    address TEXT NOT NULL
);

-- E2. Клиент
CREATE TABLE clients (
    client_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_name VARCHAR(200) NOT NULL UNIQUE,
    phone TEXT NOT NULL,
    address TEXT NOT NULL
);

-- E4. Договор
CREATE TABLE contracts (
    contract_number BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    manager_employee_id BIGINT NOT NULL REFERENCES employees(employee_id) ON DELETE RESTRICT,
    client_id BIGINT NOT NULL REFERENCES clients(client_id) ON DELETE RESTRICT,
    debtor_id BIGINT NOT NULL REFERENCES debtors(debtor_id) ON DELETE RESTRICT,
    department_id BIGINT NOT NULL REFERENCES departments(department_id) ON DELETE RESTRICT,
    debt_sum NUMERIC(12, 2) NOT NULL CHECK (debt_sum > 0.00),
    reward_percent NUMERIC(5, 2) NOT NULL CHECK (reward_percent > 0 AND reward_percent <= 100),
    contract_date DATE NOT NULL
);

-- E5. План выплат
CREATE TABLE payment_plans (
    plan_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_number BIGINT NOT NULL REFERENCES contracts(contract_number) ON DELETE CASCADE,
    created_by_employee_id BIGINT NOT NULL REFERENCES employees(employee_id) ON DELETE RESTRICT,
    due_date DATE NOT NULL,
    payment_sum NUMERIC(12, 2) NOT NULL CHECK (payment_sum > 0.00),
    is_penalty BOOLEAN NOT NULL DEFAULT FALSE,
    is_paid BOOLEAN NOT NULL DEFAULT FALSE
);

-- E6. Входящий документ
CREATE TABLE incoming_documents (
    incoming_document_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    debtor_id BIGINT NOT NULL REFERENCES debtors(debtor_id) ON DELETE RESTRICT,
    accountant_employee_id BIGINT NOT NULL REFERENCES employees(employee_id) ON DELETE RESTRICT,
    payment_sum NUMERIC(12, 2) NOT NULL CHECK (payment_sum > 0.00),
    payment_date DATE NOT NULL
);

-- Оплата (связь E5 и E6)
CREATE TABLE payments (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plan_item_id BIGINT NOT NULL REFERENCES payment_plans(plan_item_id) ON DELETE CASCADE,
    incoming_document_id BIGINT NOT NULL REFERENCES incoming_documents(incoming_document_id) ON DELETE CASCADE,
    UNIQUE (plan_item_id, incoming_document_id)
);

-- Получатель
CREATE TABLE recipients (
    recipient_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
);

-- Получатель-Клиент
CREATE TABLE client_recipients (
    recipient_id BIGINT PRIMARY KEY REFERENCES recipients(recipient_id) ON DELETE CASCADE,
    client_id BIGINT NOT NULL UNIQUE REFERENCES clients(client_id) ON DELETE RESTRICT
);

-- Получатель-Сотрудник
CREATE TABLE employee_recipients (
    recipient_id BIGINT PRIMARY KEY REFERENCES recipients(recipient_id) ON DELETE CASCADE,
    employee_id BIGINT NOT NULL UNIQUE REFERENCES employees(employee_id) ON DELETE RESTRICT
);

-- E7. Исходящий документ
CREATE TABLE outgoing_documents (
    outgoing_document_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    recipient_id BIGINT NOT NULL REFERENCES recipients(recipient_id) ON DELETE RESTRICT,
    accountant_employee_id BIGINT NOT NULL REFERENCES employees(employee_id) ON DELETE RESTRICT,
    plan_item_id BIGINT REFERENCES payment_plans(plan_item_id) ON DELETE RESTRICT,
    payment_sum NUMERIC(12, 2) NOT NULL CHECK (payment_sum > 0.00),
    payment_date DATE NOT NULL
);

-- E9. Услуга
CREATE TABLE services (
    service_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    service_name VARCHAR(150) NOT NULL UNIQUE,
    description TEXT,
    price NUMERIC(12, 2) NOT NULL CHECK (price > 0.00)
);

-- E8. Мероприятие
CREATE TABLE events (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    debtor_id BIGINT NOT NULL REFERENCES debtors(debtor_id) ON DELETE RESTRICT,
    event_date DATE NOT NULL
);

-- МероприятиеСотрудник
CREATE TABLE event_employees (
    employee_id BIGINT NOT NULL REFERENCES employees(employee_id) ON DELETE RESTRICT,
    event_id BIGINT NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    PRIMARY KEY (employee_id, event_id)
);

-- МероприятиеУслуга
CREATE TABLE event_services (
    service_id BIGINT NOT NULL REFERENCES services(service_id) ON DELETE RESTRICT,
    event_id BIGINT NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    is_successful BOOLEAN,
    PRIMARY KEY (service_id, event_id)
);
