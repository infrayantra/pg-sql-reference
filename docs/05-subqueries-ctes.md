# 5. Subqueries & Common Table Expressions (CTEs)

## Scalar Subqueries

Return a single value (one row, one column).

```sql
SELECT name, salary,
       (SELECT AVG(salary) FROM ref.employees) AS company_avg,
       salary - (SELECT AVG(salary) FROM ref.employees) AS diff_from_avg
FROM ref.employees;

-- In WHERE
SELECT * FROM ref.employees
WHERE salary > (SELECT AVG(salary) FROM ref.employees);
```

⚠️ Scalar subquery must return exactly one row or you get a runtime error. Use `LIMIT 1` or aggregates to guarantee one row.

---

## Row Subqueries

```sql
SELECT * FROM ref.employees
WHERE (department_id, salary) = (
  SELECT department_id, MAX(salary)
  FROM ref.employees
  GROUP BY department_id
  HAVING department_id = 1
);
```

---

## Table Subqueries (Derived Tables)

```sql
SELECT dept.name, stats.avg_salary
FROM ref.departments dept
JOIN (
  SELECT department_id, AVG(salary) AS avg_salary
  FROM ref.employees
  GROUP BY department_id
) stats ON stats.department_id = dept.id;
```

---

## Correlated Subqueries

Reference outer query — evaluated per outer row.

```sql
SELECT e.name, e.salary
FROM ref.employees e
WHERE e.salary > (
  SELECT AVG(salary)
  FROM ref.employees inner_e
  WHERE inner_e.department_id = e.department_id
);
```

Often rewrite as JOIN for clarity:

```sql
SELECT e.name, e.salary
FROM ref.employees e
JOIN (
  SELECT department_id, AVG(salary) AS dept_avg
  FROM ref.employees GROUP BY department_id
) d ON d.department_id = e.department_id
WHERE e.salary > d.dept_avg;
```

---

## EXISTS / NOT EXISTS

```sql
-- Departments with at least one employee earning > 100k
SELECT d.*
FROM ref.departments d
WHERE EXISTS (
  SELECT 1 FROM ref.employees e
  WHERE e.department_id = d.id AND e.salary > 100000
);
```

---

## IN / NOT IN with Subqueries

```sql
SELECT * FROM ref.customers
WHERE id IN (SELECT DISTINCT customer_id FROM ref.orders);

-- NOT IN: beware NULLs in subquery result
SELECT * FROM ref.employees
WHERE id NOT IN (SELECT manager_id FROM ref.employees WHERE manager_id IS NOT NULL);
```

---

## ANY / ALL

```sql
SELECT * FROM ref.employees
WHERE salary > ANY (SELECT salary FROM ref.employees WHERE department_id = 3);

SELECT * FROM ref.employees
WHERE salary >= ALL (SELECT salary FROM ref.employees WHERE department_id = 3);
```

---

## WITH — Common Table Expressions (CTEs)

```sql
WITH dept_stats AS (
  SELECT department_id,
         COUNT(*) AS cnt,
         AVG(salary) AS avg_sal
  FROM ref.employees
  GROUP BY department_id
)
SELECT d.name, ds.cnt, ROUND(ds.avg_sal, 2)
FROM ref.departments d
JOIN dept_stats ds ON ds.department_id = d.id;
```

### Multiple CTEs

```sql
WITH
  paid_orders AS (
    SELECT * FROM ref.orders WHERE status IN ('paid', 'shipped')
  ),
  customer_totals AS (
    SELECT customer_id, SUM(total) AS lifetime_value
    FROM paid_orders
    GROUP BY customer_id
  )
SELECT c.name, ct.lifetime_value
FROM ref.customers c
JOIN customer_totals ct ON ct.customer_id = c.id
ORDER BY ct.lifetime_value DESC;
```

### CTE column names

```sql
WITH stats(dept_id, headcount, avg_pay) AS (
  SELECT department_id, COUNT(*), AVG(salary)
  FROM ref.employees GROUP BY department_id
)
SELECT * FROM stats;
```

---

## Recursive CTEs

For hierarchical or graph traversal data.

```sql
-- Employee hierarchy from a manager down
WITH RECURSIVE org_tree AS (
  -- Base case: top-level managers
  SELECT id, name, manager_id, 1 AS depth, ARRAY[id] AS path
  FROM ref.employees
  WHERE manager_id IS NULL

  UNION ALL

  -- Recursive case
  SELECT e.id, e.name, e.manager_id, t.depth + 1, t.path || e.id
  FROM ref.employees e
  JOIN org_tree t ON e.manager_id = t.id
  WHERE NOT e.id = ANY(t.path)  -- cycle prevention
)
SELECT * FROM org_tree ORDER BY path;
```

### Graph shortest path (breadth-first)

```sql
WITH RECURSIVE paths AS (
  SELECT id, ARRAY[id] AS path, 0 AS depth
  FROM nodes WHERE id = start_id
  UNION ALL
  SELECT n.id, p.path || n.id, p.depth + 1
  FROM paths p
  JOIN edges e ON e.from_id = p.id
  JOIN nodes n ON n.id = e.to_id
  WHERE NOT n.id = ANY(p.path)
)
SELECT * FROM paths WHERE id = end_id ORDER BY depth LIMIT 1;
```

---

## MATERIALIZED CTE `(PG 12+)`

Forces CTE result to be computed and stored before the outer query uses it.

```sql
WITH big AS MATERIALIZED (
  SELECT * FROM ref.events WHERE occurred_at > now() - interval '1 year'
)
SELECT event_type, COUNT(*) FROM big GROUP BY event_type;
```

Default behavior changed in PG 12: CTEs are **inlined** by default (optimization fence removed). Use `MATERIALIZED` when you want to force materialization; use `NOT MATERIALIZED` to hint inlining.

💡 Use `MATERIALIZED` when the CTE is referenced multiple times or is expensive and reduces rows significantly.

---

## Subquery in FROM vs CTE

Functionally similar; CTEs improve readability and allow recursion. Performance is usually equivalent after planning.

---

## Next

→ [06. Window Functions](./06-window-functions.md)
