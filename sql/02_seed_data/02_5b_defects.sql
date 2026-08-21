/* ============================================================================
   FabYield - Stage 2.5b : Seed data (GENERATED) - defect_inspections + defects
   ----------------------------------------------------------------------------
   One post-etch inspection per wafer (at Metal-1 Etch, ETCH-200), then the
   individual defects that make up each inspection's count.

   THE SUBTLE SIGNAL (planted here for the first time in defect data):
     - Baseline per wafer:  2..6 defects   = 2 + (rand % 5)
     - ETCH-02/C wafers:    +1..+3 extra   = small, averages ~+2
     The boost shifts the GROUP MEAN but is smaller than baseline scatter, so no
     single wafer looks obviously bad. Only aggregation over the ~187 affected
     wafers reveals it - which is exactly what Stage 3 commonality analysis does.

     Bad-chamber wafers are found by joining back through process_runs to
     ETCH-02 / C (the same join path Stage 3 walks). We do NOT hard-code wafer
     IDs - the affected set is DERIVED from run history, as in reality.

   RANDOMNESS: ABS(CHECKSUM(NEWID())) % k gives a per-row random 0..k-1.
     NEWID() = fresh random GUID per row; CHECKSUM hashes it to an int;
     ABS(...) % k bounds it. Standard T-SQL randomness idiom.

   COUNT -> ROWS: we expand each wafer's defect_count into that many rows by
     joining dbo.numbers (the 2.5a tally table) and keeping n <= defect_count.
   ============================================================================ */

USE FabYield;
GO


/* Re-runnable: clear child (defects) before parent (defect_inspections). */
DELETE FROM dbo.defects;
DELETE FROM dbo.defect_inspections;
GO


/* ----------------------------------------------------------------------------
   PART 1 - defect_inspections : one row per wafer.
   We flag each wafer as bad-chamber or not by checking whether it has ANY
   process_run through ETCH-02 / C, then set defect_count = baseline + boost.
   ---------------------------------------------------------------------------- */
WITH bad_chamber_wafers AS (
    /* The DISTINCT set of wafers that passed through ETCH-02 / C. */
    SELECT DISTINCT pr.wafer_id
    FROM dbo.process_runs pr
    JOIN dbo.tools    t ON pr.tool_id    = t.tool_id
    JOIN dbo.chambers c ON pr.chamber_id = c.chamber_id
    WHERE t.tool_code = 'ETCH-02' AND c.chamber_code = 'C'
),
inspection_tool AS (
    /* Pick a real inspection tool to attribute the scan to (INSP-01). */
    SELECT TOP 1 tool_id FROM dbo.tools WHERE tool_code = 'INSP-01'
)
INSERT INTO dbo.defect_inspections
    (wafer_id, tool_id, inspection_date, inspection_step, defect_count)
SELECT
    w.wafer_id,
    (SELECT tool_id FROM inspection_tool),
    DATEADD(DAY, 3, CAST(l.start_date AS DATETIME2))  AS inspection_date,
    'Post-Etch (Metal-1)'                             AS inspection_step,
    /* baseline 2..6 */
    2 + (ABS(CHECKSUM(NEWID())) % 5)
    /* + subtle boost 1..3 ONLY for bad-chamber wafers */
    + CASE WHEN bcw.wafer_id IS NOT NULL
           THEN 1 + (ABS(CHECKSUM(NEWID())) % 3)
           ELSE 0 END                                 AS defect_count
FROM dbo.wafers w
JOIN dbo.lots   l ON w.lot_id = l.lot_id
LEFT JOIN bad_chamber_wafers bcw ON w.wafer_id = bcw.wafer_id;  -- flag = matched?
GO


/* ----------------------------------------------------------------------------
   PART 2 - defects : expand each inspection's defect_count into individual rows
   via the tally table, and assign each defect a type.

   Type skew: bad-chamber wafers lean toward Particle/Flake (dirty-etch-chamber
   signature). We re-detect bad-chamber membership the same way, then use a
   per-row random draw to choose the defect_type_id, with tilted odds.
   ---------------------------------------------------------------------------- */
WITH bad_chamber_wafers AS (
    SELECT DISTINCT pr.wafer_id
    FROM dbo.process_runs pr
    JOIN dbo.tools    t ON pr.tool_id    = t.tool_id
    JOIN dbo.chambers c ON pr.chamber_id = c.chamber_id
    WHERE t.tool_code = 'ETCH-02' AND c.chamber_code = 'C'
),
/* Map defect codes to their IDs so we can pick by a small integer below. */
dt AS (
    SELECT defect_code, defect_type_id FROM dbo.defect_types
),
/* One row per individual defect: join inspections to the tally table, keeping
   n <= defect_count. Also carry a fresh random 0..99 and the bad-chamber flag
   so the next step can choose a type with tilted odds. */
exploded AS (
    SELECT
        di.inspection_id,
        num.n                                   AS defect_seq,
        ABS(CHECKSUM(NEWID())) % 100            AS roll,        -- 0..99
        CASE WHEN bcw.wafer_id IS NOT NULL THEN 1 ELSE 0 END AS is_bad
    FROM dbo.defect_inspections di
    JOIN dbo.numbers num ON num.n <= di.defect_count            -- COUNT -> ROWS
    LEFT JOIN bad_chamber_wafers bcw ON di.wafer_id = bcw.wafer_id
)
INSERT INTO dbo.defects (inspection_id, defect_type_id, x_um, y_um, defect_size_um)
SELECT
    e.inspection_id,
    /* Choose a defect type from the roll. Bad-chamber wafers get a much higher
       chance of Particle/Flake; good-chamber wafers are spread more evenly. */
    CASE
      WHEN e.is_bad = 1 THEN
           CASE WHEN e.roll < 45 THEN (SELECT defect_type_id FROM dt WHERE defect_code='PART')
                WHEN e.roll < 70 THEN (SELECT defect_type_id FROM dt WHERE defect_code='FLAKE')
                WHEN e.roll < 82 THEN (SELECT defect_type_id FROM dt WHERE defect_code='BRIDGE')
                WHEN e.roll < 91 THEN (SELECT defect_type_id FROM dt WHERE defect_code='RESIDUE')
                ELSE                  (SELECT defect_type_id FROM dt WHERE defect_code='SCRATCH')
           END
      ELSE
           CASE WHEN e.roll < 20 THEN (SELECT defect_type_id FROM dt WHERE defect_code='PART')
                WHEN e.roll < 38 THEN (SELECT defect_type_id FROM dt WHERE defect_code='BRIDGE')
                WHEN e.roll < 54 THEN (SELECT defect_type_id FROM dt WHERE defect_code='OPEN')
                WHEN e.roll < 68 THEN (SELECT defect_type_id FROM dt WHERE defect_code='RESIDUE')
                WHEN e.roll < 80 THEN (SELECT defect_type_id FROM dt WHERE defect_code='VOID')
                WHEN e.roll < 90 THEN (SELECT defect_type_id FROM dt WHERE defect_code='CONTAM')
                WHEN e.roll < 96 THEN (SELECT defect_type_id FROM dt WHERE defect_code='SCRATCH')
                ELSE                  (SELECT defect_type_id FROM dt WHERE defect_code='FLAKE')
           END
    END                                                     AS defect_type_id,
    /* Random-ish wafer location, micrometres (150mm-ish radius spread). */
    CAST((ABS(CHECKSUM(NEWID())) % 150000) - 75000 AS DECIMAL(12,4)) AS x_um,
    CAST((ABS(CHECKSUM(NEWID())) % 150000) - 75000 AS DECIMAL(12,4)) AS y_um,
    /* Random defect size 0.05 .. ~2.05 um. */
    CAST(0.05 + (ABS(CHECKSUM(NEWID())) % 200) / 100.0 AS DECIMAL(10,4)) AS defect_size_um
FROM exploded e;
GO