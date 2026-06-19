# 16. Advanced Patterns & Recipes

## Upsert (INSERT ... ON CONFLICT)

```sql
INSERT INTO ref.products (sku, name, price)
VALUES ('WDG-001', 'Widget Pro v2', 34.99)
ON CONFLICT (sku) DO UPDATE
SET name = EXCLUDED.name,
    price = EXCLUDED.price;

-- Do nothing on conflict
INSERT INTO ref.customers (email, name)
VALUES ('buyer@acme.com', 'Acme Corp')
ON CONFLICT (email) DO NOTHING;

-- Conditional update
ON CONFLICT (sku) DO UPDATE
SET price = EXCLUDED.price
WHERE ref.products.price <> EXCLUDED.price;

-- Conflict on constraint name
ON CONFLICT ON CONSTRAINT products_sku_key DO UPDATE SET ...
```

Requires UNIQUE index or PRIMARY KEY on conflict target.

---

## MERGE `(PG 15+)`

SQL-standard upsert/delete in one statement:

```sql
MERGE INTO ref.products AS t
USING (VALUES ('WDG-003', 'Widget Max', 49.99)) AS s(sku, name, price)
ON t.sku = s.sku
WHEN MATCHED THEN
  UPDATE SET name = s.name, price = s.price
WHEN NOT MATCHED THEN
  INSERT (sku, name, price) VALUES (s.sku, s.name, s.price);
```

---

## Gaps and Islands

### Gaps — find missing sequences

```sql
WITH ordered AS (
  SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id
  FROM ref.employees
)
SELECT id + 1 AS gap_start, next_id - 1 AS gap_end
FROM ordered
WHERE next_id - id > 1;
```

### Islands — consecutive groups

```sql
WITH flagged AS (
  SELECT occurred_at,
         occurred_at - (ROW_NUMBER() OVER (ORDER BY occurred_at))::int AS grp
  FROM ref.events
)
SELECT MIN(occurred_at) AS island_start, MAX(occurred_at) AS island_end, COUNT(*)
FROM flagged
GROUP BY grp;
```

---

## Pivot / Crosstab

### Conditional aggregation (portable)

```sql
SELECT department_id,
       COUNT(*) FILTER (WHERE salary < 80000)  AS junior,
       COUNT(*) FILTER (WHERE salary BETWEEN 80000 AND 100000) AS mid,
       COUNT(*) FILTER (WHERE salary > 100000) AS senior
FROM ref.employees
GROUP BY department_id;
```

### tablefunc extension

```sql
CREATE EXTENSION tablefunc;
SELECT * FROM crosstab(
  'SELECT department_id, status, count(*) FROM ... GROUP BY 1,2 ORDER BY 1,2',
  'SELECT DISTINCT status FROM ... ORDER BY 1'
) AS ct(dept_id INT, pending INT, paid INT, shipped INT);
```

---

## Running Totals & Moving Averages

```sql
SELECT created_at::date AS day,
       SUM(total) AS daily,
       SUM(SUM(total)) OVER (ORDER BY created_at::date) AS cumulative
FROM ref.orders
GROUP BY created_at::date;

SELECT AVG(total) OVER (
  ORDER BY created_at
  ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
) AS moving_avg_7
FROM ref.orders;
```

---

## Deduplication

```sql
-- Keep lowest id per email
DELETE FROM ref.employees a
USING ref.employees b
WHERE a.email = b.email AND a.id > b.id;

-- Using ctid (physical row id) — not stable across vacuum
DELETE FROM ref.employees a
USING (
  SELECT MIN(ctid) AS keep_ctid, email
  FROM ref.employees GROUP BY email
) d
WHERE a.email = d.email AND a.ctid <> d.keep_ctid;
```

---

## Soft Delete Pattern

```sql
ALTER TABLE ref.employees ADD COLUMN deleted_at TIMESTAMPTZ;

CREATE VIEW ref.employees_active AS
SELECT * FROM ref.employees WHERE deleted_at IS NULL;

-- Partial unique index ignoring soft-deleted
CREATE UNIQUE INDEX employees_email_active
ON ref.employees (email) WHERE deleted_at IS NULL;
```

---

## Temporal / Slowly Changing Dimensions (SCD Type 2)

```sql
CREATE TABLE ref.employee_history (
  emp_id     INT,
  salary     NUMERIC,
  valid_from TIMESTAMPTZ NOT NULL,
  valid_to   TIMESTAMPTZ,
  PRIMARY KEY (emp_id, valid_from)
);

-- Point-in-time query
SELECT * FROM ref.employee_history
WHERE emp_id = 1
  AND valid_from <= '2023-06-01'
  AND (valid_to IS NULL OR valid_to > '2023-06-01');
```

---

## Job Queue Pattern

```sql
CREATE TABLE ref.job_queue (
  id BIGSERIAL PRIMARY KEY,
  payload JSONB,
  status TEXT DEFAULT 'pending',
  locked_at TIMESTAMPTZ,
  locked_by TEXT
);

-- Claim job
UPDATE ref.job_queue
SET status = 'processing', locked_at = now(), locked_by = 'worker-1'
WHERE id = (
  SELECT id FROM ref.job_queue
  WHERE status = 'pending'
  ORDER BY id
  FOR UPDATE SKIP LOCKED
  LIMIT 1
)
RETURNING *;
```

---

## Graph Queries (Recursive CTE)

See [05. Subqueries & CTEs](./05-subqueries-ctes.md) — org charts, bill of materials, friend-of-friend.

---

## Bulk Load

```sql
COPY ref.employees (name, email, department_id, salary, hired_at)
FROM '/path/to/employees.csv'
WITH (FORMAT csv, HEADER true);

-- From STDIN in psql
\copy ref.employees FROM 'employees.csv' CSV HEADER
```

💡 `COPY` is fastest for bulk insert. Disable indexes/triggers only for very large loads with rebuild strategy.

---

## Idempotent Migrations

```sql
CREATE TABLE IF NOT EXISTS ref.schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ DEFAULT now()
);
```

---

## Next

→ [17. Administration & Maintenance](./17-administration.md)
