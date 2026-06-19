# E-commerce & Sales Scenarios

## Monthly Revenue by Status

**Question:** What revenue did we recognize each month, broken down by order status?

```sql
SELECT date_trunc('month', created_at) AS month,
       status,
       COUNT(*) AS order_count,
       SUM(total) AS revenue
FROM ref.orders
WHERE status IN ('paid', 'shipped')
GROUP BY 1, 2
ORDER BY 1, 2;
```

---

## Top-N Products by Revenue

**Question:** Which 3 products generated the most revenue?

```sql
SELECT p.name, SUM(oi.quantity * oi.unit_price) AS revenue
FROM ref.order_items oi
JOIN ref.products p ON p.id = oi.product_id
JOIN ref.orders o ON o.id = oi.order_id
WHERE o.status IN ('paid', 'shipped')
GROUP BY p.id, p.name
ORDER BY revenue DESC
LIMIT 3;
```

---

## Top Product Per Customer

**Question:** What is each customer's favorite product (most purchased quantity)?

```sql
SELECT DISTINCT ON (o.customer_id)
       c.name AS customer,
       p.name AS top_product,
       SUM(oi.quantity) AS total_qty
FROM ref.customers c
JOIN ref.orders o ON o.customer_id = c.id
JOIN ref.order_items oi ON oi.order_id = o.id
JOIN ref.products p ON p.id = oi.product_id
GROUP BY c.id, c.name, p.id, p.name, o.customer_id
ORDER BY o.customer_id, total_qty DESC;
```

---

## Average Order Value (AOV)

**Question:** What is our average order value overall and per customer?

```sql
-- Overall AOV
SELECT AVG(total) AS aov FROM ref.orders WHERE status IN ('paid', 'shipped');

-- Per customer
SELECT c.name,
       COUNT(o.id) AS orders,
       ROUND(AVG(o.total), 2) AS aov,
       SUM(o.total) AS lifetime_value
FROM ref.customers c
LEFT JOIN ref.orders o ON o.customer_id = c.id AND o.status IN ('paid', 'shipped')
GROUP BY c.id, c.name
ORDER BY lifetime_value DESC NULLS LAST;
```

---

## Conversion Funnel (Order Status)

**Question:** How many orders reached each stage, and where do we drop off?

```sql
WITH funnel AS (
  SELECT
    COUNT(*) FILTER (WHERE TRUE) AS created,
    COUNT(*) FILTER (WHERE status IN ('paid', 'shipped')) AS paid,
    COUNT(*) FILTER (WHERE status = 'shipped') AS shipped
  FROM ref.orders
)
SELECT created,
       paid,
       ROUND(100.0 * paid / NULLIF(created, 0), 1) AS paid_pct,
       shipped,
       ROUND(100.0 * shipped / NULLIF(paid, 0), 1) AS shipped_pct
FROM funnel;
```

### Time-to-convert from status history

```sql
SELECT o.id,
       MIN(h.changed_at) FILTER (WHERE h.new_status = 'pending') AS created,
       MIN(h.changed_at) FILTER (WHERE h.new_status = 'paid') AS paid_at,
       EXTRACT(EPOCH FROM (
         MIN(h.changed_at) FILTER (WHERE h.new_status = 'paid') -
         MIN(h.changed_at) FILTER (WHERE h.new_status = 'pending')
       )) / 60 AS minutes_to_pay
FROM ref.orders o
JOIN ref.order_status_history h ON h.order_id = o.id
GROUP BY o.id;
```

---

## Market Basket / Frequently Bought Together

**Question:** Which products are often purchased in the same order?

```sql
SELECT pa.name AS product_a,
       pb.name AS product_b,
       COUNT(*) AS times_together
FROM ref.order_items oi1
JOIN ref.order_items oi2
  ON oi1.order_id = oi2.order_id AND oi1.product_id < oi2.product_id
JOIN ref.products pa ON pa.id = oi1.product_id
JOIN ref.products pb ON pb.id = oi2.product_id
GROUP BY pa.name, pb.name
ORDER BY times_together DESC;
```

### Recommendations for a product

```sql
-- Products bought with product_id = 1
SELECT p.name, COUNT(*) AS co_purchase_count
FROM ref.order_items target
JOIN ref.order_items other ON other.order_id = target.order_id
  AND other.product_id <> target.product_id
JOIN ref.products p ON p.id = other.product_id
WHERE target.product_id = 1
GROUP BY p.id, p.name
ORDER BY co_purchase_count DESC
LIMIT 5;
```

---

## Low Stock Alert

**Question:** Which products need reordering (available qty < 20)?

```sql
SELECT p.sku, p.name,
       i.quantity AS on_hand,
       i.reserved,
       i.quantity - i.reserved AS available
FROM ref.inventory i
JOIN ref.products p ON p.id = i.product_id
WHERE i.quantity - i.reserved < 20
ORDER BY available;
```

---

## Revenue by Country

**Question:** Which countries drive the most revenue?

```sql
SELECT c.country,
       COUNT(DISTINCT c.id) AS customers,
       COUNT(o.id) AS orders,
       SUM(o.total) AS revenue
FROM ref.customers c
JOIN ref.orders o ON o.customer_id = c.id
WHERE o.status IN ('paid', 'shipped')
GROUP BY c.country
ORDER BY revenue DESC;
```

---

## Customers With No Orders (Lead List)

**Question:** Who signed up but never ordered?

```sql
SELECT c.*
FROM ref.customers c
LEFT JOIN ref.orders o ON o.customer_id = c.id
WHERE o.id IS NULL;
```

---

## Repeat Purchase Rate

**Question:** What percentage of customers ordered more than once?

```sql
WITH customer_orders AS (
  SELECT customer_id, COUNT(*) AS order_count
  FROM ref.orders
  WHERE status IN ('paid', 'shipped')
  GROUP BY customer_id
)
SELECT
  COUNT(*) AS total_customers,
  COUNT(*) FILTER (WHERE order_count > 1) AS repeat_customers,
  ROUND(100.0 * COUNT(*) FILTER (WHERE order_count > 1) / COUNT(*), 1) AS repeat_rate_pct
FROM customer_orders;
```

---

## Cart Abandonment Proxy (Pending Orders)

**Question:** How many orders are stuck in pending, and for how long?

```sql
SELECT id, customer_id, total,
       created_at,
       now() - created_at AS age
FROM ref.orders
WHERE status = 'pending'
ORDER BY age DESC;
```

---

## Discount Impact Analysis

**Question:** If we stored list vs sale price, what's the discount % per order?

```sql
-- Assuming unit_price reflects actual charged price vs products.price as list
SELECT o.id,
       SUM(oi.quantity * p.price) AS list_total,
       SUM(oi.quantity * oi.unit_price) AS charged_total,
       ROUND(100 * (1 - SUM(oi.quantity * oi.unit_price) / NULLIF(SUM(oi.quantity * p.price), 0)), 1) AS discount_pct
FROM ref.orders o
JOIN ref.order_items oi ON oi.order_id = o.id
JOIN ref.products p ON p.id = oi.product_id
GROUP BY o.id;
```

---

## Seasonal Product Tags

**Question:** Count products by tag.

```sql
SELECT tag, COUNT(*) AS product_count
FROM ref.products, unnest(tags) AS tag
GROUP BY tag
ORDER BY product_count DESC;
```

---

## Orders With Line Item Detail (Invoice View)

**Question:** Generate a line-item invoice for order #1.

```sql
SELECT o.id AS order_id,
       c.name AS customer,
       p.name AS product,
       oi.quantity,
       oi.unit_price,
       oi.quantity * oi.unit_price AS line_total
FROM ref.orders o
JOIN ref.customers c ON c.id = o.customer_id
JOIN ref.order_items oi ON oi.order_id = o.id
JOIN ref.products p ON p.id = oi.product_id
WHERE o.id = 1;
```

---

## New vs Returning Customer Revenue

**Question:** Split revenue between first-time and repeat buyers per month.

```sql
WITH first_order AS (
  SELECT customer_id, MIN(created_at) AS first_at
  FROM ref.orders
  WHERE status IN ('paid', 'shipped')
  GROUP BY customer_id
)
SELECT date_trunc('month', o.created_at) AS month,
       SUM(o.total) FILTER (WHERE o.created_at = fo.first_at) AS new_customer_revenue,
       SUM(o.total) FILTER (WHERE o.created_at > fo.first_at) AS returning_revenue
FROM ref.orders o
JOIN first_order fo ON fo.customer_id = o.customer_id
WHERE o.status IN ('paid', 'shipped')
GROUP BY 1
ORDER BY 1;
```
