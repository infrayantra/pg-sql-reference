# 3. Joins

## Join Types Overview

| Join | Returns |
|------|---------|
| `INNER JOIN` | Rows with matches in both tables |
| `LEFT [OUTER] JOIN` | All left rows + matching right (NULL if no match) |
| `RIGHT [OUTER] JOIN` | All right rows + matching left |
| `FULL [OUTER] JOIN` | All rows from both; NULLs where no match |
| `CROSS JOIN` | Cartesian product (every combination) |

---

## INNER JOIN

```sql
SELECT e.name, d.name AS department
FROM ref.employees e
INNER JOIN ref.departments d ON d.id = e.department_id;

-- Equivalent comma syntax (avoid — implicit CROSS JOIN + WHERE)
SELECT e.name, d.name
FROM ref.employees e, ref.departments d
WHERE d.id = e.department_id;
```

### Multiple joins

```sql
SELECT c.name AS customer, o.id AS order_id, o.total, o.status
FROM ref.customers c
JOIN ref.orders o ON o.customer_id = c.id
JOIN ref.order_items oi ON oi.order_id = o.id
JOIN ref.products p ON p.id = oi.product_id;
```

---

## LEFT JOIN

```sql
-- All employees, including those without a department
SELECT e.name, d.name AS department
FROM ref.employees e
LEFT JOIN ref.departments d ON d.id = e.department_id;

-- Find rows with no match (anti-join pattern)
SELECT e.name
FROM ref.employees e
LEFT JOIN ref.departments d ON d.id = e.department_id
WHERE d.id IS NULL;
```

💡 Use `LEFT JOIN ... WHERE right.key IS NULL` instead of `NOT IN` when the right side may contain NULLs.

---

## FULL OUTER JOIN

```sql
SELECT e.name AS employee, m.name AS manager
FROM ref.employees e
FULL OUTER JOIN ref.employees m ON m.id = e.manager_id;
```

---

## CROSS JOIN

```sql
-- Every employee paired with every department (rarely needed)
SELECT e.name, d.name
FROM ref.employees e
CROSS JOIN ref.departments d;

-- Implicit cross join
FROM a, b  -- same as CROSS JOIN unless WHERE links them
```

Useful for generating combinations:

```sql
SELECT d.name, month.month_start
FROM ref.departments d
CROSS JOIN generate_series(
  date_trunc('year', CURRENT_DATE),
  date_trunc('year', CURRENT_DATE) + interval '11 months',
  interval '1 month'
) AS month(month_start);
```

---

## Self Join

```sql
SELECT e.name AS employee, m.name AS manager
FROM ref.employees e
LEFT JOIN ref.employees m ON m.id = e.manager_id;
```

---

## Join Conditions Beyond Equality

```sql
-- Range join: events within 1 hour of each other
SELECT a.id, b.id
FROM ref.events a
JOIN ref.events b ON a.user_id = b.user_id
  AND a.id < b.id
  AND b.occurred_at BETWEEN a.occurred_at AND a.occurred_at + interval '1 hour';

-- Non-equi join with BETWEEN
SELECT o.id, tier.discount_pct
FROM ref.orders o
JOIN ref.discount_tiers tier
  ON o.total BETWEEN tier.min_amount AND tier.max_amount;
```

---

## LATERAL Join `(PG 9.3+)`

Subquery in FROM that can reference preceding tables — runs **per row** of the left side.

```sql
-- Top 2 orders per customer
SELECT c.name, recent.*
FROM ref.customers c
CROSS JOIN LATERAL (
  SELECT o.id, o.total, o.created_at
  FROM ref.orders o
  WHERE o.customer_id = c.id
  ORDER BY o.created_at DESC
  LIMIT 2
) recent;

-- Equivalent: LEFT JOIN LATERAL ... ON true (preserve customers with no orders)
SELECT c.name, recent.*
FROM ref.customers c
LEFT JOIN LATERAL (
  SELECT o.id, o.total
  FROM ref.orders o
  WHERE o.customer_id = c.id
  ORDER BY o.created_at DESC
  LIMIT 1
) recent ON true;
```

💡 `LATERAL` + `LIMIT` is often cleaner than window functions for top-N-per-group when N is small.

---

## NATURAL JOIN (Avoid in Production)

```sql
-- Joins on all columns with the same name — implicit, fragile
SELECT * FROM ref.employees NATURAL JOIN ref.departments;
```

⚠️ Breaks silently when schema changes. Prefer explicit `ON` clauses.

---

## Join vs Subquery Performance

PostgreSQL's planner often rewrites subqueries and joins to the same plan. Write for clarity; verify with `EXPLAIN (ANALYZE, BUFFERS)`.

---

## Next

→ [04. Aggregations & Grouping](./04-aggregations.md)
