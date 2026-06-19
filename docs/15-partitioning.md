# 15. Partitioning & Table Inheritance

## Declarative Partitioning `(PG 10+)`

Native partitioning — preferred over legacy inheritance for new designs.

### RANGE partitioning

```sql
CREATE TABLE ref.events_partitioned (
  id          BIGSERIAL,
  user_id     INT,
  event_type  TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,
  payload     JSONB
) PARTITION BY RANGE (occurred_at);

CREATE TABLE ref.events_2024_q1
  PARTITION OF ref.events_partitioned
  FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

CREATE TABLE ref.events_2024_q2
  PARTITION OF ref.events_partitioned
  FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');

CREATE TABLE ref.events_default
  PARTITION OF ref.events_partitioned DEFAULT;
```

### LIST partitioning

```sql
CREATE TABLE ref.orders_by_region (
  id SERIAL,
  region TEXT NOT NULL,
  total NUMERIC
) PARTITION BY LIST (region);

CREATE TABLE ref.orders_us PARTITION OF ref.orders_by_region FOR VALUES IN ('US');
CREATE TABLE ref.orders_eu PARTITION OF ref.orders_by_region FOR VALUES IN ('UK', 'DE', 'FR');
```

### HASH partitioning

```sql
CREATE TABLE ref.metrics (
  id BIGSERIAL,
  shard_key INT NOT NULL,
  value NUMERIC
) PARTITION BY HASH (shard_key);

CREATE TABLE ref.metrics_p0 PARTITION OF ref.metrics FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE ref.metrics_p1 PARTITION OF ref.metrics FOR VALUES WITH (MODULUS 4, REMAINDER 1);
-- ... p2, p3
```

---

## Partition Pruning

Planner skips irrelevant partitions when WHERE matches partition key:

```sql
EXPLAIN SELECT * FROM ref.events_partitioned
WHERE occurred_at >= '2024-05-01' AND occurred_at < '2024-06-01';
-- Only scans events_2024_q2
```

Enable `enable_partition_pruning = on` (default).

---

## Partition Maintenance

```sql
-- Detach (non-blocking in PG 14+ with CONCURRENTLY)
ALTER TABLE ref.events_partitioned DETACH PARTITION ref.events_2024_q1;
ALTER TABLE ref.events_partitioned DETACH PARTITION ref.events_2024_q1 CONCURRENTLY;

-- Attach existing table
ALTER TABLE ref.events_partitioned ATTACH PARTITION ref.events_2024_q3
  FOR VALUES FROM ('2024-07-01') TO ('2024-10-01');

-- Drop old partition (fast — drops table)
DROP TABLE ref.events_2024_q1;
```

### Auto partition creation

Use pg_partman extension or scheduled jobs:

```sql
CREATE TABLE ref.events_2024_q4 PARTITION OF ref.events_partitioned
  FOR VALUES FROM ('2024-10-01') TO ('2025-01-01');
```

---

## Indexes on Partitioned Tables

```sql
CREATE INDEX ON ref.events_partitioned (user_id);
-- Creates index on each partition automatically (PG 11+)
```

---

## Unique Constraints & Primary Keys

Partition key must be included in PK/UNIQUE:

```sql
PRIMARY KEY (id, occurred_at)  -- occurred_at is partition key
```

---

## Legacy Table Inheritance

```sql
CREATE TABLE ref.logs () INHERITS (ref.events);
-- Query parent includes children unless ONLY keyword:
SELECT * FROM ONLY ref.events;
```

Declarative partitioning supersedes inheritance for most use cases.

---

## When to Partition

| Good candidates | Poor candidates |
|-----------------|-----------------|
| Time-series (events, logs) | Small tables |
| Archival by date (drop partitions) | Heavy cross-partition joins |
| Tenant isolation (LIST/HASH) | Frequent updates moving rows across boundaries |

---

## Next

→ [16. Advanced Patterns & Recipes](./16-patterns.md)
