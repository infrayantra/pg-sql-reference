-- Sample schema for PostgreSQL SQL Reference examples
-- Run: psql -f examples/setup.sql

DROP SCHEMA IF EXISTS ref CASCADE;
CREATE SCHEMA ref;
SET search_path TO ref, public;

CREATE TABLE departments (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  budget      NUMERIC(12,2)
);

CREATE TABLE employees (
  id              SERIAL PRIMARY KEY,
  name            TEXT NOT NULL,
  email           TEXT UNIQUE,
  department_id   INT REFERENCES departments(id) ON DELETE SET NULL,
  manager_id      INT REFERENCES employees(id) ON DELETE SET NULL,
  salary          NUMERIC(10,2) CHECK (salary > 0),
  hired_at        DATE NOT NULL DEFAULT CURRENT_DATE,
  is_active       BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE customers (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL,
  email       TEXT,
  country     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE products (
  id          SERIAL PRIMARY KEY,
  sku         TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  price       NUMERIC(10,2) NOT NULL CHECK (price >= 0),
  tags        TEXT[],
  metadata    JSONB DEFAULT '{}'
);

CREATE TABLE orders (
  id            SERIAL PRIMARY KEY,
  customer_id   INT NOT NULL REFERENCES customers(id),
  status        TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'paid', 'shipped', 'cancelled')),
  total         NUMERIC(10,2),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE order_items (
  id          SERIAL PRIMARY KEY,
  order_id    INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id  INT NOT NULL REFERENCES products(id),
  quantity    INT NOT NULL CHECK (quantity > 0),
  unit_price  NUMERIC(10,2) NOT NULL
);

CREATE TABLE events (
  id          BIGSERIAL PRIMARY KEY,
  user_id     INT,
  event_type  TEXT NOT NULL,
  payload     JSONB,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE articles (
  id      SERIAL PRIMARY KEY,
  title   TEXT NOT NULL,
  body    TEXT,
  tsv     TSVECTOR
);

-- Seed data
INSERT INTO departments (name, budget) VALUES
  ('Engineering', 500000),
  ('Sales', 300000),
  ('HR', 150000);

INSERT INTO employees (name, email, department_id, manager_id, salary, hired_at) VALUES
  ('Alice Chen', 'alice@co.com', 1, NULL, 120000, '2019-03-15'),
  ('Bob Smith', 'bob@co.com', 1, 1, 95000, '2020-06-01'),
  ('Carol Diaz', 'carol@co.com', 1, 1, 88000, '2021-01-10'),
  ('Dave Wilson', 'dave@co.com', 2, NULL, 110000, '2018-11-20'),
  ('Eve Park', 'eve@co.com', 2, 4, 75000, '2022-04-05'),
  ('Frank Lee', 'frank@co.com', 3, NULL, 85000, '2017-09-01');

INSERT INTO customers (name, email, country) VALUES
  ('Acme Corp', 'buyer@acme.com', 'US'),
  ('Globex', 'orders@globex.com', 'UK'),
  ('Initech', 'procurement@initech.com', 'US');

INSERT INTO products (sku, name, price, tags, metadata) VALUES
  ('WDG-001', 'Widget Pro', 29.99, ARRAY['hardware', 'pro'], '{"warranty_years": 2}'),
  ('WDG-002', 'Widget Lite', 9.99, ARRAY['hardware'], '{"warranty_years": 1}'),
  ('SVC-001', 'Support Plan', 99.00, ARRAY['service', 'subscription'], '{"tier": "gold"}');

INSERT INTO orders (customer_id, status, total, created_at) VALUES
  (1, 'paid', 59.98, '2024-01-15 10:00:00+00'),
  (1, 'shipped', 99.00, '2024-02-01 14:30:00+00'),
  (2, 'pending', 29.99, '2024-03-10 09:00:00+00'),
  (3, 'paid', 39.98, '2024-03-20 16:45:00+00');

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
  (1, 1, 2, 29.99),
  (2, 3, 1, 99.00),
  (3, 1, 1, 29.99),
  (4, 2, 4, 9.99);

INSERT INTO events (user_id, event_type, payload) VALUES
  (1, 'login', '{"ip": "10.0.0.1"}'),
  (1, 'purchase', '{"order_id": 1, "amount": 59.98}'),
  (2, 'login', '{"ip": "192.168.1.5"}');

INSERT INTO articles (title, body) VALUES
  ('PostgreSQL Indexing', 'B-tree and GIN indexes speed up queries dramatically.'),
  ('Window Functions Guide', 'OVER clause enables ranking and running totals.');

UPDATE articles SET tsv = to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, ''));