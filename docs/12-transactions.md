# 12. Transactions & Concurrency

## ACID Properties

| Property | PostgreSQL mechanism |
|----------|---------------------|
| **Atomicity** | All statements in transaction commit or rollback together |
| **Consistency** | Constraints checked; deferrable constraints at commit |
| **Isolation** | MVCC — readers don't block writers |
| **Durability** | WAL (Write-Ahead Log) flushed to disk |

---

## Transaction Control

```sql
BEGIN;                    -- or START TRANSACTION
-- statements...
COMMIT;                   -- or END (not recommended — confused with PL/pgSQL END)
ROLLBACK;

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SAVEPOINT sp1;
-- ...
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
COMMIT;
```

### Autocommit

Default in psql: each statement is its own transaction unless wrapped in `BEGIN`.

---

## Isolation Levels

| Level | Dirty Read | Non-repeatable Read | Phantom Read |
|-------|------------|---------------------|--------------|
| READ UNCOMMITTED | — (PG treats as READ COMMITTED) | Possible | Possible |
| READ COMMITTED | No | Possible | Possible |
| REPEATABLE READ | No | No | No* |
| SERIALIZABLE | No | No | No |

*PostgreSQL's REPEATABLE READ prevents phantom reads via MVCC snapshot.

```sql
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

### READ COMMITTED (default)

Each statement sees a fresh snapshot — another transaction's committed changes visible on next statement.

### REPEATABLE READ

Single snapshot for entire transaction — consistent reads; write conflicts may abort:

```
ERROR: could not serialize access due to concurrent update
```

### SERIALIZABLE

Serializable Snapshot Isolation (SSI) — detects read/write dependencies; may abort with:

```
ERROR: could not serialize access due to read/write dependencies among transactions
```

Retry on serialization failure in application code.

---

## MVCC Overview

- `INSERT` creates new row version
- `UPDATE` = delete mark old + insert new version
- `DELETE` marks row dead (visible to open transactions)
- `VACUUM` reclaims dead tuple space

Each row has system columns:

```sql
SELECT xmin, xmax, ctid FROM ref.employees LIMIT 1;
```

---

## Lock Types

### Row-level (automatic)

- `FOR UPDATE` — exclusive
- `FOR NO KEY UPDATE` — weaker exclusive
- `FOR SHARE` — shared
- `FOR KEY SHARE` — weakest

### Table-level

```sql
LOCK TABLE ref.employees IN ACCESS EXCLUSIVE MODE;  -- blocks all access
LOCK TABLE ref.employees IN SHARE ROW EXCLUSIVE MODE;
```

`ACCESS EXCLUSIVE` taken by `ALTER TABLE`, `DROP`, `VACUUM FULL`, `REINDEX`.

### Advisory locks

Application-defined coordination:

```sql
SELECT pg_advisory_lock(12345);
SELECT pg_try_advisory_lock(12345);  -- non-blocking
SELECT pg_advisory_unlock(12345);

-- Transaction-scoped
SELECT pg_advisory_xact_lock(hashtext('my_job'));
```

---

## Deadlocks

PostgreSQL detects deadlocks automatically and aborts one transaction:

```
ERROR: deadlock detected
DETAIL: Process 123 waits for ShareLock on transaction 456; blocked by process 789...
```

💡 Acquire locks in consistent order across transactions.

---

## Optimistic Concurrency — Version Column

```sql
ALTER TABLE ref.employees ADD COLUMN version INT NOT NULL DEFAULT 1;

UPDATE ref.employees
SET salary = 96000, version = version + 1
WHERE id = 2 AND version = 5;
-- Check ROW_COUNT = 1; if 0, someone else updated — retry
```

---

## Two-Phase Commit (Distributed)

```sql
PREPARE TRANSACTION 'txn_001';
COMMIT PREPARED 'txn_001';
ROLLBACK PREPARED 'txn_001';
```

---

## Connection Pooling Note

Transaction-level pooling (PgBouncer transaction mode) incompatible with prepared statements, temp tables, and `SET` per session — use session mode or reset hooks.

---

## Next

→ [13. Views, Rules & Materialized Views](./13-views.md)
