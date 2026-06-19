# 11. Indexes & Query Planning

## Index Types at a Glance

| Type | Structure | Best For | Avoid When |
|------|-----------|----------|------------|
| **B-tree** | Balanced tree | Equality, ranges, sorting, FKs, UNIQUE | Column never in WHERE/JOIN/ORDER BY |
| **Hash** | Hash buckets | `=` only (rare) | Ranges, sorting — use B-tree instead |
| **GIN** | Inverted index (many entries/row) | JSONB, arrays, FTS, `@>`, `?` | Low-cardinality scalars, heavy UPDATE |
| **GiST** | Generalized search tree | Ranges, geometry, FTS, `EXCLUDE` | Simple equality on integers |
| **SP-GiST** | Space-partitioned GiST | Quadtrees, phone prefixes, IP ranges | General-purpose queries |
| **BRIN** | Block range summaries | Huge time-series, append-only, correlated order | Random access, small tables |

```sql
-- Defaults to B-tree when USING omitted
CREATE INDEX employees_dept_salary ON ref.employees (department_id, salary DESC);
CREATE INDEX orders_created_brin ON ref.orders USING BRIN (created_at);
CREATE INDEX products_metadata_gin ON ref.products USING GIN (metadata);
CREATE INDEX products_tags_gin ON ref.products USING GIN (tags);
```

---

## B-tree (Default)

The workhorse index. Supports `<`, `<=`, `=`, `>=`, `>`, `BETWEEN`, `IN`, `IS NULL`, and `ORDER BY`.

### Use case: Foreign key lookups

```sql
-- Every FK column used in JOINs should be indexed
CREATE INDEX orders_customer_id_idx ON ref.orders (customer_id);

SELECT c.name, o.total
FROM ref.customers c
JOIN ref.orders o ON o.customer_id = c.id;
-- Index Scan or Bitmap Index Scan on orders_customer_id_idx
```

### Use case: Composite index for multi-column filters

```sql
CREATE INDEX employees_dept_active_salary
ON ref.employees (department_id, is_active, salary DESC);

-- Uses index: filter dept + active, sort by salary
SELECT name, salary FROM ref.employees
WHERE department_id = 1 AND is_active
ORDER BY salary DESC;
```

**Leftmost prefix rule:** index `(a, b, c)` helps `(a)`, `(a,b)`, `(a,b,c)` — not `(b)` alone or `(b,c)`.

### Use case: Covering index (index-only scan)

```sql
CREATE INDEX employees_dept_covering
ON ref.employees (department_id) INCLUDE (name, salary);

SELECT department_id, name, salary
FROM ref.employees WHERE department_id = 1;
-- Index Only Scan if visibility map is current (VACUUM)
```

### Use case: Partial index (smaller, faster)

```sql
-- Only index active employees — ideal when queries always filter is_active
CREATE INDEX employees_active_dept
ON ref.employees (department_id)
WHERE is_active = true;

SELECT * FROM ref.employees WHERE department_id = 2 AND is_active;
```

### Use case: Unique constraint enforcement

```sql
CREATE UNIQUE INDEX employees_email_idx ON ref.employees (email);
CREATE UNIQUE INDEX customers_email_lower ON ref.customers (lower(email));
```

### Use case: Expression index

```sql
CREATE INDEX employees_lower_name ON ref.employees (lower(name));
SELECT * FROM ref.employees WHERE lower(name) = 'alice chen';

CREATE INDEX orders_month ON ref.orders (date_trunc('month', created_at));
```

### Use case: NULL handling

B-tree indexes **can** be used for `IS NULL` / `IS NOT NULL`. For sparse nullable columns where most rows are NULL:

```sql
CREATE INDEX employees_manager_idx ON ref.employees (manager_id)
WHERE manager_id IS NOT NULL;
```

### B-tree limitations

```sql
-- Won't use plain B-tree (need pg_trgm GIN/GiST or full scan)
WHERE name LIKE '%widget%';

-- Won't use B-tree on column wrapped in function (unless expression index)
WHERE date(created_at) = '2024-01-15';
-- Fix: WHERE created_at >= '2024-01-15' AND created_at < '2024-01-16'
```

---

## GIN (Generalized Inverted Index)

Stores **one index entry per element** inside a composite value. Ideal when one row contains many searchable values.

### Use case: JSONB containment

```sql
CREATE INDEX products_metadata_gin ON ref.products USING GIN (metadata);

-- Fast: containment
SELECT * FROM ref.products WHERE metadata @> '{"warranty_years": 2}';
SELECT * FROM ref.products WHERE metadata ? 'tier';
SELECT * FROM ref.products WHERE metadata ?| array['tier', 'color'];

-- Slower without expression index:
SELECT * FROM ref.products WHERE metadata ->> 'tier' = 'gold';
-- Fix: CREATE INDEX ON ref.products ((metadata -> 'tier'));
```

**Operator classes:**
- `jsonb_ops` (default) — supports `@>`, `?`, `?|`, `?&`
- `jsonb_path_ops` — smaller index, `@>` and path only

### Use case: Array overlap / containment

```sql
CREATE INDEX products_tags_gin ON ref.products USING GIN (tags);

SELECT * FROM ref.products WHERE tags @> ARRAY['hardware'];
SELECT * FROM ref.products WHERE tags && ARRAY['pro', 'subscription'];
SELECT * FROM ref.products WHERE 'hardware' = ANY(tags);
```

### Use case: Full-text search

```sql
CREATE INDEX articles_tsv_gin ON ref.articles USING GIN (tsv);
SELECT * FROM ref.articles WHERE tsv @@ plainto_tsquery('english', 'indexing');
```

### Use case: Fuzzy text search (pg_trgm)

```sql
CREATE EXTENSION pg_trgm;
CREATE INDEX products_name_trgm ON ref.products USING GIN (name gin_trgm_ops);

SELECT * FROM ref.products WHERE name ILIKE '%widgt%';   -- typo-tolerant
SELECT * FROM ref.products WHERE name % 'Widget';        -- similarity operator
SELECT similarity(name, 'Widget Pro') FROM ref.products;
```

### GIN trade-offs

| Pros | Cons |
|------|------|
| Extremely fast for `@>`, `&&`, FTS | Slow INSERT/UPDATE (many index entries) |
| Compact for multi-value columns | Larger than B-tree for scalar columns |
| jsonb_path_ops saves space | Fewer operators than jsonb_ops |

💡 Set `fastupdate = on` (default) for write-heavy GIN; run routine `VACUUM`.

---

## GiST (Generalized Search Tree)

Lossy but flexible. Supports **overlap**, **containment**, **nearest-neighbor**, and **exclusion** constraints.

### Use case: Range overlap (scheduling, bookings)

```sql
CREATE TABLE ref.room_bookings (
  id       SERIAL PRIMARY KEY,
  room_id  INT NOT NULL,
  period   TSTZRANGE NOT NULL,
  EXCLUDE USING GIST (room_id WITH =, period WITH &&)
);

CREATE INDEX room_bookings_period ON ref.room_bookings USING GIST (period);

-- Find bookings overlapping a time window
SELECT * FROM ref.room_bookings
WHERE period && tstzrange('2024-06-01 14:00', '2024-06-05 11:00');

-- Contains a point in time
SELECT * FROM ref.room_bookings
WHERE period @> '2024-06-03 09:00'::timestamptz;
```

### Use case: Geometric / PostGIS (extension)

```sql
CREATE EXTENSION postgis;
CREATE INDEX locations_geom ON places USING GIST (geom);

SELECT * FROM places
WHERE ST_DWithin(geom, ST_MakePoint(-73.98, 40.75)::geography, 1000);
-- Nearest-neighbor
SELECT * FROM places ORDER BY geom <-> ST_MakePoint(-73.98, 40.75) LIMIT 5;
```

### Use case: Full-text search (alternative to GIN)

```sql
CREATE INDEX articles_tsv_gist ON ref.articles USING GIST (tsv);
-- GIN: faster lookups, larger index
-- GiST: smaller, better for dynamic data, lossy
```

### Use case: ltree (hierarchical paths)

```sql
CREATE EXTENSION ltree;
CREATE INDEX nodes_path ON categories USING GIST (path);
SELECT * FROM categories WHERE path ~ 'Electronics.*Computers';
```

### GiST vs GIN for same data

| Choose GIN | Choose GiST |
|------------|-------------|
| Static data, read-heavy | Frequently updated |
| Exact FTS match speed | Smaller index size |
| JSONB `@>` queries | Range/geometry/exclusion |

---

## BRIN (Block Range Index)

Stores **min/max summary per block** of heap pages. Tiny index size; ideal for **very large, naturally ordered** tables.

### Use case: Time-series / append-only logs

```sql
CREATE INDEX events_occurred_brin ON ref.events USING BRIN (occurred_at)
WITH (pages_per_range = 128);

-- Works well when new rows append with increasing occurred_at
SELECT * FROM ref.events
WHERE occurred_at >= '2024-01-01' AND occurred_at < '2024-02-01';
```

### Use case: Large orders table by created_at

```sql
CREATE INDEX orders_created_brin ON ref.orders USING BRIN (created_at);

-- Monthly report on 100M+ row table — BRIN skips irrelevant blocks
SELECT date_trunc('day', created_at), COUNT(*)
FROM ref.orders
WHERE created_at >= '2024-06-01' AND created_at < '2024-07-01'
GROUP BY 1;
```

### Use case: Correlated integer (auto-increment id on append-only table)

```sql
CREATE INDEX events_id_brin ON ref.events USING BRIN (id);
```

### When BRIN works vs fails

| Works | Fails |
|-------|-------|
| Table physically ordered by indexed column | Random INSERT order (UUID PK) |
| Range queries on timestamps | Point lookup `WHERE id = 42` |
| Tables with millions+ rows | Small tables (seq scan wins) |
| Low storage budget for indexes | Need perfect precision (BRIN is lossy) |

💡 After bulk load, `CLUSTER` or use `pg_repack` to improve BRIN effectiveness:

```sql
CLUSTER ref.events USING events_occurred_brin;
```

---

## SP-GiST (Space-Partitioned GiST)

For data that partitions space unevenly — quadtrees, k-d trees, radix trees.

### Use case: IP address lookup

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE ref.ip_rules (id SERIAL, network inet, rule TEXT);
CREATE INDEX ip_rules_network ON ref.ip_rules USING SP-GiST (network);

SELECT rule FROM ref.ip_rules WHERE network >> inet '10.0.0.42';
```

### Use case: Text prefix search

```sql
CREATE INDEX products_sku_spgist ON ref.products USING SP-GiST (sku);
SELECT * FROM ref.products WHERE sku LIKE 'WDG%';
```

---

## Hash Indexes

Equality only. Rarely needed since B-tree handles `=` well and supports more operators.

```sql
CREATE INDEX employees_id_hash ON ref.employees USING HASH (id);
-- Only helps: WHERE id = 5
-- PG 10+: WAL-logged, crash-safe (older versions were not)
```

Use B-tree unless you have a specific benchmark win.

---

## Choosing the Right Index — Decision Guide

```
Is the column JSONB, array, or tsvector with @>/&&/@@ queries?
  └─ YES → GIN (or GiST for ranges/geometry)
  └─ NO ↓

Is it a range type (tstzrange) or geometry with &&/@>/EXCLUDE?
  └─ YES → GiST
  └─ NO ↓

Is the table huge (millions+), append-ordered by timestamp/id, range queries?
  └─ YES → BRIN (+ optional B-tree for point lookups)
  └─ NO ↓

Default → B-tree
  • Add partial index if query always has same WHERE filter
  • Add INCLUDE columns for covering index-only scans
  • Add expression index if function wraps column in WHERE
```

---

## Index Maintenance

```sql
-- List indexes and sizes
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)), idx_scan
FROM pg_stat_user_indexes
WHERE schemaname = 'ref'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Unused indexes (candidates for removal)
SELECT indexrelname, idx_scan FROM pg_stat_user_indexes
WHERE schemaname = 'ref' AND idx_scan = 0;

-- Rebuild without blocking writes (PG 12+)
REINDEX INDEX CONCURRENTLY ref.employees_dept_salary;

-- Update planner stats
ANALYZE ref.employees;
```

---

## Index-Only Scans

PostgreSQL can satisfy queries from the index alone if the visibility map shows heap pages as all-visible (requires `VACUUM`).

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT department_id, name FROM ref.employees WHERE department_id = 1;
-- Look for "Index Only Scan"
```

---

## EXPLAIN

```sql
EXPLAIN SELECT * FROM ref.employees WHERE department_id = 1;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT TEXT)
SELECT * FROM ref.employees WHERE department_id = 1;
```

### Key plan nodes

| Node | Meaning |
|------|---------|
| Seq Scan | Full table scan |
| Index Scan | Index lookup + heap fetch |
| Index Only Scan | Index satisfies query |
| Bitmap Index Scan | Build TID bitmap from index |
| Bitmap Heap Scan | Fetch rows from bitmap |
| Nested Loop | For each outer row, scan inner |
| Hash Join | Build hash table on inner |
| Merge Join | Both sides sorted, merge |

---

## Query Optimization Patterns

### Sargable predicates (index-friendly)

```sql
-- Good
WHERE created_at >= '2024-01-01' AND created_at < '2024-02-01'
WHERE lower(email) = lower('Alice@co.com')  -- with expression index

-- Bad — function on column prevents index use
WHERE date(created_at) = '2024-01-15'
```

### When NOT to Index

- Small tables (seq scan cheaper)
- Write-heavy columns with almost no reads
- Low-cardinality alone (e.g. boolean) unless partial index
- Duplicate indexes: `(a)` and `(a,b)` — the composite often covers `(a)`

---

## Real-World Index Recipes

```sql
-- E-commerce: orders by customer + date
CREATE INDEX orders_customer_created ON ref.orders (customer_id, created_at DESC);

-- API keyset pagination
CREATE INDEX orders_pagination ON ref.orders (created_at DESC, id DESC);

-- Soft-delete aware unique email
CREATE UNIQUE INDEX customers_email_active
ON ref.customers (email) WHERE deleted_at IS NULL;  -- if soft-delete column exists

-- JSONB dashboard filter
CREATE INDEX events_payload_status ON ref.events USING GIN ((payload -> 'status'));

-- Log table BRIN + partition
CREATE INDEX events_brin ON ref.events USING BRIN (occurred_at);
```

---

## Next

→ [12. Transactions & Concurrency](./12-transactions.md)
