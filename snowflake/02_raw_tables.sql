-- Synthetic buyer-order observations for a fictional network of garment
-- factories in Vietnam. 40 factories = 8 cities or provinces x 5 product
-- categories. Nothing is seeded as a prediction. Randomness is HASH-seeded, so
-- every rebuild is reproducible: per-factory late-shipment propensity, drift
-- between weekly work-in-progress (WIP) status reviews, skipped reviews,
-- category-weighted order-risk signals, false-positive risk flags, and two
-- area-wide grid power curtailment days. Risk flags are demo signals, not buyer
-- compliance or audit verdicts.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

CREATE TABLE RAW.FACTORIES AS
WITH factories AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS FACTORY_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 40))
), draws AS (
  SELECT FACTORY_INDEX,
         MOD(ABS(HASH(FACTORY_INDEX, 'vnto-program')), 1000000) / 1e6 AS U_PROGRAM,
         MOD(ABS(HASH(FACTORY_INDEX, 'vnto-rate')), 1000000) / 1e6 AS U_RATE,
         MOD(ABS(HASH(FACTORY_INDEX, 'vnto-review')), 1000000) / 1e6 AS U_REVIEW,
         MOD(ABS(HASH(FACTORY_INDEX, 'vnto-discipline')), 1000000) / 1e6 AS U_DISCIPLINE,
         MOD(ABS(HASH(FACTORY_INDEX, 'vnto-tier')), 1000000) / 1e6 AS U_TIER,
         MOD(ABS(HASH(FACTORY_INDEX, 'vnto-size')), 1000000) / 1e6 AS U_SIZE
  FROM factories
), factories_named AS (
  SELECT *,
         -- Every city x product category combination appears exactly once.
         CASE MOD(FACTORY_INDEX, 8) WHEN 0 THEN 'Ho Chi Minh City' WHEN 1 THEN 'Binh Duong'
              WHEN 2 THEN 'Dong Nai' WHEN 3 THEN 'Long An' WHEN 4 THEN 'Hanoi'
              WHEN 5 THEN 'Nam Dinh' WHEN 6 THEN 'Thai Binh'
              ELSE 'Da Nang' END AS REGION,
         CASE FLOOR(FACTORY_INDEX / 8) WHEN 0 THEN 'Knit tops factory'
              WHEN 1 THEN 'Woven shirts factory' WHEN 2 THEN 'Denim factory'
              WHEN 3 THEN 'Outerwear factory' ELSE 'Sportswear factory' END AS CATEGORY
  FROM draws
)
SELECT 'FAC-' || LPAD(FACTORY_INDEX::VARCHAR, 4, '0') AS ID,
       REGION || ' ' || CATEGORY AS NAME,
       REGION, CATEGORY, FACTORY_INDEX,
       1 + FLOOR(U_TIER * 3) AS RISK_TIER,
       ROUND(1 + U_PROGRAM * 9, 1) AS PROGRAM_YEARS,
       ROUND(0.65 + U_SIZE * 0.7, 3) AS SIZE_FACTOR,
       -- Base daily probability of a confirmed late shipment, higher for
       -- trim-heavy and wash-dependent categories (outerwear, denim); ~15% of
       -- factories are capacity-stretched (x3).
       (0.005 + U_RATE * 0.019)
         * CASE CATEGORY WHEN 'Knit tops factory' THEN 0.6 WHEN 'Woven shirts factory' THEN 0.8
                         WHEN 'Denim factory' THEN 1.25 WHEN 'Outerwear factory' THEN 1.5
                         ELSE 0.9 END
         * IFF(U_RATE > 0.85, 3, 1) AS BASE_MISS_RATE,
       7 * (1 + FLOOR(U_REVIEW * 3)) AS REVIEW_INTERVAL_DAYS,
       0.5 + U_DISCIPLINE * 0.48 AS REVIEW_RETURN_PROB,
       -- Share of shipped pieces that typically leave after the buyer ex-factory date.
       CASE CATEGORY WHEN 'Knit tops factory' THEN 5 WHEN 'Woven shirts factory' THEN 7
                     WHEN 'Denim factory' THEN 10 WHEN 'Outerwear factory' THEN 14
                     ELSE 6 END AS BASE_LATE_PCT,
       'Active' AS STATUS
FROM factories_named;

CREATE TABLE RAW.FACTORY_DAILY AS
WITH days AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS DAY_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 90))
), outage_events AS (
  -- Two area-wide grid power curtailment days; every factory in the area gets a flag.
  SELECT * FROM VALUES (27, 'Nam Dinh'), (64, 'Binh Duong') AS o(DAY_INDEX, REGION)
), base AS (
  SELECT f.ID AS ENTITY_ID, f.FACTORY_INDEX, f.CATEGORY, f.REGION, f.PROGRAM_YEARS,
         f.SIZE_FACTOR, f.BASE_LATE_PCT,
         f.BASE_MISS_RATE, f.REVIEW_INTERVAL_DAYS, f.REVIEW_RETURN_PROB,
         d.DAY_INDEX,
         DATEADD('day', d.DAY_INDEX - 89, CURRENT_DATE()) AS EVENT_DATE,
         MOD(d.DAY_INDEX + f.FACTORY_INDEX * 3, f.REVIEW_INTERVAL_DAYS) AS DAYS_SINCE_REVIEW,
         MOD(ABS(HASH(f.ID, d.DAY_INDEX, 'vnto-late')), 1000000) / 1e6 AS U_MISS,
         MOD(ABS(HASH(f.ID, d.DAY_INDEX, 'vnto-detect')), 1000000) / 1e6 AS U_DETECT,
         MOD(ABS(HASH(f.ID, d.DAY_INDEX, 'vnto-fp')), 1000000) / 1e6 AS U_FP,
         MOD(ABS(HASH(f.ID, d.DAY_INDEX, 'vnto-signal')), 1000000) / 1e6 AS U_SIG,
         MOD(ABS(HASH(f.ID, d.DAY_INDEX, 'vnto-done')), 1000000) / 1e6 AS U_DONE,
         MOD(ABS(HASH(f.ID, d.DAY_INDEX, 'vnto-ship')), 1000000) / 1e6 AS U_SHIP,
         MOD(ABS(HASH(f.ID, d.DAY_INDEX, 'vnto-noise')), 1000000) / 1e6 AS U_NOISE,
         MOD(ABS(HASH(f.ID, d.DAY_INDEX, 'vnto-hold')), 1000000) / 1e6 AS U_HOLD,
         o.REGION IS NOT NULL AS OUTAGE_EVENT
  FROM RAW.FACTORIES f CROSS JOIN days d
  LEFT JOIN outage_events o ON o.DAY_INDEX = d.DAY_INDEX AND o.REGION = f.REGION
), reviews AS (
  SELECT *,
         IFF(DAYS_SINCE_REVIEW = 0, 1, 0) AS REVIEW_DUE,
         IFF(DAYS_SINCE_REVIEW = 0 AND U_DONE < REVIEW_RETURN_PROB, 1, 0) AS REVIEW_DONE,
         -- Schedule drift builds between WIP status reviews; weak follow-up carries it over.
         DAYS_SINCE_REVIEW / REVIEW_INTERVAL_DAYS + (1 - REVIEW_RETURN_PROB) AS DRIFT
  FROM base
), activity AS (
  SELECT *,
         CASE WHEN U_MISS < LEAST(0.5, BASE_MISS_RATE * (0.4 + 1.6 * DRIFT) * (1 + 1 / (1 + PROGRAM_YEARS))) / 4 THEN 2
              WHEN U_MISS < LEAST(0.5, BASE_MISS_RATE * (0.4 + 1.6 * DRIFT) * (1 + 1 / (1 + PROGRAM_YEARS))) THEN 1
              ELSE 0 END AS MISS_COUNT
  FROM reviews
), checks AS (
  SELECT *,
         -- Shipment booking checks confirm about 78% of late shipments; the rest go unnoticed.
         IFF(OUTAGE_EVENT, 0, IFF(U_DETECT < 0.78, MISS_COUNT, 0)) AS CONFIRMED_COUNT,
         -- False-positive flags (order still ships on time): higher where WIP data is thinner.
         IFF(OUTAGE_EVENT, 1, IFF(U_FP < CASE CATEGORY WHEN 'Outerwear factory' THEN 0.14
                                              WHEN 'Denim factory' THEN 0.13
                                              WHEN 'Sportswear factory' THEN 0.10
                                              WHEN 'Woven shirts factory' THEN 0.08 ELSE 0.07 END, 1, 0)) AS FALSE_POSITIVE_COUNT
  FROM activity
), measured AS (
  SELECT *,
         CONFIRMED_COUNT + FALSE_POSITIVE_COUNT AS FLAG_COUNT,
         ROUND(CASE CATEGORY WHEN 'Knit tops factory' THEN 6 WHEN 'Woven shirts factory' THEN 5
                             WHEN 'Denim factory' THEN 4 WHEN 'Outerwear factory' THEN 3 ELSE 5 END
               * SIZE_FACTOR * (0.7 + 0.6 * U_SHIP)) AS SHIPMENT_COUNT,
         -- Thousand garment pieces per buyer-order shipment.
         CASE CATEGORY WHEN 'Knit tops factory' THEN 14 WHEN 'Woven shirts factory' THEN 9
                       WHEN 'Denim factory' THEN 7 WHEN 'Outerwear factory' THEN 4
                       ELSE 10 END
           * (0.9 + 0.2 * U_NOISE) AS AVG_SHIPMENT_KUNITS,
         LEAST(95, BASE_LATE_PCT + 5 * DRIFT + 10 * MISS_COUNT + 2 * U_NOISE) AS LATE_SHARE
  FROM checks
)
SELECT ENTITY_ID || '-' || TO_CHAR(EVENT_DATE, 'YYYYMMDD') AS EVENT_ID,
       ENTITY_ID, EVENT_DATE,
       SHIPMENT_COUNT,
       ROUND(SHIPMENT_COUNT * AVG_SHIPMENT_KUNITS * (1 - LATE_SHARE / 100), 2) AS ONTIME_KUNITS,
       ROUND(SHIPMENT_COUNT * AVG_SHIPMENT_KUNITS, 2) AS SHIPPED_KUNITS,
       FLAG_COUNT, CONFIRMED_COUNT,
       IFF(CONFIRMED_COUNT > 0 AND U_HOLD < 0.45, 1, 0) AS LOTS_QUARANTINED,
       CASE WHEN FLAG_COUNT = 0 THEN 'None'
            WHEN OUTAGE_EVENT THEN 'Grid power curtailment'
            WHEN CATEGORY = 'Knit tops factory' THEN IFF(U_SIG < 0.6, 'Fabric delivery late', 'Shade band rejected')
            WHEN CATEGORY = 'Woven shirts factory' THEN IFF(U_SIG < 0.5, 'Trims not in-house', 'Line efficiency below plan')
            WHEN CATEGORY = 'Denim factory' THEN IFF(U_SIG < 0.45, 'Wash recipe rework', IFF(U_SIG < 0.8, 'Fabric delivery late', 'Trims not in-house'))
            WHEN CATEGORY = 'Outerwear factory' THEN IFF(U_SIG < 0.55, 'PP sample not approved', 'Subcontract capacity cut')
            ELSE IFF(U_SIG < 0.5, 'Line efficiency below plan', 'Inline inspection fail') END AS RISK_SIGNAL,
       REVIEW_DUE, REVIEW_DONE,
       ROUND(0.5 + 1.6 * DRIFT + 3.4 * MISS_COUNT + U_NOISE * 1.0, 2) AS WIP_GAP_PCT,
       ROUND(LATE_SHARE, 1) AS LATE_PCT,
       CURRENT_TIMESTAMP() AS LOADED_AT
FROM measured;

-- Style readiness snapshot per factory: active styles on order, styles with an
-- approved pre-production (PP) sample on file, and PP sample approvals pending.
CREATE TABLE RAW.STYLE_APPROVALS AS
WITH sized AS (
  SELECT ID, CATEGORY,
         ROUND(CASE CATEGORY WHEN 'Knit tops factory' THEN 64 WHEN 'Woven shirts factory' THEN 52
                             WHEN 'Denim factory' THEN 38 WHEN 'Outerwear factory' THEN 26 ELSE 44 END
               * (0.6 + MOD(ABS(HASH(ID, 'vnto-styles')), 1000000) / 1e6 * 0.8)) AS STYLES,
         CASE CATEGORY WHEN 'Knit tops factory' THEN 0.74 WHEN 'Woven shirts factory' THEN 0.69
                       WHEN 'Denim factory' THEN 0.52 WHEN 'Outerwear factory' THEN 0.41 ELSE 0.63 END
           + MOD(ABS(HASH(ID, 'vnto-approved')), 1000000) / 1e6 * 0.22 AS APPROVED_SHARE
  FROM RAW.FACTORIES
)
SELECT ID AS ENTITY_ID,
       CASE CATEGORY WHEN 'Knit tops factory' THEN 'Knit PP sample approval'
                     WHEN 'Woven shirts factory' THEN 'Woven PP sample approval'
                     WHEN 'Denim factory' THEN 'Wash standard approval'
                     WHEN 'Outerwear factory' THEN 'Outerwear PP sample approval'
                     ELSE 'Performance fabric approval' END AS EVIDENCE_TYPE,
       STYLES AS REQUIRED_QTY,
       LEAST(STYLES, ROUND(STYLES * APPROVED_SHARE)) AS ON_FILE_QTY,
       ROUND((STYLES - LEAST(STYLES, ROUND(STYLES * APPROVED_SHARE))) * MOD(ABS(HASH(ID, 'vnto-pending')), 1000000) / 1e6 * 0.55) AS PENDING_QTY,
       CURRENT_DATE() AS SNAPSHOT_DATE
FROM sized;
