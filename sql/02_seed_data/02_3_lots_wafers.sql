/* ============================================================================
   FabYield - Stage 2.3 : Seed data (GENERATED) - lots + wafers
   ----------------------------------------------------------------------------
   First generated stage. We manufacture rows from a generated integer series.

   NOTE ON TECHNIQUE: we use a RECURSIVE CTE - a self-referencing query that counts 1..N. 

       60 lots    : numbers 1..60                      -> LOT-24001 .. LOT-24060
       1500 wafers: 60 lots CROSS JOIN slots 1..25     -> 25 wafers per lot

   Variety (product/node/status) is assigned DETERMINISTICALLY by formula, so
   the dataset is reproducible. Randomness is added later in the event stages.

   Insert order is parent-first: lots, then wafers (each wafer looks up its
   parent lot_id by lot_number - same pattern used for chambers in 2.2).
   ============================================================================ */

USE FabYield;
GO


/* Re-runnable: clear children (wafers) before parents (lots). */
DELETE FROM dbo.wafers;
DELETE FROM dbo.lots;
GO


/* ----------------------------------------------------------------------------
   LOTS : 60 lots generated from a recursive CTE that counts 1..60.

   How the CTE works:
     - "anchor" row:      SELECT 1              (the starting number)
     - "recursive" part:  SELECT n+1 ... WHERE n < 60  (keep adding 1)
     - it stops when n reaches 60, yielding the series 1,2,...,60
   ---------------------------------------------------------------------------- */
WITH lot_numbers AS (
    SELECT 1 AS n                        -- anchor: first number
    UNION ALL
    SELECT n + 1 FROM lot_numbers        -- recursive: next number
    WHERE n < 60                         -- stop condition (60 lots)
)
INSERT INTO dbo.lots (lot_number, product, technology_node, planned_qty, start_date, status)
SELECT
    'LOT-' + CAST(24000 + n AS VARCHAR(10))                     AS lot_number,
    CASE n % 3 WHEN 0 THEN 'SoC-A17'
               WHEN 1 THEN 'GPU-B20'
               ELSE        'MEM-C10' END                        AS product,
    CASE n % 3 WHEN 0 THEN '3nm'
               WHEN 1 THEN '5nm'
               ELSE        '7nm'  END                           AS technology_node,
    25                                                          AS planned_qty,
    DATEADD(DAY, n, '2024-01-01')                              AS start_date,
    CASE WHEN n % 10 = 0 THEN 'In Process' ELSE 'Completed' END AS status
FROM lot_numbers;
GO


/* ----------------------------------------------------------------------------
   WAFERS : 1500 wafers = every lot CROSS JOINed with slots 1..25.
   A second recursive CTE generates the 25 slot numbers, then we CROSS JOIN
   it to the 60 lots (60 x 25 = 1500).
   ---------------------------------------------------------------------------- */
WITH slot_numbers AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM slot_numbers
    WHERE n < 25                         -- 25 slots per cassette
)
INSERT INTO dbo.wafers (wafer_scribe, lot_id, slot_no, status)
SELECT
    l.lot_number + '.' + RIGHT('0' + CAST(slot.n AS VARCHAR(2)), 2) AS wafer_scribe,
    l.lot_id                                                        AS lot_id,
    slot.n                                                          AS slot_no,
    'Good'                                                          AS status
FROM dbo.lots AS l
CROSS JOIN slot_numbers AS slot;
GO