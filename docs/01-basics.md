# 1. Basics: DDL, DML, and Data Types

## SELECT — Retrieving Data

```sql
SELECT [ALL | DISTINCT]
       select_list
FROM   table_reference
[WHERE condition]
[GROUP BY grouping_elements]
[HAVING condition]
[WINDOW window_name AS (window_definition) [, ...]]
[ORDER BY sort_expression [ASC | DESC] [NULLS {FIRST | LAST}] [, ...]]
[LIMIT { count | ALL } [OFFSET start]]
[FOR { UPDATE | NO KEY UPDATE | SHARE | KEY SHARE } [OF table_name [, ...]] [NOWAIT | SKIP LOCKED]]
[FOR { UPDATE | SHARE } [OF table_name [, ...]] [NOWAIT | SKIP LOCKED]];
```

### Basic queries

```sql
-- All columns
SELECT * FROM ref.employees;

-- Specific columns with alias
SELECT e.name AS employee_name, e.salary
FROM ref.employees AS e;

-- Expressions in SELECT list
SELECT name,
       salary,
       salary * 12 AS annual_salary,
       hired_at + interval '1 year' AS first_anniversary
FROM ref.employees;

-- Column ordinal in ORDER BY (avoid in production — fragile)
SELECT name, salary FROM ref.employees ORDER BY 2 DESC;
```

### INSERT

```sql
-- Single row
INSERT INTO ref.departments (name, budget)
VALUES ('Marketing', 200000);

-- Multiple rows
INSERT INTO ref.departments (name, budget) VALUES
  ('Legal', 180000),
  ('Finance', 400000);

-- INSERT ... SELECT
INSERT INTO ref.employees (name, email, department_id, salary, hired_at)
SELECT 'Intern ' || id, 'intern' || id || '@co.com', 1, 45000, CURRENT_DATE
FROM generate_series(1, 3) AS id;

-- RETURNING clause — get generated values back
INSERT INTO ref.customers (name, email)
VALUES ('NewCo', 'hello@newco.com')
RETURNING id, created_at;

-- DEFAULT values
INSERT INTO ref.orders (customer_id) VALUES (1) RETURNING id, status, created_at;
```

### UPDATE

```sql
UPDATE ref.employees
SET salary = salary * 1.05,
    is_active = true
WHERE department_id = 1
  AND is_active = true
RETURNING id, name, salary;

-- Update from another table
UPDATE ref.orders o
SET total = sub.sum_total
FROM (
  SELECT order_id, SUM(quantity * unit_price) AS sum_total
  FROM ref.order_items
  GROUP BY order_id
) sub
WHERE o.id = sub.order_id
  AND o.total IS NULL;
```

### DELETE

```sql
DELETE FROM ref.events
WHERE occurred_at < now() - interval '90 days'
RETURNING id;

-- DELETE using USING (join form)
DELETE FROM ref.order_items oi
USING ref.orders o
WHERE oi.order_id = o.id
  AND o.status = 'cancelled';
```

---

## Data Definition Language (DDL)

### CREATE TABLE

```sql
CREATE TABLE ref.audit_log (
  id          BIGSERIAL PRIMARY KEY,
  table_name  TEXT NOT NULL,
  operation   TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
  row_data    JSONB,
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  changed_by  TEXT DEFAULT current_user
);

-- Temporary table (session-scoped, dropped at session end)
CREATE TEMP TABLE staging (id INT, raw_data TEXT) ON COMMIT DROP;

-- UNLOGGED table (no WAL — faster, not crash-safe)
CREATE UNLOGGED TABLE ref.cache_entries (
  key   TEXT PRIMARY KEY,
  value JSONB,
  expires_at TIMESTAMPTZ
);
```

### Constraints

| Constraint | Purpose |
|------------|---------|
| `PRIMARY KEY` | Unique + NOT NULL; one per table |
| `UNIQUE` | No duplicate values (NULLs allowed, multiple NULLs in PG) |
| `NOT NULL` | Column cannot be NULL |
| `CHECK` | Boolean expression must hold |
| `FOREIGN KEY` | Referential integrity |
| `EXCLUDE` | Prevent overlapping rows (ranges, etc.) |

```sql
CREATE TABLE ref.bookings (
  id         SERIAL PRIMARY KEY,
  room_id    INT NOT NULL,
  guest_name TEXT NOT NULL,
  period     TSTZRANGE NOT NULL,
  EXCLUDE USING GIST (room_id WITH =, period WITH &&)
);

-- Named constraints
ALTER TABLE ref.employees
  ADD CONSTRAINT employees_salary_positive CHECK (salary > 0);

-- Deferrable FK (checked at commit, not each statement)
CREATE TABLE ref.child (
  id       SERIAL PRIMARY KEY,
  parent_id INT REFERENCES ref.parent(id)
    DEFERRABLE INITIALLY DEFERRED
);
```

### Foreign Key actions

```sql
REFERENCES parent(id)
  ON DELETE CASCADE    -- delete child rows
  ON DELETE SET NULL   -- set FK column to NULL
  ON DELETE RESTRICT   -- prevent delete (default)
  ON UPDATE CASCADE    -- update FK when parent PK changes
```

### ALTER TABLE

```sql
ALTER TABLE ref.employees ADD COLUMN phone TEXT;
ALTER TABLE ref.employees DROP COLUMN phone;
ALTER TABLE ref.employees RENAME COLUMN email TO work_email;
ALTER TABLE ref.employees ALTER COLUMN salary SET DEFAULT 50000;
ALTER TABLE ref.employees ALTER COLUMN salary SET NOT NULL;
ALTER TABLE ref.employees ADD CONSTRAINT emp_email_unique UNIQUE (work_email);
```

### DROP & TRUNCATE

```sql
DROP TABLE IF EXISTS ref.staging CASCADE;  -- CASCADE drops dependent objects
TRUNCATE ref.events RESTART IDENTITY CASCADE;  -- fast delete all rows, reset sequences
```

---

## Core Data Types

### Numeric

| Type | Description |
|------|-------------|
| `SMALLINT` | 2 bytes, -32768 to 32767 |
| `INTEGER` / `INT` | 4 bytes |
| `BIGINT` | 8 bytes |
| `NUMERIC(p,s)` / `DECIMAL` | Exact arbitrary precision |
| `REAL` | 4-byte float |
| `DOUBLE PRECISION` | 8-byte float |
| `SERIAL` / `BIGSERIAL` | Auto-increment (sequence-backed) |

```sql
SELECT 0.1::REAL + 0.2::REAL;           -- imprecise float
SELECT 0.1::NUMERIC + 0.2::NUMERIC;     -- exact: 0.3
SELECT nextval(pg_get_serial_sequence('ref.employees', 'id'));
```

### Text

| Type | Description |
|------|-------------|
| `TEXT` | Unlimited length (preferred over VARCHAR) |
| `VARCHAR(n)` | Variable with limit |
| `CHAR(n)` | Fixed width, space-padded |

```sql
SELECT 'hello' || ' ' || 'world';           -- concatenation
SELECT format('Hello, %s!', 'Alice');       -- printf-style
SELECT left('PostgreSQL', 4), right('PostgreSQL', 2);
SELECT regexp_replace('foo123bar', '\d+', '-', 'g');
```

### Boolean

```sql
SELECT true, false, NULL::boolean;
SELECT * FROM ref.employees WHERE is_active IS TRUE;  -- prefer IS TRUE over = true for NULL safety
```

### Temporal

| Type | Storage | Range |
|------|---------|-------|
| `DATE` | date only | 4713 BC – 5874897 AD |
| `TIME` | time of day | |
| `TIMETZ` | time + offset | |
| `TIMESTAMP` | date + time (no TZ) | |
| `TIMESTAMPTZ` | date + time + TZ | **Use this for timestamps** |

```sql
SELECT now(), CURRENT_DATE, CURRENT_TIMESTAMP;
SELECT '2024-06-15'::date + interval '3 months';
SELECT age('2024-06-15'::date, '2020-01-01'::date);
SELECT date_part('dow', now());  -- day of week (0=Sunday)
SELECT extract(epoch FROM now()); -- Unix timestamp
```

⚠️ **Never use `TIMESTAMP WITHOUT TIME ZONE` for event times** — ambiguous across DST and time zones.

### UUID `(PG 13+ gen_random_uuid built-in)`

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- if gen_random_uuid not available
SELECT gen_random_uuid();
CREATE TABLE ref.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id INT,
  expires_at TIMESTAMPTZ
);
```

### Sequences

```sql
CREATE SEQUENCE ref.order_number_seq START 1000 INCREMENT 1;
SELECT nextval('ref.order_number_seq');
SELECT currval('ref.order_number_seq');
SELECT setval('ref.order_number_seq', 5000, true);  -- third arg: is_called
```

---

## NULL Semantics

```sql
-- Three-valued logic: TRUE, FALSE, UNKNOWN (NULL)
SELECT NULL = NULL;        -- NULL (unknown), not TRUE
SELECT NULL IS NULL;       -- TRUE
SELECT NULL IS DISTINCT FROM NULL;  -- FALSE

-- COALESCE — first non-NULL
SELECT COALESCE(phone, email, 'no contact') FROM ref.employees;

-- NULLIF — NULL if equal
SELECT val / NULLIF(divisor, 0) FROM t;

-- Filtering NULLs
SELECT * FROM ref.employees WHERE manager_id IS NULL;
SELECT * FROM ref.employees WHERE manager_id IS NOT NULL;
```

---

## Comments & Documentation

```sql
COMMENT ON TABLE ref.employees IS 'Company employees';
COMMENT ON COLUMN ref.employees.salary IS 'Annual base salary in USD';
```

---

## Next

→ [02. Filtering, Sorting & Pagination](./02-filtering-sorting.md)
