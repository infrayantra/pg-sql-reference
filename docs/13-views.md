# 13. Views & Materialized Views

## Views (Virtual Tables)

A view stores a **query definition**, not data. Every read re-executes the underlying SQL.

```sql
CREATE VIEW ref.active_employees AS
SELECT e.id, e.name, e.salary, d.name AS department
FROM ref.employees e
LEFT JOIN ref.departments d ON d.id = e.department_id
WHERE e.is_active;

SELECT * FROM ref.active_employees WHERE salary > 90000;
```

### Use case: Simplify complex joins for applications

```sql
CREATE VIEW ref.order_details AS
SELECT
  o.id AS order_id,
  o.status,
  o.total,
  o.created_at,
  c.name AS customer_name,
  c.country,
  p.name AS product_name,
  oi.quantity,
  oi.unit_price,
  oi.quantity * oi.unit_price AS line_total
FROM ref.orders o
JOIN ref.customers c ON c.id = o.customer_id
JOIN ref.order_items oi ON oi.order_id = o.id
JOIN ref.products p ON p.id = oi.product_id;

-- App code: SELECT * FROM ref.order_details WHERE order_id = 1;
```

### Use case: Security — hide sensitive columns

```sql
CREATE VIEW ref.employees_public AS
SELECT id, name, department_id, hired_at
FROM ref.employees;

REVOKE SELECT ON ref.employees FROM app_reader;
GRANT SELECT ON ref.employees_public TO app_reader;
```

### Use case: Computed columns without schema change

```sql
CREATE VIEW ref.employees_with_annual AS
SELECT *,
       salary * 12 AS annual_salary,
       (CURRENT_DATE - hired_at) AS tenure_days
FROM ref.employees;
```

### Updatable views

Simple single-table views (no DISTINCT, GROUP BY, window functions) are auto-updatable:

```sql
CREATE VIEW ref.emp_names AS
SELECT id, name, department_id FROM ref.employees;

UPDATE ref.emp_names SET name = 'Updated' WHERE id = 1;
INSERT INTO ref.emp_names (name, department_id) VALUES ('New Hire', 1);
DELETE FROM ref.emp_names WHERE id = 99;
```

Complex views need `INSTEAD OF` triggers:

```sql
CREATE VIEW ref.dept_summary AS
SELECT department_id, COUNT(*) AS cnt, AVG(salary) AS avg_sal
FROM ref.employees GROUP BY department_id;

-- Not directly updatable — use trigger or update base table
```

### WITH CHECK OPTION

Prevents inserts/updates through view that would become invisible:

```sql
CREATE VIEW ref.high_earners AS
SELECT * FROM ref.employees WHERE salary > 100000
WITH CASCADED CHECK OPTION;

INSERT INTO ref.high_earners (name, salary, ...) VALUES ('X', 50000, ...);
-- ERROR: violates check option
```

### Security barrier & invoker `(PG 15+)`

```sql
CREATE VIEW ref.public_employees
WITH (security_barrier = true) AS
SELECT id, name FROM ref.employees WHERE is_active;

-- security_invoker: runs with caller's permissions
CREATE VIEW ref.salary_summary
WITH (security_invoker = true) AS
SELECT department_id, AVG(salary) FROM ref.employees GROUP BY 1;
```

---

## Materialized Views (Stored Snapshots)

Physically stores query results. **Fast reads, stale data** until refreshed.

```sql
CREATE MATERIALIZED VIEW ref.monthly_revenue AS
SELECT date_trunc('month', created_at) AS month,
       SUM(total) AS revenue,
       COUNT(*) AS order_count
FROM ref.orders
WHERE status IN ('paid', 'shipped')
GROUP BY 1;
```

### Use case: Dashboard / BI aggregates

Pre-compute expensive aggregations refreshed nightly or hourly:

```sql
CREATE MATERIALIZED VIEW ref.dashboard_kpis AS
SELECT
  (SELECT COUNT(*) FROM ref.customers) AS total_customers,
  (SELECT COUNT(*) FROM ref.orders WHERE status = 'paid') AS paid_orders,
  (SELECT COALESCE(SUM(total), 0) FROM ref.orders WHERE status IN ('paid','shipped')) AS total_revenue,
  (SELECT COUNT(*) FROM ref.employees WHERE is_active) AS active_employees;

-- Refresh before dashboard load
REFRESH MATERIALIZED VIEW ref.dashboard_kpis;
SELECT * FROM ref.dashboard_kpis;
```

### Use case: Department payroll summary

```sql
CREATE MATERIALIZED VIEW ref.dept_payroll AS
SELECT d.id AS department_id,
       d.name,
       COUNT(e.id) AS headcount,
       SUM(e.salary) AS total_payroll,
       AVG(e.salary) AS avg_salary,
       MAX(e.salary) AS max_salary
FROM ref.departments d
LEFT JOIN ref.employees e ON e.department_id = d.id AND e.is_active
GROUP BY d.id, d.name;

CREATE UNIQUE INDEX dept_payroll_id ON ref.dept_payroll (department_id);
```

### Use case: Customer lifetime value cache

```sql
CREATE MATERIALIZED VIEW ref.customer_ltv AS
SELECT c.id AS customer_id,
       c.name,
       COUNT(o.id) AS order_count,
       COALESCE(SUM(o.total), 0) AS lifetime_value,
       MIN(o.created_at) AS first_order,
       MAX(o.created_at) AS last_order
FROM ref.customers c
LEFT JOIN ref.orders o ON o.customer_id = c.id
  AND o.status IN ('paid', 'shipped')
GROUP BY c.id, c.name;

CREATE UNIQUE INDEX customer_ltv_id ON ref.customer_ltv (customer_id);
```

### Use case: Search / report snapshot with indexes

Materialized views **can have their own indexes**:

```sql
CREATE MATERIALIZED VIEW ref.product_sales AS
SELECT p.id, p.sku, p.name,
       SUM(oi.quantity) AS units_sold,
       SUM(oi.quantity * oi.unit_price) AS revenue
FROM ref.products p
JOIN ref.order_items oi ON oi.product_id = p.id
GROUP BY p.id, p.sku, p.name;

CREATE INDEX product_sales_revenue ON ref.product_sales (revenue DESC);
CREATE UNIQUE INDEX product_sales_id ON ref.product_sales (id);

SELECT * FROM ref.product_sales ORDER BY revenue DESC LIMIT 10;
```

---

## REFRESH Strategies

### Full refresh (blocks reads)

```sql
REFRESH MATERIALIZED VIEW ref.monthly_revenue;
```

### Concurrent refresh (no read blocking) `(requires UNIQUE index)`

```sql
CREATE UNIQUE INDEX monthly_revenue_month ON ref.monthly_revenue (month);

REFRESH MATERIALIZED VIEW CONCURRENTLY ref.monthly_revenue;
-- Slower; allows SELECT during refresh; requires UNIQUE index on MV
```

### Create empty, populate later

```sql
CREATE MATERIALIZED VIEW ref.heavy_report AS
SELECT ... FROM huge_table ...
WITH NO DATA;

REFRESH MATERIALIZED VIEW ref.heavy_report;
```

### Scheduled refresh (pg_cron extension)

```sql
CREATE EXTENSION pg_cron;
SELECT cron.schedule('refresh-revenue', '0 * * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY ref.monthly_revenue$$);
```

### Incremental refresh pattern (manual)

PostgreSQL has no native incremental MV refresh. Common patterns:

```sql
-- 1. Staging table + swap
CREATE TABLE ref.monthly_revenue_new AS SELECT ... FROM ref.orders WHERE ...;
BEGIN;
DROP MATERIALIZED VIEW ref.monthly_revenue;
CREATE MATERIALIZED VIEW ref.monthly_revenue AS SELECT * FROM ref.monthly_revenue_new;
COMMIT;

-- 2. Append-only partition + union view
-- 3. Use regular table + UPSERT instead of MV for incremental updates
```

---

## Materialized View vs Regular Table

| | Materialized View | Table + scheduled INSERT |
|---|-------------------|--------------------------|
| Definition | Tied to source query | Manual ETL logic |
| Refresh | `REFRESH MATERIALIZED VIEW` | Custom scripts |
| Indexes | Supported | Supported |
| Incremental | Full refresh only* | Full control |
| Permissions | Separate from source | Standard table |

*Use tables + UPSERT for true incremental pipelines.

---

## Materialized View vs CTE / View

| Need | Use |
|------|-----|
| Always fresh data | View or query |
| Expensive query, stale OK | Materialized view |
| One-time cache in transaction | `WITH ... AS MATERIALIZED` (PG 12+) |
| Application-level cache | MV or Redis |

---

## Monitoring Materialized Views

```sql
SELECT schemaname, matviewname, ispopulated, definition
FROM pg_matviews
WHERE schemaname = 'ref';

SELECT pg_size_pretty(pg_total_relation_size('ref.monthly_revenue'));
```

---

## Drop & Replace

```sql
DROP MATERIALIZED VIEW IF EXISTS ref.monthly_revenue;
DROP MATERIALIZED VIEW ref.monthly_revenue CASCADE;  -- drops dependent objects

-- Replace definition
CREATE OR REPLACE VIEW ref.active_employees AS ...;  -- views only
-- MV: must DROP and CREATE (no OR REPLACE for MV)
```

---

## Practical Scenario: Nightly ETL Pipeline

```sql
-- Step 1: Build MV
CREATE MATERIALIZED VIEW ref.daily_order_stats AS
SELECT created_at::date AS day,
       COUNT(*) AS orders,
       SUM(total) FILTER (WHERE status = 'paid') AS paid_total,
       COUNT(*) FILTER (WHERE status = 'cancelled') AS cancelled
FROM ref.orders
GROUP BY 1
WITH NO DATA;

CREATE UNIQUE INDEX daily_order_stats_day ON ref.daily_order_stats (day);

-- Step 2: Initial load
REFRESH MATERIALIZED VIEW ref.daily_order_stats;

-- Step 3: Nightly job
REFRESH MATERIALIZED VIEW CONCURRENTLY ref.daily_order_stats;

-- Step 4: App reads instantly
SELECT * FROM ref.daily_order_stats
WHERE day >= CURRENT_DATE - 30
ORDER BY day;
```

---

## Next

→ [14. Functions, Procedures & PL/pgSQL](./14-plpgsql.md)
