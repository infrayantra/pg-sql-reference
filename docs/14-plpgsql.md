# 14. Functions, Procedures & PL/pgSQL

Complete guide to PostgreSQL server-side logic: SQL functions, PL/pgSQL functions, procedures, triggers, and practical patterns.

## Function vs Procedure vs Trigger

| | Function | Procedure `(PG 11+)` | Trigger Function |
|---|----------|----------------------|------------------|
| Invoked via | `SELECT fn()` | `CALL proc()` | Trigger event |
| Returns value | Required (or VOID) | Optional OUT params | `TRIGGER` type |
| Use in SQL expressions | Yes | No | No |
| COMMIT / ROLLBACK | No (runs in caller txn) | **Yes** | No |
| Side effects | Should be minimal | Batch jobs, ETL | Audit, validation |

---

## SQL Functions

Pure SQL body — often **inlined** by the planner (zero function call overhead).

### Scalar function

```sql
CREATE OR REPLACE FUNCTION ref.employee_annual_salary(p_salary NUMERIC)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_salary * 12;
$$;

SELECT name, ref.employee_annual_salary(salary) AS annual
FROM ref.employees;
```

### Function taking composite type

```sql
CREATE OR REPLACE FUNCTION ref.employee_annual_salary(emp ref.employees)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
  SELECT emp.salary * 12;
$$;
```

### SQL function with multiple statements `(PG 14+)`

```sql
CREATE OR REPLACE FUNCTION ref.dept_stats(p_dept_id INT)
RETURNS TABLE(headcount BIGINT, avg_salary NUMERIC, total_payroll NUMERIC)
LANGUAGE sql
STABLE
AS $$
  SELECT COUNT(*)::bigint, AVG(salary), SUM(salary)
  FROM ref.employees
  WHERE department_id = p_dept_id AND is_active;
$$;

SELECT * FROM ref.dept_stats(1);
```

### Volatility categories (critical for optimization)

| Category | Guarantees | Examples |
|----------|------------|----------|
| `IMMUTABLE` | Same inputs → same output always; no DB read | `lower()`, math, `salary * 12` |
| `STABLE` | Same result within one query; no modifications | `now()` in stable context, reads table |
| `VOLATILE` | Default; can change DB, time, random | `random()`, `nextval()`, INSERT |

```sql
-- IMMUTABLE → usable in indexes and generated columns
CREATE INDEX employees_annual ON ref.employees ((ref.employee_annual_salary(salary)));
```

⚠️ Marking a function `IMMUTABLE` when it reads tables or calls `now()` causes **wrong results** and stale indexes.

---

## PL/pgSQL Functions

Procedural language with variables, control flow, exceptions, and dynamic SQL.

### Basic structure

```sql
CREATE OR REPLACE FUNCTION ref.give_raise(p_emp_id INT, p_pct NUMERIC)
RETURNS ref.employees
LANGUAGE plpgsql
AS $$
DECLARE
  v_emp      ref.employees;
  v_old_sal  NUMERIC;
BEGIN
  SELECT salary INTO v_old_sal FROM ref.employees WHERE id = p_emp_id;
  IF v_old_sal IS NULL THEN
    RAISE EXCEPTION 'Employee % not found', p_emp_id USING ERRCODE = 'P0002';
  END IF;

  UPDATE ref.employees
  SET salary = salary * (1 + p_pct / 100)
  WHERE id = p_emp_id
  RETURNING * INTO v_emp;

  RAISE NOTICE 'Employee %: % -> %', p_emp_id, v_old_sal, v_emp.salary;
  RETURN v_emp;
END;
$$;

SELECT * FROM ref.give_raise(2, 5);
```

### Variable declarations

```sql
DECLARE
  v_count       INT;
  v_name        TEXT := 'default';
  v_row         ref.employees%ROWTYPE;       -- whole row type
  v_dept_name   ref.departments.name%TYPE;   -- column type alias
  v_ids         INT[] := ARRAY[1, 2, 3];
  v_rec         RECORD;                       -- anonymous record
```

### Assignment

```sql
v_count := 10;
SELECT COUNT(*) INTO v_count FROM ref.employees;
SELECT name INTO STRICT v_name FROM ref.employees WHERE id = 1;  -- error if not exactly 1 row
v_row := ref.give_raise(1, 3);
PERFORM ref.give_raise(1, 3);  -- discard return value
```

### Control flow: IF / CASE

```sql
IF p_pct < 0 THEN
  RAISE EXCEPTION 'Negative raise not allowed';
ELSIF p_pct > 50 THEN
  RAISE WARNING 'Large raise: % percent', p_pct;
END IF;

CASE p_dept_id
  WHEN 1 THEN v_bonus := 5000;
  WHEN 2 THEN v_bonus := 3000;
  ELSE v_bonus := 1000;
END CASE;
```

### Loops

```sql
-- FOR over query
FOR v_rec IN SELECT id, name FROM ref.employees WHERE department_id = 1 LOOP
  RAISE NOTICE '%: %', v_rec.id, v_rec.name;
END LOOP;

-- FOR over integer range
FOR i IN 1..10 LOOP
  INSERT INTO ref.audit_log (table_name, operation) VALUES ('batch', 'step ' || i);
END LOOP;

-- FOR over array
FOREACH v_id IN ARRAY v_ids LOOP
  PERFORM ref.give_raise(v_id, 2);
END LOOP;

-- WHILE
WHILE v_count > 0 LOOP
  v_count := v_count - 1;
END LOOP;

-- EXIT / CONTINUE with labels
<<outer>>
FOR i IN 1..5 LOOP
  EXIT outer WHEN i = 3;
END LOOP;
```

### RETURN variants

```sql
RETURN v_emp;                    -- scalar / composite
RETURN NEXT v_row; RETURN;       -- set-returning: add row, then finalize
RETURN QUERY SELECT ...;          -- append query results to SRF output
RETURN;                          -- void function exit
```

---

## Set-Returning Functions (SRF)

Return multiple rows — use as table source.

```sql
CREATE OR REPLACE FUNCTION ref.dept_employee_names(p_dept_id INT)
RETURNS TABLE(emp_id INT, emp_name TEXT, annual NUMERIC)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT id, name, salary * 12
  FROM ref.employees
  WHERE department_id = p_dept_id AND is_active
  ORDER BY name;
END;
$$;

SELECT * FROM ref.dept_employee_names(1);
SELECT emp_name FROM ref.dept_employee_names(1) WHERE annual > 100000;
```

### Generate rows procedurally

```sql
CREATE OR REPLACE FUNCTION ref.generate_dates(p_start DATE, p_end DATE)
RETURNS TABLE(day DATE)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_day DATE := p_start;
BEGIN
  WHILE v_day <= p_end LOOP
    RETURN NEXT v_day;
    v_day := v_day + 1;
  END LOOP;
END;
$$;

SELECT * FROM ref.generate_dates('2024-06-01', '2024-06-07');
```

---

## Exception Handling

```sql
BEGIN
  INSERT INTO ref.employees (email, name, department_id, salary, hired_at)
  VALUES ('alice@co.com', 'Duplicate', 1, 50000, CURRENT_DATE);
EXCEPTION
  WHEN unique_violation THEN
    RAISE NOTICE 'Email already exists';
  WHEN check_violation THEN
    RAISE EXCEPTION 'Validation failed: %', SQLERRM;
  WHEN OTHERS THEN
    RAISE NOTICE 'SQLSTATE: %, Message: %', SQLSTATE, SQLERRM;
    RAISE;  -- re-throw
END;
```

### Common SQLSTATE codes

| Code | Condition |
|------|-----------|
| `23505` | unique_violation |
| `23503` | foreign_key_violation |
| `23514` | check_violation |
| `P0002` | no_data_found (custom) |

```sql
GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
```

---

## RAISE — Logging & Errors

```sql
RAISE DEBUG   'debug %', var;      -- visible at debug level
RAISE LOG     'logged';            -- server log
RAISE NOTICE  'notice';            -- client message
RAISE WARNING 'warning';           -- warning
RAISE EXCEPTION 'fatal: %', sqlerrm USING ERRCODE = '22000', HINT = 'Check input';
```

---

## Procedures `(PG 11+)`

Procedures **do not return a value** but can have `IN`, `OUT`, `INOUT` parameters and **commit/rollback independently**.

### Basic procedure

```sql
CREATE OR REPLACE PROCEDURE ref.transfer_employee(
  p_emp_id      INT,
  p_new_dept_id INT
)
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE ref.employees
  SET department_id = p_new_dept_id
  WHERE id = p_emp_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee % not found', p_emp_id;
  END IF;
END;
$$;

CALL ref.transfer_employee(2, 2);
```

### Procedure with OUT parameters

```sql
CREATE OR REPLACE PROCEDURE ref.get_dept_headcount(
  p_dept_id   INT,
  INOUT p_count INT DEFAULT 0
)
LANGUAGE plpgsql
AS $$
BEGIN
  SELECT COUNT(*) INTO p_count
  FROM ref.employees
  WHERE department_id = p_dept_id AND is_active;
END;
$$;

CALL ref.get_dept_headcount(1, NULL);  -- p_count returned
```

### Procedure with COMMIT (multi-step batch)

```sql
CREATE OR REPLACE PROCEDURE ref.archive_old_orders(p_days INT)
LANGUAGE plpgsql
AS $$
DECLARE
  v_cutoff TIMESTAMPTZ := now() - (p_days || ' days')::interval;
  v_archived INT;
BEGIN
  CREATE TABLE IF NOT EXISTS ref.orders_archive (LIKE ref.orders INCLUDING ALL);

  INSERT INTO ref.orders_archive
  SELECT * FROM ref.orders WHERE created_at < v_cutoff;
  GET DIAGNOSTICS v_archived = ROW_COUNT;

  DELETE FROM ref.orders WHERE created_at < v_cutoff;

  COMMIT;  -- only allowed in PROCEDURE, not FUNCTION
  RAISE NOTICE 'Archived % orders older than %', v_archived, v_cutoff;
END;
$$;

CALL ref.archive_old_orders(365);
```

### Use case: Batch processing in chunks

```sql
CREATE OR REPLACE PROCEDURE ref.process_events_batch(p_batch_size INT DEFAULT 1000)
LANGUAGE plpgsql
AS $$
DECLARE
  v_processed INT;
BEGIN
  LOOP
    WITH batch AS (
      SELECT id FROM ref.events
      WHERE payload ->> 'processed' IS NULL
      LIMIT p_batch_size
      FOR UPDATE SKIP LOCKED
    )
    UPDATE ref.events e
    SET payload = e.payload || '{"processed": true}'::jsonb
    FROM batch b WHERE e.id = b.id;

    GET DIAGNOSTICS v_processed = ROW_COUNT;
    EXIT WHEN v_processed = 0;
    COMMIT;
    RAISE NOTICE 'Processed % events', v_processed;
  END LOOP;
END;
$$;
```

### Use case: Swap tables safely

```sql
CREATE OR REPLACE PROCEDURE ref.swap_staging_to_prod()
LANGUAGE plpgsql
AS $$
BEGIN
  ALTER TABLE ref.products RENAME TO products_old;
  ALTER TABLE ref.products_staging RENAME TO products;
  ALTER TABLE ref.products_old RENAME TO products_staging;
  COMMIT;
END;
$$;
```

⚠️ Procedures with `COMMIT` cannot be called from within a function or trigger.

---

## Dynamic SQL

Build and execute SQL at runtime — always sanitize with `format()`.

```sql
CREATE OR REPLACE FUNCTION ref.count_by_column(
  p_table  TEXT,
  p_column TEXT,
  p_value  TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_count BIGINT;
BEGIN
  -- %I = identifier (quoted), %L = literal (escaped), %s = string (unsafe for user input)
  EXECUTE format(
    'SELECT COUNT(*) FROM %I.%I WHERE %I = $1',
    'ref', p_table, p_column
  ) INTO v_count USING p_value;
  RETURN v_count;
END;
$$;
```

### Dynamic ORDER BY (whitelist pattern)

```sql
CREATE OR REPLACE FUNCTION ref.list_employees_sorted(p_column TEXT, p_dir TEXT DEFAULT 'ASC')
RETURNS SETOF ref.employees
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF p_column NOT IN ('name', 'salary', 'hired_at') THEN
    RAISE EXCEPTION 'Invalid sort column: %', p_column;
  END IF;
  IF upper(p_dir) NOT IN ('ASC', 'DESC') THEN
    RAISE EXCEPTION 'Invalid direction: %', p_dir;
  END IF;
  RETURN QUERY EXECUTE format(
    'SELECT * FROM ref.employees ORDER BY %I %s',
    p_column, p_dir
  );
END;
$$;
```

---

## Triggers

### Audit trigger (AFTER)

```sql
CREATE OR REPLACE FUNCTION ref.audit_employee_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO ref.audit_log (table_name, operation, row_data)
    VALUES ('employees', TG_OP, to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO ref.audit_log (table_name, operation, row_data)
    VALUES ('employees', TG_OP, jsonb_build_object('old', OLD, 'new', NEW));
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO ref.audit_log (table_name, operation, row_data)
    VALUES ('employees', TG_OP, to_jsonb(OLD));
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

CREATE TRIGGER employees_audit
  AFTER INSERT OR UPDATE OR DELETE ON ref.employees
  FOR EACH ROW EXECUTE FUNCTION ref.audit_employee_changes();
```

### Validation trigger (BEFORE)

```sql
CREATE OR REPLACE FUNCTION ref.validate_salary()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.salary > 500000 THEN
    RAISE EXCEPTION 'Salary exceeds maximum allowed';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.salary < OLD.salary * 0.5 THEN
    RAISE EXCEPTION 'Salary decrease exceeds 50%%';
  END IF;
  NEW.updated_at := now();  -- auto timestamp
  RETURN NEW;
END;
$$;

CREATE TRIGGER employees_validate
  BEFORE INSERT OR UPDATE ON ref.employees
  FOR EACH ROW EXECUTE FUNCTION ref.validate_salary();
```

### Use case: Maintain derived column / tsvector

```sql
CREATE OR REPLACE FUNCTION ref.articles_tsv_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.tsv := to_tsvector('english', coalesce(NEW.title, '') || ' ' || coalesce(NEW.body, ''));
  RETURN NEW;
END;
$$;

CREATE TRIGGER articles_tsv
  BEFORE INSERT OR UPDATE ON ref.articles
  FOR EACH ROW EXECUTE FUNCTION ref.articles_tsv_update();
```

### Use case: INSTEAD OF trigger on view

```sql
CREATE OR REPLACE FUNCTION ref.emp_names_insert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO ref.employees (id, name, department_id, salary, hired_at)
  VALUES (NEW.id, NEW.name, NEW.department_id, 50000, CURRENT_DATE);
  RETURN NEW;
END;
$$;

CREATE TRIGGER emp_names_insert_tr
  INSTEAD OF INSERT ON ref.emp_names
  FOR EACH ROW EXECUTE FUNCTION ref.emp_names_insert();
```

### Trigger timing summary

```
BEFORE  → can modify NEW; abort with RAISE EXCEPTION
AFTER   → audit, side effects; cannot change row
INSTEAD OF → only on views; replaces the DML
FOR EACH ROW vs FOR EACH STATEMENT
WHEN (condition) → filter which rows fire row triggers
```

---

## Event Triggers (DDL hooks)

```sql
CREATE OR REPLACE FUNCTION ref.log_ddl()
RETURNS event_trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE NOTICE 'DDL command: %', tg_tag;
END;
$$;

CREATE EVENT TRIGGER ddl_logger ON ddl_command_end
  EXECUTE FUNCTION ref.log_ddl();
```

---

## Function Security

```sql
-- SECURITY DEFINER: runs as owner (elevated privileges — use carefully)
CREATE FUNCTION ref.admin_reset_password(p_user TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ref, pg_temp  -- prevent search_path hijacking
AS $$ ... $$;

-- SECURITY INVOKER (default): runs as caller
```

⚠️ Always `SET search_path` on `SECURITY DEFINER` functions.

---

## Managing Functions & Procedures

```sql
-- List
\df ref.*
SELECT proname, prokind, provolatile, prosecdef
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'ref';

-- Drop
DROP FUNCTION IF EXISTS ref.give_raise(INT, NUMERIC);
DROP PROCEDURE IF EXISTS ref.archive_old_orders(INT);

-- Replace signature = new function
CREATE OR REPLACE FUNCTION ref.give_raise(p_emp_id INT, p_pct NUMERIC, p_reason TEXT DEFAULT NULL)
...
```

`prokind`: `f` = function, `p` = procedure, `a` = aggregate, `w` = window

---

## Practical Patterns Summary

| Task | Use |
|------|-----|
| Computed column in query | SQL function (IMMUTABLE) |
| Business logic + validation | PL/pgSQL function |
| Multi-step ETL with commits | Procedure |
| Row-level audit | AFTER trigger |
| Reject bad data | BEFORE trigger |
| Auto-maintain search vector | BEFORE trigger |
| Dynamic reporting | PL/pgSQL + EXECUTE format |
| Batch job queue | Procedure + COMMIT in loop |

---

## Next

→ [15. Partitioning & Table Inheritance](./15-partitioning.md)
