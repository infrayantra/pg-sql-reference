# 8. Data Types & Casting

## Type Casting

```sql
-- PostgreSQL cast syntax
SELECT '123'::integer;
SELECT CAST('123' AS integer);

-- Function-style (some types)
SELECT to_number('1,234.56', '9,999.99');
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_timestamp('2024-06-15 14:30', 'YYYY-MM-DD HH24:MI');
```

---

## Arrays

```sql
-- Literals
SELECT ARRAY[1, 2, 3];
SELECT '{hardware,pro}'::text[];

-- Access (1-based indexing)
SELECT tags[1], tags[2:3] FROM ref.products;

-- Array functions
SELECT array_length(tags, 1), cardinality(tags) FROM ref.products;
SELECT unnest(tags) FROM ref.products WHERE id = 1;  -- rows from array
SELECT array_agg(name ORDER BY name) FROM ref.employees;

-- ANY / ALL with arrays
SELECT * FROM ref.products WHERE 'pro' = ANY(tags);
SELECT * FROM ref.products WHERE tags @> ARRAY['hardware'];

-- Array operators
||   -- concatenate
@>   -- contains
<@   -- contained by
&&   -- overlap

-- Multidimensional
SELECT ARRAY[[1,2],[3,4]];
```

### GIN index on arrays

```sql
CREATE INDEX products_tags_gin ON ref.products USING GIN (tags);
```

---

## Composite Types

```sql
CREATE TYPE ref.address AS (
  street TEXT,
  city   TEXT,
  zip    TEXT
);

CREATE TABLE ref.locations (
  id SERIAL PRIMARY KEY,
  name TEXT,
  addr ref.address
);

INSERT INTO ref.locations (name, addr)
VALUES ('HQ', ROW('123 Main St', 'NYC', '10001'));

SELECT (addr).city FROM ref.locations;  -- field access
```

---

## Enumerated Types

```sql
CREATE TYPE ref.order_status AS ENUM ('pending', 'paid', 'shipped', 'cancelled');

ALTER TYPE ref.order_status ADD VALUE 'refunded' AFTER 'shipped';

SELECT enum_range(NULL::ref.order_status);
```

💡 ENUMs are hard to modify in production. Consider TEXT + CHECK or lookup tables.

---

## Range Types

Built-in: `int4range`, `int8range`, `numrange`, `tsrange`, `tstzrange`, `daterange`

```sql
CREATE TABLE ref.reservations (
  id SERIAL PRIMARY KEY,
  room INT,
  during tstzrange NOT NULL,
  EXCLUDE USING GIST (room WITH =, during WITH &&)
);

INSERT INTO ref.reservations (room, during)
VALUES (101, tstzrange('2024-06-01 14:00', '2024-06-05 11:00', '[)'));

SELECT * FROM ref.reservations
WHERE during @> '2024-06-03 09:00'::timestamptz;

-- Range operators
@>  contains
<@  contained by
&&  overlaps
<<  strictly left of
>>  strictly right of
```

---

## Network Types

```sql
SELECT '192.168.1.0/24'::cidr;
SELECT '192.168.1.42'::inet;
SELECT inet '192.168.1.0/24' >> inet '192.168.1.42';  -- contains
SELECT macaddr '08:00:2b:01:02:03';
```

---

## UUID

```sql
SELECT gen_random_uuid();  -- PG 13+ pgcrypto/builtin
SELECT uuid_generate_v4(); -- uuid-ossp extension

CREATE TABLE ref.tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid()
);
```

---

## Binary Data

```sql
SELECT bytea E'\\xDEADBEEF';
SELECT encode(digest('hello', 'sha256'), 'hex');  -- pgcrypto
```

---

## Domain Types

```sql
CREATE DOMAIN ref.email AS TEXT
  CHECK (VALUE ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

CREATE TABLE ref.contacts (id SERIAL PRIMARY KEY, address ref.email);
```

---

## Collation

```sql
SELECT name FROM ref.employees ORDER BY name COLLATE "C";  -- byte-order sort
CREATE TABLE ref.names (name TEXT COLLATE "en_US");
```

---

## JSON vs JSONB

| | JSON | JSONB |
|---|------|-------|
| Storage | Text, preserved whitespace | Binary, decomposed |
| Insert speed | Faster | Slightly slower |
| Query/index | Slower | **Preferred** |
| Duplicate keys | Preserved | Last wins |

See [09. JSON & JSONB](./09-json.md) for full coverage.

---

## hstore Extension

Key-value pairs (legacy; prefer JSONB for new projects).

```sql
CREATE EXTENSION hstore;
SELECT hstore('key1', 'val1') || hstore('key2', 'val2');
```

---

## pg_trgm — Trigram Similarity

```sql
CREATE EXTENSION pg_trgm;
SELECT similarity('PostgreSQL', 'Postgres');
SELECT * FROM ref.products WHERE name % 'Widgt';  -- fuzzy match
CREATE INDEX products_name_trgm ON ref.products USING GIN (name gin_trgm_ops);
```

---

## Custom Base Types & Extensions

PostGIS (`geometry`, `geography`), `ltree`, `cube`, `seg`, etc. — install via `CREATE EXTENSION`.

---

## Next

→ [09. JSON & JSONB](./09-json.md)
