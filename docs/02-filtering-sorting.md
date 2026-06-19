# 2. Filtering, Sorting & Pagination

## WHERE Clause

```sql
SELECT * FROM ref.employees
WHERE salary >= 80000
  AND department_id = 1
  AND hired_at >= '2020-01-01';
```

### Comparison operators

`=`, `<>`, `!=`, `<`, `>`, `<=`, `>=`, `BETWEEN`, `IN`, `NOT IN`, `LIKE`, `ILIKE`, `SIMILAR TO`, `~` (regex), `~*` (case-insensitive regex)

```sql
-- BETWEEN (inclusive both ends)
SELECT * FROM ref.employees WHERE salary BETWEEN 70000 AND 100000;

-- IN / NOT IN
SELECT * FROM ref.orders WHERE status IN ('paid', 'shipped');

-- ⚠️ NOT IN returns no rows if subquery contains NULL
SELECT * FROM t WHERE id NOT IN (SELECT parent_id FROM t);  -- dangerous

-- Prefer NOT EXISTS
SELECT * FROM ref.employees e
WHERE NOT EXISTS (
  SELECT 1 FROM ref.employees m WHERE m.manager_id = e.id
);
```

### Pattern matching

```sql
-- LIKE: % = any string, _ = single char
SELECT * FROM ref.employees WHERE name LIKE 'A%';
SELECT * FROM ref.employees WHERE email LIKE '%@co.com';

-- ILIKE: case-insensitive
SELECT * FROM ref.products WHERE name ILIKE '%widget%';

-- POSIX regular expressions
SELECT * FROM ref.employees WHERE name ~ '^[A-C]';      -- starts with A, B, or C
SELECT * FROM ref.employees WHERE email ~* '@co\.com$';   -- case-insensitive end anchor
```

### Logical operators

```sql
WHERE (department_id = 1 OR department_id = 2)
  AND NOT is_active = false

-- Short-circuit with AND/OR — place selective conditions first 💡
```

---

## DISTINCT

```sql
-- Remove duplicate rows from result
SELECT DISTINCT department_id FROM ref.employees;

-- DISTINCT ON — first row per group (PostgreSQL-specific)
SELECT DISTINCT ON (department_id)
       department_id, name, salary
FROM ref.employees
ORDER BY department_id, salary DESC;  -- ORDER BY must start with DISTINCT ON expressions
```

`DISTINCT ON` picks the **first row** after sorting within each group — ideal for "top employee per department" without window functions.

---

## ORDER BY

```sql
SELECT name, salary
FROM ref.employees
ORDER BY salary DESC NULLS LAST, name ASC;

-- Order by expression
SELECT *, salary * 12 AS annual FROM ref.employees ORDER BY annual DESC;

-- Order by column alias (works in same SELECT level)
SELECT name, salary FROM ref.employees ORDER BY salary DESC;

-- NULLS FIRST | NULLS LAST (default: NULLS FIRST for DESC, NULLS LAST for ASC)
```

---

## LIMIT & OFFSET (Pagination)

```sql
-- First 10 rows
SELECT * FROM ref.employees ORDER BY id LIMIT 10;

-- Page 3, 10 per page (offset 20)
SELECT * FROM ref.employees ORDER BY id LIMIT 10 OFFSET 20;

-- FETCH syntax (SQL standard)
SELECT * FROM ref.employees
ORDER BY id
OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;
```

⚠️ **Large OFFSET is slow** — the server must scan and discard skipped rows. For deep pagination, use keyset (seek) pagination:

```sql
-- Keyset pagination: "rows after id 50"
SELECT * FROM ref.employees
WHERE id > 50
ORDER BY id
LIMIT 10;
```

---

## CASE Expressions

```sql
SELECT name, salary,
  CASE
    WHEN salary >= 100000 THEN 'senior'
    WHEN salary >= 80000  THEN 'mid'
    ELSE 'junior'
  END AS level
FROM ref.employees;

-- Searched CASE vs simple CASE
SELECT CASE department_id
  WHEN 1 THEN 'Engineering'
  WHEN 2 THEN 'Sales'
  ELSE 'Other'
END AS dept_name
FROM ref.employees;

-- FILTER clause (cleaner than CASE in aggregates)
SELECT department_id,
       COUNT(*) AS total,
       COUNT(*) FILTER (WHERE salary >= 100000) AS senior_count
FROM ref.employees
GROUP BY department_id;
```

---

## EXISTS & Semi-joins

```sql
-- Customers who have placed orders
SELECT c.*
FROM ref.customers c
WHERE EXISTS (
  SELECT 1 FROM ref.orders o WHERE o.customer_id = c.id
);

-- Equivalent IN (often similar plan)
SELECT * FROM ref.customers
WHERE id IN (SELECT customer_id FROM ref.orders);
```

💡 Prefer `EXISTS` over `COUNT(*) > 0` — stops at first match.

---

## Row Comparison (Tuple Comparison)

```sql
SELECT * FROM ref.employees
WHERE (department_id, salary) > (1, 90000);

-- Equivalent expanded form
SELECT * FROM ref.employees
WHERE department_id > 1
   OR (department_id = 1 AND salary > 90000);
```

---

## ALL, ANY, SOME

```sql
-- salary greater than all salaries in department 3
SELECT * FROM ref.employees
WHERE salary > ALL (SELECT salary FROM ref.employees WHERE department_id = 3);

-- salary greater than at least one in department 3
SELECT * FROM ref.employees
WHERE salary > ANY (SELECT salary FROM ref.employees WHERE department_id = 3);
-- ANY with = is equivalent to IN
```

---

## Next

→ [03. Joins](./03-joins.md)
