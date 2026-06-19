# 4. Aggregations & Grouping

## Aggregate Functions

| Function | Description |
|----------|-------------|
| `COUNT(*)` | Row count (includes NULLs) |
| `COUNT(col)` | Non-NULL values |
| `COUNT(DISTINCT col)` | Distinct non-NULL count |
| `SUM`, `AVG`, `MIN`, `MAX` | Numeric/statistical |
| `BOOL_AND`, `BOOL_OR` | Boolean aggregation |
| `ARRAY_AGG` | Collect into array |
| `JSON_AGG`, `JSONB_AGG` | Collect into JSON array |
| `STRING_AGG` | Delimited string concatenation |
| `PERCENTILE_CONT`, `PERCENTILE_DISC` | Ordered-set aggregates |

```sql
SELECT department_id,
       COUNT(*) AS headcount,
       ROUND(AVG(salary), 2) AS avg_salary,
       MIN(salary) AS min_salary,
       MAX(salary) AS max_salary,
       SUM(salary) AS payroll
FROM ref.employees
GROUP BY department_id;
```

---

## GROUP BY

```sql
-- Single column
SELECT status, COUNT(*), SUM(total)
FROM ref.orders
GROUP BY status;

-- Multiple columns
SELECT customer_id, status, COUNT(*)
FROM ref.orders
GROUP BY customer_id, status;

-- Group by expression
SELECT date_trunc('month', created_at) AS month, SUM(total)
FROM ref.orders
GROUP BY date_trunc('month', created_at);

-- PG 9.5+: GROUP BY primary key → other columns from same table allowed
SELECT e.id, e.name, d.name
FROM ref.employees e
JOIN ref.departments d ON d.id = e.department_id
GROUP BY e.id, d.name;  -- e.id is PK, so e.name is functionally dependent
```

---

## HAVING

Filters **groups** after aggregation (WHERE filters rows before).

```sql
SELECT department_id, AVG(salary) AS avg_sal
FROM ref.employees
GROUP BY department_id
HAVING AVG(salary) > 85000
   AND COUNT(*) >= 2;
```

⚠️ Cannot use column aliases from SELECT in HAVING in all contexts — repeat expression or use subquery.

---

## FILTER Clause

```sql
SELECT department_id,
       COUNT(*) AS total,
       COUNT(*) FILTER (WHERE salary >= 100000) AS senior_count,
       AVG(salary) FILTER (WHERE is_active) AS active_avg_salary
FROM ref.employees
GROUP BY department_id;
```

---

## GROUPING SETS, ROLLUP, CUBE

### GROUPING SETS — specify multiple grouping combinations

```sql
SELECT department_id, is_active, COUNT(*), SUM(salary)
FROM ref.employees
GROUP BY GROUPING SETS (
  (department_id, is_active),
  (department_id),
  ()
);
```

### ROLLUP — hierarchical subtotals

```sql
SELECT department_id, is_active, COUNT(*), SUM(salary)
FROM ref.employees
GROUP BY ROLLUP (department_id, is_active);
-- Produces: (dept, active), (dept), grand total
```

### CUBE — all combinations of dimensions

```sql
SELECT department_id, is_active, COUNT(*)
FROM ref.employees
GROUP BY CUBE (department_id, is_active);
```

### GROUPING() — distinguish NULL from subtotal rows

```sql
SELECT
  CASE WHEN GROUPING(department_id) = 1 THEN 'ALL DEPTS' ELSE department_id::text END,
  COUNT(*)
FROM ref.employees
GROUP BY ROLLUP (department_id);
```

---

## Ordered-Set & Hypothetical-Set Aggregates

```sql
-- Median salary per department
SELECT department_id,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary
FROM ref.employees
GROUP BY department_id;

-- 90th percentile
SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY salary) FROM ref.employees;

-- Rank of a hypothetical value
SELECT rank(85000) WITHIN GROUP (ORDER BY salary) FROM ref.employees;
```

---

## Array & String Aggregation

```sql
SELECT department_id,
       array_agg(name ORDER BY name) AS names,
       string_agg(name, ', ' ORDER BY salary DESC) AS name_list
FROM ref.employees
GROUP BY department_id;

-- json aggregation with structure
SELECT customer_id,
       jsonb_agg(jsonb_build_object(
         'order_id', id,
         'total', total,
         'status', status
       ) ORDER BY created_at) AS orders
FROM ref.orders
GROUP BY customer_id;
```

---

## Statistical Aggregates

```sql
SELECT department_id,
       stddev(salary),
       variance(salary),
       corr(salary, extract(year FROM hired_at))  -- correlation
FROM ref.employees
GROUP BY department_id;
```

---

## Empty Groups

`GROUP BY` never produces a row for a group with zero input rows. Use LEFT JOIN from dimension table or `UNION` with zero-filled defaults.

```sql
-- Ensure all departments appear
SELECT d.name, COALESCE(COUNT(e.id), 0) AS headcount
FROM ref.departments d
LEFT JOIN ref.employees e ON e.department_id = d.id
GROUP BY d.id, d.name;
```

---

## Next

→ [05. Subqueries & CTEs](./05-subqueries-ctes.md)
