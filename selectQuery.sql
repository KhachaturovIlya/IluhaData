-- Запрос 1. Отчёт по клиентам
SELECT cl.company_name AS "Название фирмы",
       cl.phone AS "Телефон фирмы",
       SUM(c.debt_sum * c.reward_percent / 100)::numeric(14, 2) AS "Суммарная награда агентства",
       SUM(c.debt_sum) AS "Суммарный переданный долг",
       COUNT(*) AS "Кол-во договоров"
FROM clients cl
JOIN contracts c ON c.client_id = cl.client_id
GROUP BY cl.client_id, cl.company_name, cl.phone
ORDER BY COUNT(*) ASC, SUM(c.debt_sum * c.reward_percent / 100) DESC;


-- Запрос 2. Успешность стимулирующих мероприятий по отделениям
SELECT d.address AS "Адрес отделения",
       d.phone AS "Телефон отделения",
       s.service_name AS "Мероприятие",
       COALESCE(SUM(es.is_successful::int), 0) AS "Успешно выполнено",
       COUNT(es.is_successful) AS "Выполнено",
       ROUND(AVG(es.is_successful::int), 3) AS "Коэффициент успешности"
FROM departments d
JOIN contracts c ON c.department_id = d.department_id
JOIN events e ON e.debtor_id = c.debtor_id
JOIN event_services es ON es.event_id = e.event_id
JOIN services s ON s.service_id = es.service_id
GROUP BY d.department_id, d.address, d.phone, s.service_id, s.service_name
ORDER BY d.address, s.service_name;


-- Запрос 3. Финансовый отчёт по месяцам (с 1 июля прошлого года)
WITH months AS (
    SELECT d::date AS start_date,
           (d + INTERVAL '1 month')::date - 1 AS last_date
    FROM generate_series(date_trunc('year', CURRENT_DATE) - INTERVAL '6 months',
                         date_trunc('month', CURRENT_DATE),
                         INTERVAL '1 month') AS d
),
contract_paid AS (
    SELECT c.contract_number, c.contract_date, c.debt_sum,
           CASE WHEN MIN(p.is_paid::int) = 1 THEN MAX(i.payment_date) END AS paid_date
    FROM contracts c
    JOIN payment_plans p ON p.contract_number = c.contract_number AND NOT p.is_penalty
    LEFT JOIN payments pay ON pay.plan_item_id = p.plan_item_id
    LEFT JOIN incoming_documents i ON i.incoming_document_id = pay.incoming_document_id
    GROUP BY c.contract_number, c.contract_date, c.debt_sum
),
monthly AS (
    SELECT m.start_date, m.last_date,
           (SELECT COALESCE(SUM(debt_sum), 0) FROM contract_paid WHERE contract_date < m.start_date) AS total_start,
           (SELECT COALESCE(SUM(debt_sum), 0) FROM contract_paid WHERE paid_date < m.start_date) AS paid_start,
           (SELECT COALESCE(SUM(debt_sum), 0) FROM contract_paid WHERE contract_date <= m.last_date) AS total_end,
           (SELECT COALESCE(SUM(debt_sum), 0) FROM contract_paid WHERE paid_date <= m.last_date) AS paid_end,
           (SELECT COUNT(*) FROM contracts WHERE contract_date BETWEEN m.start_date AND m.last_date) AS new_cnt,
           (SELECT COALESCE(SUM(debt_sum), 0) FROM contracts WHERE contract_date BETWEEN m.start_date AND m.last_date) AS new_sum,
           (SELECT COUNT(*) FROM incoming_documents WHERE payment_date BETWEEN m.start_date AND m.last_date) AS in_cnt,
           (SELECT COALESCE(SUM(payment_sum), 0) FROM incoming_documents WHERE payment_date BETWEEN m.start_date AND m.last_date) AS in_sum,
           (SELECT COUNT(*) FROM outgoing_documents WHERE payment_date BETWEEN m.start_date AND m.last_date) AS out_cnt,
           (SELECT COALESCE(SUM(payment_sum), 0) FROM outgoing_documents WHERE payment_date BETWEEN m.start_date AND m.last_date) AS out_sum
    FROM months m
)
SELECT (ARRAY['январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
              'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь'])[EXTRACT(MONTH FROM start_date)::int]
       || ' ' || EXTRACT(YEAR FROM start_date)::int AS "Месяц",
       total_start - paid_start AS "Неоплаченные договоры на начало",
       paid_start AS "Оплаченные договоры на начало",
       total_start AS "Всего договоров на начало",
       new_cnt AS "Новых договоров, шт",
       new_sum AS "Новых договоров, сумма",
       in_cnt AS "Входящих платежей, шт",
       in_sum AS "Входящих платежей, сумма",
       out_cnt AS "Исходящих платежей, шт",
       out_sum AS "Исходящих платежей, сумма",
       total_end - paid_end AS "Неоплаченные договоры на конец",
       in_sum - out_sum AS "Прибыль за месяц"
FROM monthly
ORDER BY start_date;

-- Запрос 4. Должники, просрочившие более 3 пунктов плана
WITH debtor_plan AS (
    SELECT c.debtor_id, p.plan_item_id, p.due_date, p.payment_sum,
           CASE WHEN p.is_paid THEN 'paid'
                WHEN p.due_date < CURRENT_DATE THEN 'overdue'
                ELSE 'future' END AS state
    FROM contracts c
    JOIN payment_plans p ON p.contract_number = c.contract_number
)
SELECT d.full_name AS "ФИО должника",
       SUM(p.payment_sum) AS "Общая сумма долга",
       o.oldest_due AS "Дата самой старой задолженности",
       SUM(p.payment_sum) FILTER (WHERE p.state = 'overdue' AND p.due_date = o.oldest_due) AS "Сумма самой старой задолженности",
       COUNT(*) 		  FILTER (WHERE p.state = 'overdue') AS "Неоплаченных просроченных, шт",
       SUM(p.payment_sum) FILTER (WHERE p.state = 'overdue') AS "Неоплаченных просроченных, сумма",
       COUNT(*)           FILTER (WHERE p.state = 'future') AS "Срок оплаты не истёк, шт",
       ROUND(100 * SUM(CASE WHEN p.state = 'paid' THEN p.payment_sum ELSE 0 END) / SUM(p.payment_sum), 2) AS "% долга оплачено",
       ROUND(100 * SUM(CASE WHEN p.state <> 'paid' THEN p.payment_sum ELSE 0 END) / SUM(p.payment_sum), 2) AS "% долга к оплате",
       ROUND(100 * SUM(CASE WHEN p.state = 'overdue' THEN p.payment_sum ELSE 0 END) / SUM(p.payment_sum), 2) AS "% к оплате, просрочено",
       ROUND(100 * SUM(CASE WHEN p.state = 'future' THEN p.payment_sum ELSE 0 END) / SUM(p.payment_sum), 2) AS "% к оплате, не просрочено"
FROM debtors d
JOIN debtor_plan p ON p.debtor_id = d.debtor_id
JOIN (SELECT debtor_id, MIN(due_date) AS oldest_due
      FROM debtor_plan
      WHERE state = 'overdue'
      GROUP BY debtor_id) o ON o.debtor_id = d.debtor_id
GROUP BY d.debtor_id, d.full_name, o.oldest_due
HAVING SUM(CASE WHEN p.state = 'overdue' THEN 1 ELSE 0 END) > 3
ORDER BY "Неоплаченных просроченных, шт" DESC, d.full_name;

-- Запрос 5. Рейтинг популярности стимулирующих мероприятий
SELECT s.service_name AS "Мероприятие",
       COUNT(*) AS "Проведено всего",
       SUM(CASE WHEN TO_CHAR(e.event_date, 'YYYY-MM') = TO_CHAR(CURRENT_DATE - INTERVAL '1 month', 'YYYY-MM')
                THEN 1 ELSE 0 END) AS "В прошлом месяце",
       SUM(CASE WHEN TO_CHAR(e.event_date, 'YYYY-MM') = TO_CHAR(CURRENT_DATE, 'YYYY-MM')
                THEN 1 ELSE 0 END) AS "В текущем месяце",
       s.price AS "Цена (текущая)",
       MAX(e.event_date) AS "Дата последнего проведения",
       (SELECT d.full_name
        FROM event_services es2
        JOIN events e2 ON e2.event_id = es2.event_id
        JOIN debtors d ON d.debtor_id = e2.debtor_id
        WHERE es2.service_id = s.service_id
        ORDER BY e2.event_date DESC, e2.event_id DESC
        LIMIT 1) AS "Последний должник"
FROM services s
LEFT JOIN event_services es ON es.service_id = s.service_id
LEFT JOIN events e ON e.event_id = es.event_id
GROUP BY s.service_id, s.service_name, s.price
ORDER BY COUNT(e.event_id) DESC, s.service_name;
