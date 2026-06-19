# 10. Full-Text Search (FTS)

PostgreSQL includes powerful built-in full-text search without external engines like Elasticsearch (though those scale further for huge corpora).

## Core Types

| Type | Role |
|------|------|
| `tsvector` | Normalized document — lexemes + positions |
| `tsquery` | Search query — lexemes with operators |

```sql
SELECT to_tsvector('english', 'The PostgreSQL database supports full text search');
-- 'databas':3 'full':6 'postgresql':2 'search':8 'text':7

SELECT to_tsquery('english', 'postgresql & search');
SELECT plainto_tsquery('english', 'postgresql search');  -- AND between terms
SELECT phraseto_tsquery('english', 'full text search');    -- phrase
SELECT websearch_to_tsquery('english', '"full text" OR index -stopword');  -- PG 11+
```

---

## Matching & Ranking

```sql
SELECT title,
       ts_rank(tsv, query) AS rank,
       ts_headline('english', body, query, 'MaxWords=20') AS snippet
FROM ref.articles, plainto_tsquery('english', 'index window') query
WHERE tsv @@ query
ORDER BY rank DESC;
```

### Ranking variants

```sql
ts_rank(tsv, query)                          -- term frequency
ts_rank_cd(tsv, query)                       -- cover density (proximity)
ts_rank(tsv, query, normalization := 32)     -- rank / document length
```

---

## Maintaining tsvector

### Generated column `(PG 12+)`

```sql
ALTER TABLE ref.articles
  ADD COLUMN tsv tsvector GENERATED ALWAYS AS (
    to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, ''))
  ) STORED;

CREATE INDEX articles_tsv_gin ON ref.articles USING GIN (tsv);
```

### Trigger-based (pre-PG 12 or custom logic)

```sql
CREATE FUNCTION ref.articles_tsv_trigger() RETURNS trigger AS $$
BEGIN
  NEW.tsv := to_tsvector('english', coalesce(NEW.title, '') || ' ' || coalesce(NEW.body, ''));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tsvector_update
  BEFORE INSERT OR UPDATE ON ref.articles
  FOR EACH ROW EXECUTE FUNCTION ref.articles_tsv_trigger();
```

---

## Query Operators

| Operator | Meaning |
|----------|---------|
| `&` | AND |
| `\|` | OR |
| `!` | NOT |
| `<->` | Followed by (phrase in tsquery) |
| `@@` | Match predicate |

```sql
SELECT * FROM ref.articles
WHERE tsv @@ to_tsquery('english', 'postgresql & (index | window)');

-- Prefix search
WHERE tsv @@ to_tsquery('english', 'post:*');
```

---

## Dictionaries & Configuration

```sql
SELECT cfgname FROM pg_ts_config;
-- simple, english, french, ...

SELECT to_tsvector('english', 'running runs ran');  -- stems to 'run'
SELECT to_tsvector('simple', 'running runs ran');   -- no stemming

ALTER TEXT SEARCH CONFIGURATION english (ALTER MAPPING FOR asciiword WITH english_stem);
```

Custom dictionary / stop words via extensions or custom configs.

---

## Weighted Vectors

```sql
SETWEIGHT(to_tsvector('english', title), 'A') ||
SETWEIGHT(to_tsvector('english', body), 'B')
```

`ts_rank` weights A > B > C > D.

---

## Multi-language

Store language per row; use in trigger:

```sql
to_tsvector(CASE lang WHEN 'fr' THEN 'french' ELSE 'english' END, content)
```

Or separate `tsv` columns per language.

---

## vs External Search

| Use PostgreSQL FTS | Consider Elasticsearch/OpenSearch |
|--------------------|-----------------------------------|
| Moderate document count | Billions of docs, heavy analytics |
| Tight transactional coupling | Dedicated search cluster |
| Simple relevance needs | Advanced scoring, faceting at scale |

---

## Next

→ [11. Indexes & Query Planning](./11-indexes-performance.md)
