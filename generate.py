import os
import random
from datetime import timedelta
from decimal import Decimal, ROUND_HALF_UP

import psycopg2
from dotenv import load_dotenv
from faker import Faker
from psycopg2 import sql
from psycopg2.extras import execute_values

SEED = 42

N_DEBTORS = 10_000
N_CONTRACTS = 10_000  # по одному договору на должника
N_EVENTS = 10_000
N_CLIENTS = 2_000
N_DEPARTMENTS = 100
N_ADMINS = 120  # не меньше N_DEPARTMENTS: админ отделения уникален
N_MANAGERS = 300
N_ACCOUNTANTS = 150
N_COLLECTORS = 430

HISTORY_DAYS = 500
LIMIT_DAYS = 365
PENALTY_RATE = Decimal("0.05")
MANAGER_SHARE = Decimal("0.10")
EVENT_PAYMENT = Decimal("300.00")
CENT = Decimal("0.01")

POSITIONS = [("MGR", "менеджер"), ("ACC", "бухгалтер"), ("COL", "коллектор"), ("ADM", "администратор")]
POS_MANAGER, POS_ACCOUNTANT, POS_COLLECTOR, POS_ADMIN = 1, 2, 3, 4

SERVICES = [
    ("Телефонный звонок должнику", "Первичный контакт и напоминание о долге"),
    ("Звонок доверенному лицу", "Уточнение контактов и информирование доверенного лица"),
    ("SMS-напоминание", "Отправка сообщения с реквизитами и сроками платежа"),
    ("Письменное уведомление", "Заказное письмо с требованием погасить задолженность"),
    ("Выезд по месту жительства", "Личная беседа с должником по адресу проживания"),
    ("Выезд по месту работы", "Встреча с должником на работе"),
    ("Переговоры о реструктуризации", "Согласование нового графика платежей"),
    ("Досудебная претензия", "Подготовка и вручение претензии"),
    ("Проверка адреса проживания", "Подтверждение актуального адреса"),
    ("Проверка места работы", "Подтверждение места работы и дохода"),
    ("Встреча в отделении", "Приглашение должника в отделение агентства"),
    ("Разъяснение последствий неуплаты", "Информирование о пенях и сроках давности"),
    ("Согласование частичной оплаты", "Договорённость о внесении части долга"),
    ("Контрольный звонок", "Проверка выполнения договорённостей"),
    ("Повторный выезд", "Повторное посещение должника"),
    ("Опрос соседей", "Уточнение места нахождения должника"),
    ("Оформление расписки", "Фиксация обязательства должника письменно"),
    ("Сопровождение платежа", "Помощь должнику в проведении оплаты"),
    ("Вручение графика платежей", "Передача плана выплат под подпись"),
    ("Предупреждение о передаче приставам", "Уведомление о последствиях по истечении срока"),
    ("Мессенджер-уведомление", "Напоминание через мессенджер"),
    ("Личный визит с уведомлением", "Вручение документов лично"),
    ("Переговоры с поручителем", "Обсуждение погашения с поручителем"),
    ("Сверка данных по договору", "Уточнение суммы и сроков с должником"),
]

fake = Faker("ru_RU")


def money(value):
    return Decimal(value).quantize(CENT, rounding=ROUND_HALF_UP)


def person_name():
    if random.random() < 0.5:
        return f"{fake.last_name_male()} {fake.first_name_male()} {fake.middle_name_male()}"
    return f"{fake.last_name_female()} {fake.first_name_female()} {fake.middle_name_female()}"


def passport_factory():
    used = set()

    def make():
        while True:
            value = str(random.randint(10**9, 10**10 - 1))
            if value not in used:
                used.add(value)
                return value

    return make


def unique_values(count, producer):
    result, used = [], set()
    while len(result) < count:
        value = producer()
        if value in used:
            value = f"{value} ({len(result) + 1})"
        if value in used:
            continue
        used.add(value)
        result.append(value)
    return result


def build_plan(debt):
    # < 100 т.р.: еженедельные 10 т.р. и остаток; иначе 10 равных платежей
    if debt < 100_000:
        amounts, left = [], debt
        while left >= 10_000:
            amounts.append(Decimal(10_000))
            left -= 10_000
        if left > 0:
            amounts.append(left)
        return amounts
    part = money(debt / 10)
    return [part] * 9 + [debt - part * 9]


def ceil_weeks(delta):
    return max(0, -(-delta.days // 7))


def make_penalties(item, weeks, paid_on=None):
    penalties, previous = [], item["sum"]
    for week in range(1, weeks + 1):
        amount = money(previous * PENALTY_RATE)
        if amount < CENT:
            break
        penalties.append({
            "due": item["due"] + timedelta(days=7 * week),
            "sum": amount,
            "penalty": True,
            "paid_on": paid_on,
        })
        previous = amount
    return penalties


def simulate_contract(sign_date, debt, today):
    limit_date = sign_date + timedelta(days=LIMIT_DAYS)
    horizon = min(today, limit_date)
    items = [
        {"due": sign_date + timedelta(days=7 * number), "sum": amount, "penalty": False, "paid_on": None}
        for number, amount in enumerate(build_plan(debt), 1)
    ]

    behavior = random.choices(("good", "late", "bad"), weights=(45, 35, 20))[0]
    pay_dates = []
    if behavior == "good":
        pay_dates = [item["due"] for item in items if item["due"] <= horizon]
    else:
        max_events = random.randint(0, 2) if behavior == "bad" else 50
        current = items[0]["due"] + timedelta(days=random.randint(0, 21))
        while current <= horizon and len(pay_dates) < max_events:
            pay_dates.append(current)
            current += timedelta(days=random.randint(3, 28))

    penalties = []
    for pay_date in pay_dates:
        for item in items:
            if item["paid_on"] is None and item["due"] <= pay_date:
                item["paid_on"] = pay_date
                weeks = ceil_weeks(min(pay_date, limit_date) - item["due"])
                penalties.extend(make_penalties(item, weeks, paid_on=pay_date))

    for item in items:
        if item["paid_on"] is None and item["due"] < horizon:
            penalties.extend(make_penalties(item, ceil_weeks(horizon - item["due"])))

    if all(item["paid_on"] for item in items):
        last_payment = max(item["paid_on"] for item in items)
        closed_date = min(today, last_payment + timedelta(days=random.randint(0, 5)))
    elif limit_date <= today:
        closed_date = limit_date
    else:
        closed_date = None
    return items, penalties, closed_date


def generate_data(today):
    random.seed(SEED)
    Faker.seed(SEED)
    passport = passport_factory()

    # E11. Должность
    positions = list(POSITIONS)

    # E10. Сотрудник (сначала админы, затем менеджеры, бухгалтеры, коллекторы)
    employees, fire_dates = [], {}
    for i in range(1, N_ADMINS + 1):
        hire = today - timedelta(days=3000 - i * 5)
        hired_by = None if i == 1 else random.randint(1, i - 1)
        employees.append((person_name(), passport(), POS_ADMIN, fake.phone_number(), fake.email(),
                          hire, None, hired_by, None))
    admin_ids = list(range(1, N_ADMINS + 1))

    def add_staff(position_id, count, can_be_fired):
        for _ in range(count):
            hire = today - timedelta(days=random.randint(600, 2100))
            fire = fired_by = None
            if can_be_fired and random.random() < 0.2:
                fire = today - timedelta(days=random.randint(1, 550))
                fired_by = random.choice(admin_ids)
            employees.append((person_name(), passport(), position_id, fake.phone_number(), fake.email(),
                              hire, fire, random.choice(admin_ids), fired_by))
            fire_dates[len(employees)] = fire

    add_staff(POS_MANAGER, N_MANAGERS, False)
    add_staff(POS_ACCOUNTANT, N_ACCOUNTANTS, False)
    add_staff(POS_COLLECTOR, N_COLLECTORS, True)
    manager_ids = list(range(N_ADMINS + 1, N_ADMINS + N_MANAGERS + 1))
    accountant_ids = list(range(manager_ids[-1] + 1, manager_ids[-1] + N_ACCOUNTANTS + 1))
    collector_ids = list(range(accountant_ids[-1] + 1, accountant_ids[-1] + N_COLLECTORS + 1))
    assert len(employees) == collector_ids[-1]

    # E3. Отделение
    addresses = unique_values(N_DEPARTMENTS, lambda: f"{fake.city()}, {fake.street_address()}")
    departments = [
        (addresses[i], admin_ids[i], fake.phone_number(),
         random.choice([None, "Режим работы: пн-пт 9:00-18:00", "Приём должников по записи",
                        "Есть отдельный кабинет для переговоров"]))
        for i in range(N_DEPARTMENTS)
    ]

    # E1. Должник
    debtors = [
        (person_name(), passport(), fake.phone_number(),
         fake.phone_number() if random.random() < 0.6 else None, fake.address())
        for _ in range(N_DEBTORS)
    ]

    # E2. Клиент
    company_names = unique_values(N_CLIENTS, fake.company)
    clients = [(name, fake.phone_number(), fake.address()) for name in company_names]

    # Получатели: клиенты имеют id 1..N_CLIENTS, сотрудники N_CLIENTS + employee_id
    total_recipients = N_CLIENTS + len(employees)
    recipients = [(i,) for i in range(1, total_recipients + 1)]
    client_recipients = [(c, c) for c in range(1, N_CLIENTS + 1)]
    employee_recipients = [(N_CLIENTS + e, e) for e in range(1, len(employees) + 1)]

    # E4-E7. Договор, план выплат, входящие и исходящие документы, оплата
    contracts, plan_rows, incoming, payments, outgoing = [], [], [], [], []
    for contract_id in range(1, N_CONTRACTS + 1):
        manager_id = random.choice(manager_ids)
        client_id = random.randint(1, N_CLIENTS)
        debtor_id = contract_id
        if random.random() < 0.5:
            debt = Decimal(random.randrange(50, 1000)) * 100
        else:
            debt = Decimal(random.randrange(1000, 10_001)) * 100
        reward_percent = money(random.uniform(5, 30))
        sign_date = today - timedelta(days=random.randint(0, HISTORY_DAYS))

        items, penalties, closed_date = simulate_contract(sign_date, debt, today)
        contracts.append((
            manager_id, client_id, debtor_id, random.randint(1, N_DEPARTMENTS), debt, reward_percent,
            "CLOSED" if closed_date else "ACTIVE", closed_date,
            random.choice(admin_ids) if closed_date else None,
        ))

        paid_groups = {}
        for item in items + penalties:
            creator = random.choice(accountant_ids) if item["penalty"] else manager_id
            plan_rows.append((contract_id, creator, item["due"], item["sum"], item["penalty"],
                              item["paid_on"] is not None))
            item["id"] = len(plan_rows)
            if item["paid_on"] is not None:
                paid_groups.setdefault(item["paid_on"], []).append(item)

        for pay_date in sorted(paid_groups):
            group = paid_groups[pay_date]
            accountant_id = random.choice(accountant_ids)
            incoming.append((debtor_id, accountant_id, sum(i["sum"] for i in group), pay_date))
            document_id = len(incoming)
            out_date = min(today, pay_date + timedelta(days=random.randint(0, 2)))
            for item in group:
                payments.append((item["id"], document_id))
                if item["penalty"]:
                    continue  # пени целиком остаются агентству
                reward = money(item["sum"] * reward_percent / 100)
                outgoing.append((client_id, accountant_id, item["id"], "DEBT_RETURN",
                                 item["sum"] - reward, out_date))
                outgoing.append((N_CLIENTS + manager_id, accountant_id, item["id"], "REWARD",
                                 money(reward * MANAGER_SHARE), out_date))

    # E9. Услуга
    services = list(SERVICES)

    # E8. Мероприятие, участники и услуги
    events, event_employees, event_services = [], [], []
    for event_id in range(1, N_EVENTS + 1):
        event_date = today - timedelta(days=random.randint(0, HISTORY_DAYS))
        events.append((random.randint(1, N_DEBTORS), event_date))

        participants = []
        wanted = random.randint(2, 4)
        while len(participants) < wanted:
            collector_id = random.choice(collector_ids)
            fire = fire_dates[collector_id]
            if collector_id not in participants and (fire is None or fire >= event_date):
                participants.append(collector_id)
        for collector_id in participants:
            event_employees.append((collector_id, event_id))
            outgoing.append((N_CLIENTS + collector_id, random.choice(accountant_ids), None,
                             "EVENT_PAYMENT", EVENT_PAYMENT,
                             min(today, event_date + timedelta(days=random.randint(0, 2)))))

        for service_id in random.sample(range(1, len(services) + 1), random.randint(1, 3)):
            if event_date >= today - timedelta(days=1):
                successful = None
            else:
                successful = random.random() < 0.75
            event_services.append((service_id, event_id, successful))

    return [
        ("positions", "position_code, position_name", positions, False),
        ("employees", "full_name, passport_number, position_id, phone, email, hire_date, fire_date, "
                      "hired_by_employee_id, fired_by_employee_id", employees, False),
        ("departments", "address, admin_employee_id, phone, extra_info", departments, False),
        ("debtors", "full_name, passport_number, phone, trusted_person_phone, address", debtors, False),
        ("clients", "company_name, phone, address", clients, False),
        ("contracts", "manager_employee_id, client_id, debtor_id, department_id, debt_sum, reward_percent, "
                      "status, closed_date, closed_by_employee_id", contracts, False),
        ("payment_plans", "contract_number, created_by_employee_id, due_date, payment_sum, is_penalty, "
                          "is_paid", plan_rows, False),
        ("incoming_documents", "debtor_id, accountant_employee_id, payment_sum, payment_date", incoming, False),
        ("payments", "plan_item_id, incoming_document_id", payments, False),
        ("recipients", "recipient_id", recipients, True),
        ("client_recipients", "recipient_id, client_id", client_recipients, False),
        ("employee_recipients", "recipient_id, employee_id", employee_recipients, False),
        ("outgoing_documents", "recipient_id, accountant_employee_id, plan_item_id, document_type, "
                               "payment_sum, payment_date", outgoing, False),
        ("services", "service_name, description", services, False),
        ("events", "debtor_id, event_date", events, False),
        ("event_employees", "employee_id, event_id", event_employees, False),
        ("event_services", "service_id, event_id, is_successful", event_services, False),
    ]


def main():
    load_dotenv()
    config = {
        "dbname": os.getenv("DB_NAME"),
        "user": os.getenv("DB_USER"),
        "password": os.getenv("DB_PASSWORD"),
        "host": os.getenv("DB_HOST"),
        "port": os.getenv("DB_PORT"),
    }
    conn = psycopg2.connect(**config)
    try:
        with conn, conn.cursor() as cur:
            cur.execute("SELECT CURRENT_DATE")
            data = generate_data(cur.fetchone()[0])
            # Внешние ключи считаются по порядку вставки, поэтому нужна пустая схема.
            cur.execute("LOCK TABLE " + ", ".join(table for table, _, _, _ in data) + " IN EXCLUSIVE MODE")
            for table, _, _, _ in data:
                cur.execute(f"SELECT EXISTS (SELECT 1 FROM {table})")
                if cur.fetchone()[0]:
                    raise SystemExit(f"Таблица {table} уже содержит данные. Нужна пустая схема.")
            for table, columns, rows, override_identity in data:
                cur.execute(
                    "SELECT attname FROM pg_attribute WHERE attrelid = %s::regclass AND attidentity <> ''",
                    (table,),
                )
                identity_columns = [name for (name,) in cur.fetchall()]
                for identity_column in identity_columns:
                    cur.execute(sql.SQL("ALTER TABLE {} ALTER COLUMN {} RESTART WITH 1").format(
                        sql.Identifier(table), sql.Identifier(identity_column),
                    ))
                if rows:
                    overriding = " OVERRIDING SYSTEM VALUE" if override_identity else ""
                    execute_values(cur, f"INSERT INTO {table} ({columns}){overriding} VALUES %s",
                                   rows, page_size=5000)
                    if override_identity:
                        cur.execute("SELECT setval(pg_get_serial_sequence(%s, %s), %s)",
                                    (table, identity_columns[0], len(rows)))
                print(f"{table}: {len(rows)}")
        print("Тестовые данные загружены.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
