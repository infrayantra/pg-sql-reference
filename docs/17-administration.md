# 17. Administration & Maintenance

## Roles, Users & Permissions

In PostgreSQL, **roles** encompass users and groups.

```sql
CREATE ROLE app_reader LOGIN PASSWORD 'secret';
CREATE ROLE app_writer LOGIN PASSWORD 'secret';
CREATE ROLE app_admin LOGIN PASSWORD 'secret' SUPERUSER;  -- avoid in apps

CREATE DATABASE myapp OWNER app_admin;

GRANT CONNECT ON DATABASE myapp TO app_reader;
GRANT USAGE ON SCHEMA ref TO app_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO app_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA ref
  GRANT SELECT ON TABLES TO app_reader;

GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ref TO app_writer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA ref TO app_writer;

-- Column-level
GRANT SELECT (id, name) ON ref.employees TO app_reader;

-- Row-level security (RLS)
ALTER TABLE ref.employees ENABLE ROW LEVEL SECURITY;
CREATE POLICY emp_dept_policy ON ref.employees
  FOR SELECT
  USING (department_id = current_setting('app.dept_id')::int);
```

### Role attributes

`LOGIN`, `SUPERUSER`, `CREATEDB`, `CREATEROLE`, `REPLICATION`, `BYPASSRLS`

```sql
\du                    -- list roles (psql)
SELECT * FROM pg_roles;
```

---

## Schemas & search_path

```sql
CREATE SCHEMA app AUTHORIZATION app_admin;
SET search_path TO app, public;

SHOW search_path;
-- Best practice: set search_path per role or at connection time
ALTER ROLE app_reader SET search_path TO ref, public;
```

---

## Backup & Restore

### Logical backup (pg_dump)

```bash
pg_dump -h localhost -U postgres -d mydb -Fc -f mydb.dump        # custom format
pg_dump -h localhost -U postgres -d mydb -c -f schema.sql --schema-only
pg_dump -h localhost -U postgres -d mydb -t ref.employees -f employees.sql

pg_restore -h localhost -U postgres -d mydb_restored mydb.dump
pg_restore -j 4 -d mydb_restored mydb.dump   # parallel restore
```

### All databases

```bash
pg_dumpall -h localhost -U postgres -f all.sql
```

### Physical backup

- Continuous archiving + WAL (Point-in-Time Recovery)
- `pg_basebackup` for base backup
- Tools: pgBackRest, Barman, WAL-G

---

## VACUUM & ANALYZE

PostgreSQL MVCC leaves dead tuples; VACUUM reclaims space.

```sql
VACUUM ref.employees;              -- reclaim space, update visibility map
VACUUM ANALYZE ref.employees;      -- vacuum + update statistics
VACUUM FULL ref.employees;         -- rewrites table (exclusive lock!)
```

Autovacuum runs automatically — tune via `autovacuum_vacuum_scale_factor`, `autovacuum_analyze_scale_factor`.

Monitor bloat:

```sql
SELECT schemaname, relname, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

---

## REINDEX

```sql
REINDEX TABLE ref.employees;
REINDEX INDEX CONCURRENTLY employees_email_idx;  -- PG 12+, no write block
```

---

## Connection Management

```sql
SELECT pid, usename, application_name, state, query, query_start
FROM pg_stat_activity
WHERE datname = current_database();

SELECT pg_terminate_backend(pid);   -- force disconnect
SELECT pg_cancel_backend(pid);      -- cancel running query only
```

Settings: `max_connections`, use **PgBouncer** or **pgpool** for pooling.

---

## Replication Overview

### Streaming replication (physical)

Standby receives WAL stream — hot standby for read replicas.

```sql
-- On primary: CREATE PUBLICATION / SUBSCRIPTION for logical replication
CREATE PUBLICATION mypub FOR TABLE ref.orders, ref.customers;
CREATE SUBSCRIPTION mysub
  CONNECTION 'host=primary dbname=mydb user=replicator'
  PUBLICATION mypub;
```

Logical replication: table-level, cross-version possible.

---

## Configuration

Main file: `postgresql.conf`

```ini
shared_buffers = 256MB          # ~25% RAM on dedicated server
effective_cache_size = 1GB      # planner hint for OS cache
work_mem = 16MB                 # per sort/hash operation
maintenance_work_mem = 256MB    # VACUUM, CREATE INDEX
random_page_cost = 1.1          # SSD tuning (default 4.0 for HDD)
effective_io_concurrency = 200  # SSD
wal_level = replica             # enable replication
log_min_duration_statement = 1000  # log queries > 1s
```

Reload: `SELECT pg_reload_conf();` or `pg_ctl reload`

Some params need restart: `shared_buffers`, `max_connections`

---

## Extensions

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS postgis;

SELECT * FROM pg_available_extensions;
```

---

## Useful Catalog Queries

```sql
-- Table sizes
SELECT relname, pg_size_pretty(pg_total_relation_size(oid))
FROM pg_class
WHERE relkind = 'r' AND relnamespace = 'ref'::regnamespace
ORDER BY pg_total_relation_size(oid) DESC;

-- Index usage
SELECT indexrelname, idx_scan, idx_tup_read
FROM pg_stat_user_indexes
WHERE schemaname = 'ref';

-- Unused indexes
SELECT indexrelname FROM pg_stat_user_indexes WHERE idx_scan = 0;

-- Locks
SELECT * FROM pg_locks WHERE NOT granted;

-- Blocking queries
SELECT blocked.pid AS blocked_pid, blocking.pid AS blocking_pid,
       blocked.query AS blocked_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid));
```

---

## Security Checklist

- Least-privilege roles; no SUPERUSER for apps
- ` scram-sha-256` password encryption
- SSL/TLS for connections
- RLS for multi-tenant data isolation
- Audit logging (pgaudit extension)
- Keep PostgreSQL patched

---

## Upgrade Paths

- **pg_upgrade** — in-place major version upgrade
- **Logical replication** — minimal downtime migration
- Dump/restore — simplest, longest downtime

---

## Reference Complete

Return to [README](../README.md) for the full index and cheat sheet.
