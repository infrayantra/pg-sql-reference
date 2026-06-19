-- Extended schema for scenario examples
-- Run after setup.sql: psql -f examples/setup.sql -f examples/scenarios-setup.sql

SET search_path TO ref, public;

-- Inventory
CREATE TABLE IF NOT EXISTS inventory (
  product_id  INT PRIMARY KEY REFERENCES products(id),
  quantity    INT NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  reserved    INT NOT NULL DEFAULT 0 CHECK (reserved >= 0),
  warehouse   TEXT NOT NULL DEFAULT 'main'
);

INSERT INTO inventory (product_id, quantity, reserved) VALUES
  (1, 100, 5), (2, 250, 0), (3, 999, 0)
ON CONFLICT (product_id) DO NOTHING;

-- Order status history (state machine / funnel)
CREATE TABLE IF NOT EXISTS order_status_history (
  id          SERIAL PRIMARY KEY,
  order_id    INT NOT NULL REFERENCES orders(id),
  old_status  TEXT,
  new_status  TEXT NOT NULL,
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO order_status_history (order_id, old_status, new_status, changed_at) VALUES
  (1, NULL, 'pending', '2024-01-15 10:00:00+00'),
  (1, 'pending', 'paid', '2024-01-15 10:05:00+00'),
  (1, 'paid', 'shipped', '2024-01-16 08:00:00+00'),
  (2, NULL, 'pending', '2024-02-01 14:30:00+00'),
  (2, 'pending', 'paid', '2024-02-01 14:35:00+00'),
  (3, NULL, 'pending', '2024-03-10 09:00:00+00'),
  (4, NULL, 'pending', '2024-03-20 16:45:00+00'),
  (4, 'pending', 'paid', '2024-03-20 16:50:00+00');

-- Subscriptions (SaaS)
CREATE TABLE IF NOT EXISTS subscription_plans (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL,
  price_monthly NUMERIC(10,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS subscriptions (
  id          SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES customers(id),
  plan_id     INT NOT NULL REFERENCES subscription_plans(id),
  status      TEXT NOT NULL CHECK (status IN ('active', 'cancelled', 'past_due')),
  started_at  DATE NOT NULL,
  cancelled_at DATE
);

INSERT INTO subscription_plans (name, price_monthly) VALUES
  ('Basic', 9.99), ('Pro', 29.99), ('Enterprise', 99.99)
ON CONFLICT DO NOTHING;

INSERT INTO subscriptions (customer_id, plan_id, status, started_at, cancelled_at) VALUES
  (1, 2, 'active', '2023-06-01', NULL),
  (2, 1, 'cancelled', '2023-01-15', '2024-02-28'),
  (3, 3, 'active', '2024-01-01', NULL);

-- Page views / web analytics
CREATE TABLE IF NOT EXISTS page_views (
  id          BIGSERIAL PRIMARY KEY,
  session_id  UUID NOT NULL,
  user_id     INT,
  path        TEXT NOT NULL,
  referrer    TEXT,
  viewed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO page_views (session_id, user_id, path, referrer, viewed_at) VALUES
  ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 1, '/', NULL, '2024-06-01 09:00:00+00'),
  ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 1, '/products', '/', '2024-06-01 09:01:00+00'),
  ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 1, '/checkout', '/products', '2024-06-01 09:05:00+00'),
  ('b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a12', 2, '/', 'google.com', '2024-06-01 10:00:00+00'),
  ('b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a12', 2, '/products', '/', '2024-06-01 10:02:00+00'),
  ('c2eebc99-9c0b-4ef8-bb6d-6bb9bd380a13', NULL, '/', NULL, '2024-06-02 11:00:00+00');

-- Support tickets
CREATE TABLE IF NOT EXISTS support_tickets (
  id            SERIAL PRIMARY KEY,
  customer_id   INT REFERENCES customers(id),
  subject       TEXT NOT NULL,
  priority      TEXT CHECK (priority IN ('low', 'medium', 'high', 'critical')),
  status        TEXT DEFAULT 'open' CHECK (status IN ('open', 'pending', 'resolved', 'closed')),
  created_at    TIMESTAMPTZ DEFAULT now(),
  resolved_at   TIMESTAMPTZ,
  agent_id      INT REFERENCES employees(id)
);

INSERT INTO support_tickets (customer_id, subject, priority, status, created_at, resolved_at, agent_id) VALUES
  (1, 'Late delivery', 'high', 'resolved', '2024-05-01', '2024-05-03', 5),
  (1, 'Invoice question', 'low', 'closed', '2024-05-10', '2024-05-11', 5),
  (2, 'Product defect', 'critical', 'open', '2024-06-15', NULL, NULL),
  (3, 'Refund request', 'medium', 'pending', '2024-06-18', NULL, 5);

-- Product co-purchase (market basket)
CREATE TABLE IF NOT EXISTS product_pairs AS
SELECT oi1.product_id AS product_a, oi2.product_id AS product_b, COUNT(*) AS pair_count
FROM order_items oi1
JOIN order_items oi2 ON oi1.order_id = oi2.order_id AND oi1.product_id < oi2.product_id
GROUP BY 1, 2;

-- Attendance / time tracking
CREATE TABLE IF NOT EXISTS attendance (
  id          SERIAL PRIMARY KEY,
  employee_id INT NOT NULL REFERENCES employees(id),
  work_date   DATE NOT NULL,
  hours       NUMERIC(4,2) NOT NULL CHECK (hours >= 0 AND hours <= 24),
  UNIQUE (employee_id, work_date)
);

INSERT INTO attendance (employee_id, work_date, hours) VALUES
  (1, '2024-06-03', 8), (1, '2024-06-04', 8), (1, '2024-06-05', 10),
  (2, '2024-06-03', 8), (2, '2024-06-04', 4), (2, '2024-06-05', 8),
  (3, '2024-06-03', 8), (3, '2024-06-04', 8), (3, '2024-06-05', 8);

-- Multi-tenant example (for RLS scenarios)
CREATE TABLE IF NOT EXISTS tenant_documents (
  id          SERIAL PRIMARY KEY,
  tenant_id   INT NOT NULL,
  title       TEXT NOT NULL,
  body        TEXT,
  created_by  INT
);

INSERT INTO tenant_documents (tenant_id, title, body, created_by) VALUES
  (1, 'Tenant 1 Contract', 'Terms...', 1),
  (1, 'Tenant 1 Report', 'Q1 results', 2),
  (2, 'Tenant 2 Contract', 'Terms...', 3);
