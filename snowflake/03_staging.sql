-- Validate the producer contract before building downstream objects.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

EXECUTE IMMEDIATE $$
DECLARE
  violations INTEGER;
  invalid_source EXCEPTION (-20001, 'Synthetic source failed grain or measure validation');
BEGIN
  SELECT COUNT(*) INTO :violations FROM (
    SELECT ENTITY_ID, EVENT_DATE
    FROM RAW.FACTORY_DAILY
    GROUP BY ENTITY_ID, EVENT_DATE HAVING COUNT(*) <> 1
    UNION ALL
    SELECT observation.ENTITY_ID, observation.EVENT_DATE
    FROM RAW.FACTORY_DAILY observation
    LEFT JOIN RAW.FACTORIES factory ON factory.ID = observation.ENTITY_ID
    WHERE factory.ID IS NULL OR observation.SHIPMENT_COUNT < 0
       OR observation.ONTIME_KUNITS < 0 OR observation.SHIPPED_KUNITS <= 0
       OR observation.CONFIRMED_COUNT < 0 OR observation.CONFIRMED_COUNT > observation.FLAG_COUNT
       OR observation.LOTS_QUARANTINED > observation.CONFIRMED_COUNT
       OR observation.REVIEW_DONE > observation.REVIEW_DUE
  );
  IF (violations > 0) THEN
    RAISE invalid_source;
  END IF;
END;
$$;
