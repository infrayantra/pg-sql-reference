# PostgreSQL SQL Reference

A comprehensive PostgreSQL reference from fundamentals through advanced topics. Each section includes syntax, behavior notes, and runnable examples.

## Prerequisites

- PostgreSQL 14+ recommended (features are tagged when version-specific)
- Run examples with `psql`, any SQL client, or the included `examples/` scripts

## Quick Start

```bash
# Connect
psql -h localhost -U postgres -d mydb

# Useful psql meta-commands
\l          -- list databases
\c mydb     -- connect to database
\dt         -- list tables
\d+ users   -- describe table with details
\x          -- toggle expanded output
\timing     -- show query execution time
\df         -- list functions
\di         -- list indexes
```

## Table of Contents

| # | Topic | File |
|---|-------|------|
| 1 | [Basics: DDL, DML, Data Types](./docs/01-basics.md) | SELECT, INSERT, UPDATE, DELETE, CREATE TABLE, constraints |
| 2 | [Filtering, Sorting, Pagination](./docs/02-filtering-sorting.md) | WHERE, ORDER BY, LIMIT/OFFSET, DISTINCT |
| 3 | [Joins](./docs/03-joins.md) | INNER, OUTER, CROSS, LATERAL, self-joins |
| 4 | [Aggregations & Grouping](./docs/04-aggregations.md) | GROUP BY, HAVING, ROLLUP, CUBE, GROUPING SETS |
| 5 | [Subqueries & CTEs](./docs/05-subqueries-ctes.md) | Subqueries, WITH, recursive CTEs, MATERIALIZED |
| 6 | [Window Functions](./docs/06-window-functions.md) | OVER, PARTITION BY, frames, ranking, analytics |
| 7 | [Set Operations & Advanced SELECT](./docs/07-set-operations.md) | UNION, INTERSECT, EXCEPT, DISTINCT ON |
| 8 | [Data Types & Casting](./docs/08-data-types.md) | Numeric, text, temporal, JSON, arrays, ranges, enums |
| 9 | [JSON & JSONB](./docs/09-json.md) | Operators, path queries, indexing, aggregation |
| 10 | [Full-Text Search](./docs/10-full-text-search.md) | tsvector, tsquery, GIN indexes, ranking |
| 11 | [Indexes & Query Planning](./docs/11-indexes-performance.md) | B-tree, GIN, GiST, BRIN, SP-GiST — use cases & recipes |
| 12 | [Transactions & Concurrency](./docs/12-transactions.md) | ACID, isolation levels, locks, deadlocks |
| 13 | [Views & Materialized Views](./docs/13-views.md) | Views, MV refresh strategies, dashboard patterns |
| 14 | [Functions, Procedures & PL/pgSQL](./docs/14-plpgsql.md) | SQL/PLpgSQL functions, procedures, triggers |
| 15 | [Partitioning & Table Inheritance](./docs/15-partitioning.md) | Declarative partitioning, inheritance |
| 16 | [Advanced Patterns & Recipes](./docs/16-patterns.md) | Upsert, gaps-and-islands, pivot, temporal queries |
| 17 | [Administration & Maintenance](./docs/17-administration.md) | Roles, backups, VACUUM, monitoring |
| 18 | [Real-World Scenarios](./docs/18-scenarios.md) | E-commerce, HR, analytics recipes |

## Runnable Examples

```bash
psql -f examples/setup.sql                              # base schema
psql -f examples/scenarios-setup.sql                      # extended scenario tables
psql -f examples/functions-views-indexes.sql              # functions, MVs, indexes
```

## Sample Schema

Many examples use this schema. Run `examples/setup.sql` to create it:

```sql
-- See examples/setup.sql for full DDL and seed data
CREATE TABLE departments (id SERIAL PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE employees (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  department_id INT REFERENCES departments(id),
  salary NUMERIC(10,2),
  hired_at DATE
);
CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  customer_id INT,
  amount NUMERIC(10,2),
  status TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

## Conventions in This Reference

- **SQL keywords** are uppercase; identifiers are lowercase unless quoted
- `[optional]` marks optional clauses; `{a|b}` means choose one
- `⚠️` marks common pitfalls; `💡` marks performance tips
- Version tags like `(PG 15+)` indicate minimum PostgreSQL version

## Cheat Sheet

```sql
-- Upsert (INSERT ... ON CONFLICT)
INSERT INTO t (id, val) VALUES (1, 'a')
ON CONFLICT (id) DO UPDATE SET val = EXCLUDED.val;

-- Return rows from DML
INSERT INTO t (name) VALUES ('x') RETURNING id, name;
UPDATE t SET name = 'y' WHERE id = 1 RETURNING *;
DELETE FROM t WHERE id = 1 RETURNING id;

-- Existence check (prefer over COUNT)
SELECT EXISTS (SELECT 1 FROM t WHERE id = 1);

-- Safe division
SELECT val / NULLIF(divisor, 0) FROM t;

-- Date truncation & intervals
SELECT date_trunc('month', now()), now() - interval '7 days';

-- Array aggregation
SELECT department_id, array_agg(name ORDER BY name) FROM employees GROUP BY 1;

-- JSONB containment
SELECT * FROM docs WHERE metadata @> '{"status": "active"}';

-- Window: running total
SELECT id, amount,
       SUM(amount) OVER (ORDER BY created_at ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
FROM orders;
```

## License

Reference material for personal and educational use.
