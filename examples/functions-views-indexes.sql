-- Runnable examples: functions, procedures, materialized views, indexes
-- Run: psql -f examples/setup.sql -f examples/functions-views-indexes.sql

SET search_path TO ref, public;

-- ============================================================
-- B-TREE INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_employees_dept_salary
  ON employees (department_id, salary DESC);

CREATE INDEX IF NOT EXISTS idx_employees_active_dept
  ON employees (department_id) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_orders_customer_created
  ON orders (customer_id, created_at DESC);

-- ============================================================
-- GIN INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_products_metadata_gin
  ON products USING GIN (metadata);

CREATE INDEX IF NOT EXISTS idx_products_tags_gin
  ON products USING GIN (tags);

-- ============================================================
-- BRIN INDEX
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_events_occurred_brin
  ON events USING BRIN (occurred_at);

CREATE INDEX IF NOT EXISTS idx_orders_created_brin
  ON orders USING BRIN (created_at);

-- ============================================================
-- MATERIALIZED VIEWS
-- ============================================================
DROP MATERIALIZED VIEW IF EXISTS monthly_revenue;
CREATE MATERIALIZED VIEW monthly_revenue AS
SELECT date_trunc('month', created_at) AS month,
       SUM(total) AS revenue,
       COUNT(*) AS order_count
FROM orders
WHERE status IN ('paid', 'shipped')
GROUP BY 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_monthly_revenue_month ON monthly_revenue (month);

DROP MATERIALIZED VIEW IF EXISTS customer_ltv;
CREATE MATERIALIZED VIEW customer_ltv AS
SELECT c.id AS customer_id,
       c.name,
       COUNT(o.id) AS order_count,
       COALESCE(SUM(o.total), 0) AS lifetime_value
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id AND o.status IN ('paid', 'shipped')
GROUP BY c.id, c.name;

CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_ltv_id ON customer_ltv (customer_id);

-- ============================================================
-- SQL FUNCTIONS
-- ============================================================
CREATE OR REPLACE FUNCTION employee_annual_salary(p_salary NUMERIC)
RETURNS NUMERIC LANGUAGE sql IMMUTABLE AS $$
  SELECT p_salary * 12;
$$;

CREATE OR REPLACE FUNCTION dept_stats(p_dept_id INT)
RETURNS TABLE(headcount BIGINT, avg_salary NUMERIC, total_payroll NUMERIC)
LANGUAGE sql STABLE AS $$
  SELECT COUNT(*)::bigint, AVG(salary), SUM(salary)
  FROM employees WHERE department_id = p_dept_id AND is_active;
$$;

-- ============================================================
-- PL/pgSQL FUNCTIONS
-- ============================================================
CREATE OR REPLACE FUNCTION give_raise(p_emp_id INT, p_pct NUMERIC)
RETURNS employees
LANGUAGE plpgsql AS $$
DECLARE
  v_emp employees;
BEGIN
  UPDATE employees
  SET salary = salary * (1 + p_pct / 100)
  WHERE id = p_emp_id
  RETURNING * INTO v_emp;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee % not found', p_emp_id;
  END IF;
  RETURN v_emp;
END;
$$;

CREATE OR REPLACE FUNCTION dept_employee_names(p_dept_id INT)
RETURNS TABLE(emp_id INT, emp_name TEXT, annual NUMERIC)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN QUERY
  SELECT id, name, salary * 12
  FROM employees
  WHERE department_id = p_dept_id AND is_active
  ORDER BY name;
END;
$$;

-- ============================================================
-- PROCEDURES
-- ============================================================
CREATE OR REPLACE PROCEDURE transfer_employee(p_emp_id INT, p_new_dept_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE employees SET department_id = p_new_dept_id WHERE id = p_emp_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee % not found', p_emp_id;
  END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE refresh_all_mvs()
LANGUAGE plpgsql AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_revenue;
  REFRESH MATERIALIZED VIEW CONCURRENTLY customer_ltv;
  RAISE NOTICE 'Materialized views refreshed at %', now();
END;
$$;

-- ============================================================
-- AUDIT LOG TABLE + TRIGGER
-- ============================================================
CREATE TABLE IF NOT EXISTS audit_log (
  id          BIGSERIAL PRIMARY KEY,
  table_name  TEXT NOT NULL,
  operation   TEXT NOT NULL,
  row_data    JSONB,
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION audit_employee_changes()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    INSERT INTO audit_log (table_name, operation, row_data)
    VALUES ('employees', TG_OP, to_jsonb(OLD));
    RETURN OLD;
  ELSE
    INSERT INTO audit_log (table_name, operation, row_data)
    VALUES ('employees', TG_OP, to_jsonb(NEW));
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS employees_audit ON employees;
CREATE TRIGGER employees_audit
  AFTER INSERT OR UPDATE OR DELETE ON employees
  FOR EACH ROW EXECUTE FUNCTION audit_employee_changes();

-- ============================================================
-- DEMO QUERIES (uncomment to run)
-- ============================================================
-- SELECT * FROM dept_stats(1);
-- SELECT * FROM give_raise(2, 5);
-- CALL transfer_employee(3, 2);
-- CALL refresh_all_mvs();
-- SELECT * FROM monthly_revenue;
-- SELECT * FROM customer_ltv ORDER BY lifetime_value DESC;
-- EXPLAIN ANALYZE SELECT * FROM products WHERE metadata @> '{"warranty_years": 2}';
-- EXPLAIN ANALYZE SELECT * FROM orders WHERE created_at >= '2024-01-01';
