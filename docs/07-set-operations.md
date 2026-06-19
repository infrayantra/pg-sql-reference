# 7. Set Operations & Advanced SELECT

## UNION, INTERSECT, EXCEPT

All combine results of SELECT statements. Column count and compatible types required.

```sql
-- UNION — distinct rows from both
SELECT name FROM ref.employees
UNION
SELECT name FROM ref.customers;

-- UNION ALL — keeps duplicates (faster, no dedup sort)
SELECT status FROM ref.orders
UNION ALL
SELECT 'archived' WHERE false;  -- example second branch

-- INTERSECT — rows in both
SELECT email FROM ref.employees
INTERSECT
SELECT email FROM ref.customers;

-- EXCEPT — rows in first but not second
SELECT id FROM ref.customers
EXCEPT
SELECT customer_id FROM ref.orders;
```

### Ordering set operation results

```sql
(SELECT name, 'employee' AS type FROM ref.employees)
UNION ALL
(SELECT name, 'customer' FROM ref.customers)
ORDER BY name;
-- Parentheses required when ORDER BY applies to combined result
```

---

## DISTINCT ON (PostgreSQL Extension)

Keep first row of each group after sorting.

```sql
-- Highest-paid employee per department
SELECT DISTINCT ON (department_id)
       department_id, name, salary
FROM ref.employees
ORDER BY department_id, salary DESC;

-- Latest order per customer
SELECT DISTINCT ON (customer_id)
       customer_id, id AS order_id, total, created_at
FROM ref.orders
ORDER BY customer_id, created_at DESC;
```

💡 Requires index `(department_id, salary DESC)` for optimal performance.

---

## VALUES Clause — Inline Table Constructor

```sql
SELECT * FROM (VALUES
  (1, 'Alice'),
  (2, 'Bob'),
  (3, 'Carol')
) AS t(id, name);

INSERT INTO ref.departments (name, budget)
SELECT name, budget FROM (VALUES
  ('Ops', 100000),
  ('Support', 120000)
) AS v(name, budget);
```

---

## TABLE Command

Shorthand for `SELECT * FROM`:

```sql
TABLE ref.employees;
-- Same as: SELECT * FROM ref.employees;
```

---

## SELECT INTO

Create table from query result (one-shot ETL).

```sql
SELECT * INTO ref.employees_backup
FROM ref.employees
WHERE NOT is_active;

-- With temp/unlogged options
SELECT * INTO TEMP TABLE active_employees
FROM ref.employees WHERE is_active;
```

Prefer `CREATE TABLE AS` (CTAS) for explicit control:

```sql
CREATE TABLE ref.employees_archive AS
SELECT * FROM ref.employees WHERE hired_at < '2018-01-01';

-- With no data (structure only)
CREATE TABLE ref.employees_copy (LIKE ref.employees INCLUDING ALL);
```

---

## Generate Series

```sql
-- Integer series
SELECT generate_series(1, 10);
SELECT generate_series(1, 10, 2);  -- step

-- Date series
SELECT generate_series(
  '2024-01-01'::date,
  '2024-12-31'::date,
  '1 month'::interval
)::date AS month_start;

-- Fill gaps in time series data
SELECT gs.day, COALESCE(COUNT(e.id), 0) AS events
FROM generate_series(
  CURRENT_DATE - 7,
  CURRENT_DATE,
  '1 day'::interval
) AS gs(day)
LEFT JOIN ref.events e ON e.occurred_at::date = gs.day::date
GROUP BY gs.day
ORDER BY gs.day;
```

---

## TABLE SAMPLE — Random Sampling

```sql
-- Bernoulli: row-level random sample (~10%)
SELECT * FROM ref.events TABLESAMPLE BERNOULLI (10);

-- System: block-level (faster, less random)
SELECT * FROM ref.events TABLESAMPLE SYSTEM (5) REPEATABLE (42);
```

---

## Row Locking in SELECT

```sql
BEGIN;
SELECT * FROM ref.orders WHERE id = 1 FOR UPDATE;           -- exclusive row lock
SELECT * FROM ref.orders WHERE id = 1 FOR UPDATE NOWAIT;    -- fail immediately if locked
SELECT * FROM ref.orders WHERE id = 1 FOR UPDATE SKIP LOCKED; -- skip locked rows
SELECT * FROM ref.orders WHERE id = 1 FOR SHARE;            -- shared lock
COMMIT;
```

Use `SKIP LOCKED` for job queue patterns:

```sql
UPDATE ref.jobs
SET status = 'processing'
WHERE id = (
  SELECT id FROM ref.jobs
  WHERE status = 'pending'
  ORDER BY created_at
  FOR UPDATE SKIP LOCKED
  LIMIT 1
)
RETURNING *;
```

---

## Next

→ [08. Data Types & Casting](./08-data-types.md)
