# 6. Window Functions

Window functions compute over a **window** of rows related to the current row, without collapsing groups like `GROUP BY`.

## Syntax

```sql
function(args) OVER (
  [PARTITION BY expression [, ...]]
  [ORDER BY expression [ASC|DESC] [NULLS {FIRST|LAST}] [, ...]]
  [frame_clause]
)

-- Named window (reuse definition)
function(args) OVER window_name

WINDOW window_name AS (window_definition)
```

---

## Ranking Functions

| Function | Behavior |
|----------|----------|
| `ROW_NUMBER()` | Unique sequential integer per partition |
| `RANK()` | Gaps after ties (1,2,2,4) |
| `DENSE_RANK()` | No gaps (1,2,2,3) |
| `NTILE(n)` | Split into n buckets |
| `PERCENT_RANK()` | Relative rank 0–1 |
| `CUME_DIST()` | Cumulative distribution |

```sql
SELECT name, department_id, salary,
       ROW_NUMBER() OVER (PARTITION BY department_id ORDER BY salary DESC) AS rn,
       RANK()       OVER (PARTITION BY department_id ORDER BY salary DESC) AS rnk,
       DENSE_RANK() OVER (PARTITION BY department_id ORDER BY salary DESC) AS dr
FROM ref.employees;
```

### Top N per group

```sql
SELECT * FROM (
  SELECT e.*,
         ROW_NUMBER() OVER (PARTITION BY department_id ORDER BY salary DESC) AS rn
  FROM ref.employees e
) ranked
WHERE rn <= 2;
```

---

## Value Functions (Access Other Rows)

| Function | Description |
|----------|-------------|
| `LAG(col, offset, default)` | Previous row value |
| `LEAD(col, offset, default)` | Next row value |
| `FIRST_VALUE(col)` | First in frame |
| `LAST_VALUE(col)` | Last in frame |
| `NTH_VALUE(col, n)` | Nth row in frame |

```sql
SELECT customer_id, id, total, created_at,
       LAG(total) OVER (PARTITION BY customer_id ORDER BY created_at) AS prev_order_total,
       total - LAG(total) OVER (PARTITION BY customer_id ORDER BY created_at) AS delta
FROM ref.orders;
```

---

## Aggregate Functions as Windows

```sql
SELECT id, customer_id, total, created_at,
       SUM(total) OVER (PARTITION BY customer_id ORDER BY created_at) AS running_total,
       AVG(total) OVER (PARTITION BY customer_id) AS customer_avg,
       COUNT(*) OVER (PARTITION BY customer_id) AS order_count
FROM ref.orders;
```

---

## Frame Clauses

Default frame with `ORDER BY`: `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`

```sql
-- Explicit ROWS frame (physical row count)
SELECT id, amount,
       SUM(amount) OVER (
         ORDER BY created_at
         ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ) AS moving_sum_3
FROM ref.orders;

-- Entire partition
SELECT department_id, name, salary,
       SUM(salary) OVER (PARTITION BY department_id) AS dept_total,
       salary / SUM(salary) OVER (PARTITION BY department_id) AS pct_of_dept
FROM ref.employees;

-- Centered moving average
AVG(val) OVER (ORDER BY ts ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING)
```

### RANGE vs ROWS vs GROUPS `(PG 14+ GROUPS)`

| Mode | Frame based on |
|------|----------------|
| `ROWS` | Physical row offsets |
| `RANGE` | Peer groups (same ORDER BY value) |
| `GROUPS` | Count of peer groups |

```sql
-- Exclude current row from frame
SUM(x) OVER (ORDER BY t ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
```

---

## Named WINDOW Clause

```sql
SELECT name, salary,
       RANK()         OVER w AS rnk,
       PERCENT_RANK() OVER w AS pct
FROM ref.employees
WINDOW w AS (PARTITION BY department_id ORDER BY salary DESC);
```

---

## FILTER on Window Functions

```sql
SELECT department_id,
       COUNT(*) FILTER (WHERE salary > 90000) OVER (PARTITION BY department_id) AS high_earners
FROM ref.employees;
```

---

## DISTINCT in Window Aggregates `(PG 14+)`

```sql
SELECT customer_id, product_id,
       COUNT(DISTINCT product_id) OVER (PARTITION BY customer_id) AS unique_products
FROM ref.order_items oi
JOIN ref.orders o ON o.id = oi.order_id;
```

---

## Practical Patterns

### Difference from previous row (gaps detection)

```sql
SELECT occurred_at,
       occurred_at - LAG(occurred_at) OVER (ORDER BY occurred_at) AS gap
FROM ref.events;
```

### First/last row per group without subquery

```sql
SELECT DISTINCT ON (department_id) department_id, name, salary
FROM ref.employees
ORDER BY department_id, salary DESC;
-- Or with windows:
SELECT * FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY department_id ORDER BY salary DESC) rn
  FROM ref.employees
) t WHERE rn = 1;
```

### Cumulative percentile

```sql
SELECT salary,
       CUME_DIST() OVER (ORDER BY salary) AS percentile
FROM ref.employees;
```

---

## Performance Notes

💡 Window functions require sorting (often). Index on `(PARTITION BY cols, ORDER BY cols)` can help adjacent operations but not always the window itself.

💡 For "top 1 per group" at scale, consider `LATERAL` + `LIMIT 1` or `DISTINCT ON` with matching index.

---

## Next

→ [07. Set Operations & Advanced SELECT](./07-set-operations.md)
