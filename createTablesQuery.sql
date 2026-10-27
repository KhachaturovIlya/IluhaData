-- 1. Должности (правило 1: 4 должности; правило 13: у сотрудника одна должность)
CREATE TABLE positions (
    position_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    position_code VARCHAR(20) NOT NULL UNIQUE,
    position_name VARCHAR(100) NOT NULL UNIQUE
        CHECK (position_name IN ('менеджер', 'бухгалтер', 'коллектор', 'администратор'))
);

-- 2. Сотрудники
CREATE TABLE employees (
    employee_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    passport_number VARCHAR(10) NOT NULL UNIQUE CHECK (passport_number ~ '^[0-9]{10}$'),
    position_id BIGINT NOT NULL REFERENCES positions(position_id) ON DELETE RESTRICT,
    phone TEXT NOT NULL,
    email TEXT NOT NULL,
    hire_date DATE NOT NULL,
    fire_date DATE,
    hired_by_employee_id BIGINT REFERENCES employees(employee_id) ON DELETE RESTRICT, -- NULL у самого первого админа
    fired_by_employee_id BIGINT REFERENCES employees(employee_id) ON DELETE RESTRICT, -- правило 16: не более одного
    CHECK (fire_date IS NULL OR fire_date >= hire_date),
    CHECK ((fire_date IS NULL) = (fired_by_employee_id IS NULL))
);

-- 3. Отделения (правило 17: один адрес — одно отделение; правило 14: админ отвечает за одно отделение)
CREATE TABLE departments (
    department_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    address TEXT NOT NULL UNIQUE,
    admin_employee_id BIGINT NOT NULL UNIQUE REFERENCES employees(employee_id) ON DELETE RESTRICT,
    phone TEXT NOT NULL,
    extra_info TEXT
);

-- 4. Должники
CREATE TABLE debtors (
    debtor_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(200) NOT NULL,
    passport_number VARCHAR(10) NOT NULL UNIQUE CHECK (passport_number ~ '^[0-9]{10}$'),
    phone TEXT NOT NULL,
    trusted_person_phone TEXT,
    address TEXT NOT NULL
);

-- 5. Клиенты (правило 18: уникальное название организации)
CREATE TABLE clients (
    client_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_name VARCHAR(200) NOT NULL UNIQUE,
    phone TEXT NOT NULL,
    address TEXT NOT NULL
);

-- 6. Договоры (правило 15: у клиента может быть несколько договоров)
CREATE TABLE contracts (
    contract_number BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    manager_employee_id BIGINT NOT NULL REFERENCES employees(employee_id) ON DELETE RESTRICT,
    client_id BIGINT NOT NULL REFERENCES clients(client_id) ON DELETE RESTRICT,
    debtor_id BIGINT NOT NULL REFERENCES debtors(debtor_id) ON DELETE RESTRICT,
    debt_sum NUMERIC(12, 2) NOT NULL CHECK (debt_sum > 0.00),
    reward_percent NUMERIC(5, 2) NOT NULL CHECK (reward_percent > 0 AND reward_percent <= 100),
    status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'CLOSED')),
    closed_date DATE,
    closed_by_employee_id BIGINT REFERENCES employees(employee_id) ON DELETE RESTRICT, -- админ, подтвердивший закрытие
    CHECK ((status = 'CLOSED') = (closed_date IS NOT NULL)),
    CHECK ((status = 'CLOSED') = (closed_by_employee_id IS NOT NULL))
);

-- 7. План выплат
CREATE TABLE payment_plans (
    payment_plan_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_number BIGINT NOT NULL REFERENCES contracts(contract_number) ON DELETE CASCADE,
    created_by_employee_id BIGINT NOT NULL REFERENCES employees(employee_id) ON DELETE RESTRICT,
    due_date DATE NOT NULL,
    payment_sum NUMERIC(12, 2) NOT NULL CHECK (payment_sum > 0.00),
    is_penalty BOOLEAN NOT NULL DEFAULT FALSE,
    is_paid BOOLEAN NOT NULL DEFAULT FALSE
);

-- 8. Входящие платёжные документы
CREATE TABLE incoming_documents (
    incoming_document_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    debtor_id BIGINT NOT NULL REFERENCES debtors(debtor_id) ON DELETE RESTRICT,
    accountant_employee_id BIGINT NOT NULL REFERENCES employees(employee_id) ON DELETE RESTRICT,
    payment_sum NUMERIC(12, 2) NOT NULL CHECK (payment_sum > 0.00),
    payment_date DATE NOT NULL
);

-- 9. Оплата: связь «платёж ↔ пункт плана» (правило 7: один платёж закрывает несколько пунктов)
CREATE TABLE payments (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_plan_id BIGINT NOT NULL REFERENCES payment_plans(payment_plan_id) ON DELETE CASCADE,
    incoming_document_id BIGINT NOT NULL REFERENCES incoming_documents(incoming_document_id) ON DELETE CASCADE,
    UNIQUE (payment_plan_id, incoming_document_id)
);

-- 10. Получатели (супертип) и подтипы
CREATE TABLE recipients (
    recipient_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
);

CREATE TABLE client_recipients (
    recipient_id BIGINT PRIMARY KEY REFERENCES recipients(recipient_id) ON DELETE CASCADE,
    client_id BIGINT NOT NULL UNIQUE REFERENCES clients(client_id) ON DELETE RESTRICT
);

CREATE TABLE employee_recipients (
    recipient_id BIGINT PRIMARY KEY REFERENCES recipients(recipient_id) ON DELETE CASCADE,
    employee_id BIGINT NOT NULL UNIQUE REFERENCES employees(employee_id) ON DELETE RESTRICT
);

-- 11. Исходящие платёжные документы
CREATE TABLE outgoing_documents (
    outgoing_document_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    recipient_id BIGINT NOT NULL REFERENCES recipients(recipient_id) ON DELETE RESTRICT,
    accountant_employee_id BIGINT NOT NULL REFERENCES employees(employee_id) ON DELETE RESTRICT,
    payment_plan_id BIGINT REFERENCES payment_plans(payment_plan_id) ON DELETE RESTRICT, -- NULL для выплат за мероприятия
    document_type VARCHAR(50) NOT NULL
        CHECK (document_type IN ('DEBT_RETURN', 'REWARD', 'EVENT_PAYMENT')),
    payment_sum NUMERIC(12, 2) NOT NULL CHECK (payment_sum > 0.00),
    payment_date DATE NOT NULL
);

-- 12. Услуги коллекторов
CREATE TABLE services (
    service_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    service_name VARCHAR(150) NOT NULL UNIQUE,
    description TEXT
);

-- 13. Стимулирующие мероприятия
CREATE TABLE events (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    debtor_id BIGINT NOT NULL REFERENCES debtors(debtor_id) ON DELETE RESTRICT,
    event_date DATE NOT NULL
);

CREATE TABLE event_employees (
    employee_id BIGINT NOT NULL REFERENCES employees(employee_id) ON DELETE RESTRICT,
    event_id BIGINT NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    PRIMARY KEY (employee_id, event_id)
);

CREATE TABLE event_services (
    service_id BIGINT NOT NULL REFERENCES services(service_id) ON DELETE RESTRICT,
    event_id BIGINT NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    is_successful BOOLEAN, -- NULL = ещё не выполнена
    PRIMARY KEY (service_id, event_id)
);
