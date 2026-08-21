/* ============================================================================
   FabYield - Stage 2 : WHOLE-STAGE SEED VERIFICATION
   ----------------------------------------------------------------------------
   Re-runnable health check for all seed data. Two parts:
     A) Row counts for every populated table vs their expected values.
     B) The planted ETCH-02/C signal, re-proven in all THREE places it lands
        (defect counts, die yield, CD drift) plus the control checks.
   Nothing here modifies data - safe to run any time.
   ============================================================================ */

USE FabYield;
GO

PRINT '=== PART A : ROW COUNTS ===';

/* Expected counts are encoded inline so a reviewer sees the intent, and the
   'status' column flags any mismatch as OK / **MISMATCH**. */
SELECT table_name, expected, actual,
       CASE WHEN expected = actual THEN 'OK' ELSE '**MISMATCH**' END AS status
FROM (
    SELECT 'tools'                  AS table_name, 13    AS expected, (SELECT COUNT(*) FROM dbo.tools)                  AS actual
    UNION ALL SELECT 'process_steps',           10,   (SELECT COUNT(*) FROM dbo.process_steps)
    UNION ALL SELECT 'defect_types',            8,    (SELECT COUNT(*) FROM dbo.defect_types)
    UNION ALL SELECT 'bin_codes',               8,    (SELECT COUNT(*) FROM dbo.bin_codes)
    UNION ALL SELECT 'chambers',                14,   (SELECT COUNT(*) FROM dbo.chambers)
    UNION ALL SELECT 'lots',                    60,   (SELECT COUNT(*) FROM dbo.lots)
    UNION ALL SELECT 'wafers',                  1500, (SELECT COUNT(*) FROM dbo.wafers)
    UNION ALL SELECT 'process_runs',            15000,(SELECT COUNT(*) FROM dbo.process_runs)
    UNION ALL SELECT 'defect_inspections',      1500, (SELECT COUNT(*) FROM dbo.defect_inspections)
    UNION ALL SELECT 'bin_results',             216000,(SELECT COUNT(*) FROM dbo.bin_results)
    UNION ALL SELECT 'numbers (tally)',         10000,(SELECT COUNT(*) FROM dbo.numbers)
    /* defects and metrology have randomised counts, so they are checked by a
       RANGE below rather than an exact number. */
) counts
ORDER BY table_name;

/* defects: randomised, but must equal SUM(defect_count) and sit in a sane band. */
SELECT
    'defects' AS table_name,
    (SELECT COUNT(*) FROM dbo.defects)                       AS actual_rows,
    (SELECT SUM(defect_count) FROM dbo.defect_inspections)   AS must_equal_sum_counts,
    CASE WHEN (SELECT COUNT(*) FROM dbo.defects)
            = (SELECT SUM(defect_count) FROM dbo.defect_inspections)
         THEN 'OK (rows = sum of counts)' ELSE '**MISMATCH**' END AS status;

/* metrology: expect ~6000 (1500 CD + 1500 Overlay + 3000 Film Thickness). */
SELECT
    'metrology_measurements' AS table_name,
    (SELECT COUNT(*) FROM dbo.metrology_measurements) AS actual_rows,
    6000 AS expected_rows,
    CASE WHEN (SELECT COUNT(*) FROM dbo.metrology_measurements) = 6000
         THEN 'OK' ELSE '**CHECK**' END AS status;
GO


PRINT '=== PART B : THE PLANTED SIGNAL (ETCH-02/C) ===';

/* The affected wafer set, defined once for all three signal checks. */
WITH bad_chamber_wafers AS (
    SELECT DISTINCT pr.wafer_id
    FROM dbo.process_runs pr
    JOIN dbo.tools    t ON pr.tool_id    = t.tool_id
    JOIN dbo.chambers c ON pr.chamber_id = c.chamber_id
    WHERE t.tool_code = 'ETCH-02' AND c.chamber_code = 'C'
)
SELECT
    'B1 defect_count' AS signal,
    CASE WHEN bcw.wafer_id IS NOT NULL THEN 'ETCH-02/C' ELSE 'others' END AS grp,
    COUNT(*)                              AS wafers,
    CAST(AVG(di.defect_count*1.0) AS DECIMAL(6,2)) AS avg_metric
FROM dbo.defect_inspections di
LEFT JOIN bad_chamber_wafers bcw ON di.wafer_id = bcw.wafer_id
GROUP BY CASE WHEN bcw.wafer_id IS NOT NULL THEN 'ETCH-02/C' ELSE 'others' END;

/* B2 - die yield per group. */
WITH bad_chamber_wafers AS (
    SELECT DISTINCT pr.wafer_id
    FROM dbo.process_runs pr
    JOIN dbo.tools t ON pr.tool_id = t.tool_id
    JOIN dbo.chambers c ON pr.chamber_id = c.chamber_id
    WHERE t.tool_code = 'ETCH-02' AND c.chamber_code = 'C'
),
wafer_yield AS (
    SELECT br.wafer_id,
           AVG(CASE WHEN bcd.is_pass = 1 THEN 100.0 ELSE 0 END) AS yield_pct
    FROM dbo.bin_results br
    JOIN dbo.bin_codes bcd ON br.bin_code_id = bcd.bin_code_id
    GROUP BY br.wafer_id
)
SELECT
    'B2 die_yield_pct' AS signal,
    CASE WHEN bcw.wafer_id IS NOT NULL THEN 'ETCH-02/C' ELSE 'others' END AS grp,
    COUNT(*)                          AS wafers,
    CAST(AVG(wy.yield_pct) AS DECIMAL(6,2)) AS avg_metric
FROM wafer_yield wy
LEFT JOIN bad_chamber_wafers bcw ON wy.wafer_id = bcw.wafer_id
GROUP BY CASE WHEN bcw.wafer_id IS NOT NULL THEN 'ETCH-02/C' ELSE 'others' END;

/* B3 - CD drift (should differ ~1nm) AND Overlay/Film (should NOT differ). */
WITH bad_chamber_wafers AS (
    SELECT DISTINCT pr.wafer_id
    FROM dbo.process_runs pr
    JOIN dbo.tools t ON pr.tool_id = t.tool_id
    JOIN dbo.chambers c ON pr.chamber_id = c.chamber_id
    WHERE t.tool_code = 'ETCH-02' AND c.chamber_code = 'C'
)
SELECT
    'B3 ' + mm.metric_type AS signal,
    CASE WHEN bcw.wafer_id IS NOT NULL THEN 'ETCH-02/C' ELSE 'others' END AS grp,
    COUNT(*)                          AS readings,
    CAST(AVG(mm.value) AS DECIMAL(8,3)) AS avg_metric
FROM dbo.metrology_measurements mm
JOIN dbo.process_runs pr ON mm.process_run_id = pr.process_run_id
LEFT JOIN bad_chamber_wafers bcw ON pr.wafer_id = bcw.wafer_id
GROUP BY mm.metric_type,
         CASE WHEN bcw.wafer_id IS NOT NULL THEN 'ETCH-02/C' ELSE 'others' END
ORDER BY signal, grp;
GO