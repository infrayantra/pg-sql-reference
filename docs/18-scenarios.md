# 18. Real-World Scenarios

Practical SQL solutions for common business and engineering problems. Run `examples/setup.sql` and `examples/scenarios-setup.sql` first.

## Scenario Index

| Category | File | Scenarios |
|----------|------|-----------|
| E-commerce & Sales | [scenarios/ecommerce.md](./scenarios/ecommerce.md) | Revenue, funnel, basket analysis, inventory |
| HR & Workforce | [scenarios/hr-workforce.md](./scenarios/hr-workforce.md) | Payroll, tenure, org chart, overtime |
| Customer Analytics | [scenarios/customer-analytics.md](./scenarios/customer-analytics.md) | RFM, cohorts, retention, LTV |
| Time Series & Reporting | [scenarios/time-series.md](./scenarios/time-series.md) | Daily rollups, YoY, missing dates |
| Data Quality | [scenarios/data-quality.md](./scenarios/data-quality.md) | Duplicates, orphans, validation |
| API & Backend Patterns | [scenarios/api-backend.md](./scenarios/api-backend.md) | Pagination, search, soft delete, queues |
| SaaS & Subscriptions | [scenarios/saas.md](./scenarios/saas.md) | MRR, churn, upgrades |
| Security & Multi-Tenancy | [scenarios/security-rls.md](./scenarios/security-rls.md) | RLS, tenant isolation |
| Support & Operations | [scenarios/operations.md](./scenarios/operations.md) | SLAs, agent workload, escalations |
| Web Analytics | [scenarios/web-analytics.md](./scenarios/web-analytics.md) | Sessions, funnels, bounce rate |
| Financial | [scenarios/financial.md](./scenarios/financial.md) | Aging, reconciliation, running balance |
| Migration & ETL | [scenarios/etl-migration.md](./scenarios/etl-migration.md) | Bulk load, sync, change detection |

---

## How to Use These Scenarios

1. Each scenario states the **business question** first
2. SQL uses the `ref` schema from sample data
3. Adapt table/column names to your schema
4. Check `EXPLAIN ANALYZE` before running at scale

## Quick Scenario Lookup

| I need to… | Go to |
|------------|-------|
| Find top customers by spend | [customer-analytics § RFM](./scenarios/customer-analytics.md#rfm-segmentation) |
| Calculate month-over-month growth | [time-series § MoM](./scenarios/time-series.md#month-over-month-growth) |
| Get top 3 products per category | [ecommerce § Top-N](./scenarios/ecommerce.md#top-n-products-by-revenue) |
| Find employees who report to themselves indirectly | [hr § Org hierarchy](./scenarios/hr-workforce.md#full-org-hierarchy) |
| Paginate API results efficiently | [api-backend § Keyset](./scenarios/api-backend.md#keyset-pagination) |
| Prevent tenant A seeing tenant B data | [security § RLS](./scenarios/security-rls.md#row-level-security-for-multi-tenancy) |
| Calculate monthly recurring revenue | [saas § MRR](./scenarios/saas.md#monthly-recurring-revenue-mrr) |
| Find products frequently bought together | [ecommerce § Market basket](./scenarios/ecommerce.md#market-basket--frequently-bought-together) |
| Detect duplicate emails | [data-quality § Duplicates](./scenarios/data-quality.md#find-duplicate-emails) |
| Fill gaps in a date series chart | [time-series § Gap fill](./scenarios/time-series.md#fill-missing-dates-with-zero) |
