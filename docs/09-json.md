# 9. JSON & JSONB

PostgreSQL has first-class JSON support. **Use JSONB** for almost all application workloads.

## Creating JSON Values

```sql
SELECT '{"name": "Alice", "age": 30}'::jsonb;
SELECT jsonb_build_object('name', 'Alice', 'dept_id', 1);
SELECT jsonb_build_array(1, 2, 'three');
SELECT to_jsonb(ref.employees.*) FROM ref.employees LIMIT 1;
SELECT row_to_json(e) FROM ref.employees e LIMIT 1;
```

---

## Operators

| Operator | Description |
|----------|-------------|
| `->` | Get JSON object field (returns JSON) |
| `->>` | Get JSON object field as text |
| `#>` | Path as array (JSON result) |
| `#>>` | Path as text |
| `@>` | Left contains right |
| `<@` | Left contained in right |
| `?` | Key/string exists (top level) |
| `?|` | Any key exists |
| `?&` | All keys exist |
| `\|\|` | Concatenate / merge |
| `-` | Delete key or path |
| `#-` | Delete at path |

```sql
SELECT metadata -> 'warranty_years' FROM ref.products;
SELECT metadata ->> 'warranty_years' FROM ref.products;
SELECT payload #>> '{order_id}' FROM ref.events WHERE event_type = 'purchase';

-- Containment (GIN-indexable)
SELECT * FROM ref.products WHERE metadata @> '{"warranty_years": 2}';
SELECT * FROM ref.events WHERE payload ? 'order_id';
```

---

## jsonpath `(PG 12+)`

SQL/JSON path language.

```sql
SELECT jsonb_path_query(
  '{"items": [{"id": 1, "qty": 2}, {"id": 2, "qty": 5}]}',
  '$.items[*].qty'
);

SELECT jsonb_path_query_array(payload, '$.tags[*]') FROM ref.events;

-- Filter
SELECT * FROM ref.events
WHERE jsonb_path_exists(payload, '$.amount ? (@ > 50)');
```

---

## Modifying JSONB

```sql
UPDATE ref.products
SET metadata = metadata || '{"color": "blue"}'::jsonb
WHERE sku = 'WDG-001';

UPDATE ref.products
SET metadata = jsonb_set(metadata, '{warranty_years}', '3')
WHERE sku = 'WDG-001';

UPDATE ref.products
SET metadata = metadata - 'color';

-- Deep merge
UPDATE ref.products
SET metadata = metadata || '{"specs": {"weight_kg": 0.5}}'::jsonb;
```

---

## Aggregation

```sql
SELECT customer_id,
       jsonb_agg(jsonb_build_object(
         'order_id', o.id,
         'total', o.total
       ) ORDER BY o.created_at) AS order_history
FROM ref.orders o
GROUP BY customer_id;

SELECT jsonb_object_agg(key, value) FROM (
  SELECT department_id::text AS key, COUNT(*)::text AS value
  FROM ref.employees GROUP BY department_id
) t;
```

---

## Indexing JSONB

### GIN default ops — containment, existence

```sql
CREATE INDEX products_metadata_gin ON ref.products USING GIN (metadata);
-- Supports @>, ?, ?|, ?&
```

### jsonb_path_ops — smaller index, path/containment only

```sql
CREATE INDEX events_payload_path ON ref.events USING GIN (payload jsonb_path_ops);
```

### Expression index on specific key

```sql
CREATE INDEX products_warranty ON ref.products ((metadata -> 'warranty_years'));
SELECT * FROM ref.products WHERE (metadata -> 'warranty_years')::int > 1;
```

---

## JSON Table Functions

```sql
-- Expand array elements to rows
SELECT e.id, item
FROM ref.events e,
     jsonb_array_elements(e.payload -> 'items') AS item
WHERE e.payload ? 'items';

-- jsonb_to_recordset — rows from JSON array
SELECT *
FROM jsonb_to_recordset('[{"a":1,"b":"x"},{"a":2,"b":"y"}]'::jsonb)
  AS t(a int, b text);
```

---

## Performance Tips

💡 Store only variable/schema-less attributes in JSONB; keep queryable columns as regular columns.

💡 `@>` containment with GIN is fast; `->>` text extraction without index scans full table.

💡 Avoid `jsonb_each` in WHERE on large tables without filtering first.

---

## Next

→ [10. Full-Text Search](./10-full-text-search.md)
