# E-commerce Sales Analysis | MySQL + Power BI

End-to-end analytics project on an e-commerce dataset (20,000 orders, 38,734 order lines, 5,000 customers, 600 products, Jan 2023 to Oct 2026). Data was cleaned and explored in **MySQL**, then turned into a 3-page **Power BI** dashboard.

## Tools
- **MySQL:** data cleaning, flag columns, views, joins, aggregations, window functions (20 business queries)
- **Power BI:** data model, DAX measures, interactive dashboard with slicers

## Dashboard

### 1. Executive Overview
![Executive Overview](screenshots/page1_overview.png)

### 2. Product & Customer
![Product & Customer](screenshots/page2_product_customer.png)

### 3. Operations & Returns
![Operations & Returns](screenshots/page3_operations.png)

## Revenue definition
In the dashboard, **net revenue = Delivered, non-returned order lines**, excluding lines flagged as data-quality issues. The same definition is used for every KPI and chart.

## Headline numbers
| Metric | Value |
|---|---|
| Net revenue | ~INR 42.2 Cr (422M) |
| Gross profit | ~INR 11.0 Cr (110M), 26.1% margin |
| Orders | 14,008 |
| Average order value | ~INR 30K |
| Repeat customers | 81.7% |
| Customers who never ordered | 110 |
| Return rate | 7.9% (about 2,500 returned items, INR 41.8M refunded) |
| Avg delivery time | 5.49 days |

## Key insights
- **Channels:** Mobile App (49.5%) and Website (36.4%) bring about 86% of revenue. Marketplace is 9.0% and Call Center 5.1%.
- **Growth:** monthly revenue climbs steadily through 2024 to 2026. Early 2023 volumes are very small, so growth % is shown for 2024-25.
- **Products:** Smart Watches, Headphones and Mobiles lead category revenue.
- **Customers:** 81.7% of buying customers order more than once. Bronze tier contributes just over half of revenue because it is the largest group.
- **Returns:** 7.9% of delivered and returned lines come back. Reasons are spread almost evenly (Not as described, Size issue and Changed mind are the top three), so no single fix removes most returns.
- **Delivery:** all six couriers average between 5.4 and 5.6 days, so courier choice makes little difference to delivery time.

## Data quality findings
- **4,494 order lines (~11.6%)** have an order date before the product's launch date. Flagged and excluded from revenue.
- **46 returns** are dated after 28-Oct-2026 (beyond the data window). Flagged and excluded.
- Oct 2026 is a partial month (data ends 15-Oct-2026).

## Data model
`clean_order_items` is the fact table, linked to `products` (then `categories`, `brands`, `suppliers`), `clean_customers`, `clean_orders`, `returns` and a `Date` table. Key DAX measures: Net Revenue, Gross Profit, Profit Margin %, Orders, AOV, MoM Growth %, Return Rate %, Repeat Customer %, Avg Delivery Days.

## SQL notes
`sql/02_cleaning_and_analysis.sql` builds `clean_order_items`, `clean_orders`, `clean_customers` and the `v_rev` view (delivered, non-returned), then answers 20 business questions. Q1-Q6 are exploratory queries on booked sales, so their totals are higher than the dashboard's net revenue, which excludes cancelled and returned lines.

## Repository structure
```
sql/          dataset and cleaning + analysis queries
powerbi/      Power BI file (.pbix)
screenshots/  dashboard page images
docs/         quick HTML preview of main KPIs and charts
```

## How to run
1. Run `sql/01_ecommerce_dataset.sql` in MySQL (creates and loads the `ecommerce` database).
2. Run `sql/02_cleaning_and_analysis.sql` for the clean tables, view and queries.
3. Open `powerbi/ecommerce_sales_dashboard.pbix` and point the MySQL connection to your server.
