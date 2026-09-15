# cohort_analysis_sql

# Shopee Seller Churn Detection

Monthly SQL pipeline that identifies which seller shops churned (went from active to inactive) month-over-month on Shopee's platform-fulfillment program.

Built as part of my BI work on Shopee's SCommerce team. Leadership wanted to know which sellers were dropping off the platform or when.

**Note:** table names, schema names, and the region code have been redacted/genericized to remove anything specific to Shopee's internal systems. The query logic itself is unchanged.

## What it does

1. **Defines "active shop"** by cross-checking two signals: live inventory status (in stock, listed, sellable) *and* actual order activity that month. Using inventory data alone missed edge cases. Some shops had stale inventory flags but were still fulfilling real orders, or vice versa.
2. **Builds a month-over-month shop universe**, tagging every shop with whether it was active this month *and* whether it was active the month before.
3. **Pulls order-level metrics** (order count, GMV, fulfillment share) per shop per month, scoped to the specific fulfillment method being tracked.
4. **Isolates churn**: the final query filters this universe down to shops that were active last month but inactive this month: the exact definition of churn used here.

## Why it's structured this way

The two-signal "active shop" definition (inventory + orders) was the key fix over a naive version that just checked inventory status. That approach was both over- and under-counting active shops. Cross-referencing against actual order activity closed that gap.

## Tech

SQL (CTEs, window functions, self-joins for month-over-month comparison). Originally run on a distributed SQL engine (Presto/Trino-style syntax).

## Files

- `sql_logic`: the full query, table/schema names genericized
