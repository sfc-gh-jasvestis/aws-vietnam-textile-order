# Order Management

**Vietnam - Textile & Garment**
Use case: Order Management

> Order Management for Vietnam - ML.FORECAST and Dynamic Tables power real-time order management intelligence for textile & garment in Hanoi & Ho Chi Minh City.

## Why Snowflake

Snowflake delivers order management intelligence for Vietnamese textile & garment - Dynamic Tables maintain real-time dashboards, ML.FORECAST projects key metrics, and Cortex AI generates recommendations

- **ML.FORECAST for order management** - Only demo for Vietnamese textile & garment
- **ML.ANOMALY_DETECTION early warning** - Detects deviations before impact
- **AI recommendations** - Cortex AI actionable guidance
- **Vietnamese context** - Local names, VND economics

## What is deployed

| | |
|---|---|
| Database | `VIETNAM_TEXTILE_ORDER` |
| Service | `VIETNAM_TEXTILE_ORDER_APP` |
| Compute pool | `SEA_DEMOS_VIETNAM_POOL` |
| Dimension table | `RAW.FACTORIES` (20 rows) |
| Fact table | `RAW.CUSTOMER_ORDERS` (250,000 rows, 90 days) |
| Curated layer | `CURATED.PERFORMANCE_SUMMARY`, `CURATED.TREND_ANALYSIS`, `CURATED.KPI_SUMMARY` |
| Currency | VND (₫) |

Regions in play: Ho Chi Minh City, Hanoi, Binh Duong, Dong Nai, Can Tho
Segments: EU Export, US Export, Japan Export, Domestic

Dynamic tables are created suspended and refreshed on demand:

```bash
./refresh_demo_data.sh VIETNAM_TEXTILE_ORDER
```

## KPI cards

Every card below is served live from `CURATED.KPI_SUMMARY`. The app keeps the
original literal as a fallback, so it still renders if Snowflake is unreachable.

| Card | Value | Backed by |
|---|---|---|
| Order Book Value | `₫4.8T` | total across Factories |
| On-Time Delivery | `91%` | average per event |
| Active Orders | `1,247` | total across Factories |
| Customers | `87` | average per event |
| Avg Lead Time | `42 days` | average per event |
| Fill Rate | `94%` | average per event |
| Cancellation Rate | `2.4%` | average per event |


## Demo flow

1. Overview
2. Analytics
3. AI Intelligence
4. Ask AI
5. Architecture

## Talking points

- **100K operations** - tracked in Hanoi & Ho Chi Minh City
- **500K metrics** - time-series data points
- **5K assets** - monitored
- **100 docs** - searchable

## Business impact

- Vietnam textile & garment sector growing rapidly (GSO Vietnam)
- AI improves outcomes 15-30% (McKinsey)
- Vietnam FDI strong in this sector (MPI)
- Real-time analytics reduces response 60-80% (Gartner)

---
Generated from `generator/demo_specs/aws-vietnam-textile-order.json`. Do not hand-edit: run
`python3 generator/gen_repo_docs.py aws-vietnam-textile-order` instead.
