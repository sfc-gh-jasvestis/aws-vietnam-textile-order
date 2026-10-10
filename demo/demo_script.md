# Garment Buyer Order Risk

**Vietnam - Garment and textile manufacturing**
Use case: On-time shipment and late-shipment risk for buyer purchase orders at fictional garment factories

> A fictional network of 40 Vietnam garment factories, from Hanoi, Nam Dinh and Thai Binh in the north through Da Nang to Ho Chi Minh City, Binh Duong, Dong Nai and Long An in the south, tracked from WIP status review to ex-factory shipment: dynamic tables for on-time shipment, a holdout-evaluated late-shipment classifier, an order shipment forecast and grounded AI answers. Order risk flags are demo signals, not buyer compliance or audit verdicts.

## Why Snowflake

- **Dynamic tables** reconcile buyer-order shipments, on-time shipment, order risk flags, confirmed late shipments and WIP review completion from RAW factory data, with checks in `run_core.py`
- **Late-shipment classification** gives a holdout-evaluated next-7-day probability per factory
- **Order shipment forecast** projects 14 days of network-wide shipments with prediction intervals, for container booking and port cut-off planning
- **Grounded AI**: the Cortex Agent (Analyst over a semantic view, plus Search over SOPs) shows its SQL and SOP citations
- **Live order status**: a native order-status simulator (Snowflake only) or an Amazon Data Firehose stream, S3 and Snowpipe (AWS build), then an alert and email

## What is built

| | |
|---|---|
| Dimension table | `RAW.FACTORIES` (40 rows) |
| Fact table | `RAW.FACTORY_DAILY` (3,600 factory-days, 90 days) |
| Curated layer | `CURATED.KPI_SUMMARY`, `PERFORMANCE_SUMMARY`, `SIGNAL_SUMMARY`, `TREND_ANALYSIS` |
| ML | `ML.LATE_RISK_SCORES`, `ML.LATE_RISK_HOLDOUT_METRICS`, `ML.SHIPMENT_FORECAST`, `ML.WIP_GAP_ANOMALIES` |

Cities and provinces: Ho Chi Minh City, Binh Duong, Dong Nai, Long An, Hanoi, Nam Dinh, Thai Binh, Da Nang.
Product categories: Knit tops factory, Woven shirts factory, Denim factory, Outerwear factory, Sportswear factory.

## KPI cards (live from `CURATED.KPI_SUMMARY`; no fallback values)

| Card | Value from the seeded data |
|---|---|
| On-Time Shipment (pieces) | 88.2% |
| Order Shipments | 16,919 |
| Pieces Shipped (millions) | 159 |
| Order Risk Flags | 527 |
| Confirmed Late Shipments | 158 |
| Flag Precision | 30.0% |
| Lots Held at Final Inspection | 46 |
| WIP Review Completion | 72.1% |
| Factories Monitored | 40 |
| PP Sample Approval Coverage | 74.7% |
| Approvals Pending | 128 |
| Active Styles | 1,802 |

Values are synthetic. A rebuild reproduces them because the data is HASH-seeded; dates are relative to the build day.

## Demo flow

1. Executive Cockpit: KPIs, daily buyer-order shipments against order risk flags, flags and confirmed late shipments by order-risk signal, factory table
2. Predictive: holdout metrics, risk bands, 14-day order shipment forecast, WIP gap anomalies
3. WIP Reviews: WIP review completion, PP sample approval coverage and pending approvals, review completion against confirmed late shipments, then generate the action memo
4. Live Order Status: run `CALL APP.SIMULATE_ORDERS(20)` (Snowflake only) or `python aws/publish_orders.py --count 20` (AWS build). Then run `EXECUTE ALERT APP.LIVE_ORDER_ALERT` and show the alert log and email.
5. Ask AI: the Cortex Agent answers metric questions through the semantic view and cites SOPs from Cortex Search. The SQL is shown.
6. QuickSight (AWS build): the same Snowflake tables through DIRECT_QUERY
7. Architecture: both builds side by side

## Talking points

- About three order risk flags in ten are confirmed as late shipments (30.0%). The rest are false positives, and chasing them is where the merchandising team loses its week.
- "Line efficiency below plan" produces the most confirmed late shipments (32 of 98 flags), ahead of "Trims not in-house" (28) and "Wash recipe rework" (23). Grid power curtailment flags hit every factory in an area at once and are never confirmed.
- FAC-0027 (Long An outerwear factory) has the most confirmed late shipments (16), and outerwear factories have the lowest on-time shipment (80.9%).
- The risk model is evaluated on a time-based holdout: precision 0.57 and recall 0.31 at 0.5, against a 0.23 base rate. Use it to order factory calls, not as a verdict. Forecast and anomaly figures can shift slightly with the build day.
- Grid power curtailment days are excluded from model training, because the factory did not cause them.

## Business impact

Use only the sourced references in `README.md` (Business Impact).
