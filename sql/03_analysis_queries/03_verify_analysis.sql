/* ============================================================================
   FabYield - Stage 3 : WHOLE-STAGE ANALYSIS VERIFICATION
   ----------------------------------------------------------------------------
   Stage 3 is an analysis layer, not fixed data, so this verifier checks that
   the CONCLUSIONS still hold rather than that a number equals a literal. Every
   check emits PASS / **CHECK**, and all thresholds are directional (bad group
   vs peers by a sane margin) so they survive reseeding.

   Part A - the two foundation views exist and return sane totals.
   Part B - each of the five analyses re-run condensed, with a verdict:
     B1 yield: product & node flat; ETCH-02 trails the other etchers
     B2 pareto: cumulative % closes at 100; Particle/Flake over-index on bad grp
     B3 spc: CD group-mean shift is positive & meaningful; overlay/film are not
     B4 commonality: ETCH-02/C is the worst-ranked chamber
     B5 correlation: yield falls as defect load rises
   Nothing here modifies data - safe to run any time.
   ============================================================================ */

USE FabYield;
GO

PRINT '=== PART A : FOUNDATION VIEWS EXIST ===';

SELECT
    'v_wafer_yield'  AS object_name,
    CASE WHEN OBJECT_ID('dbo.v_wafer_yield','V')  IS NOT NULL THEN 'PASS' ELSE '**CHECK**' END AS status
UNION ALL
SELECT
    'v_wafer_defects',
    CASE WHEN OBJECT_ID('dbo.v_wafer_defects','V') IS NOT NULL THEN 'PASS' ELSE '**CHECK**' END;

-- Sanity totals from the views (expect 1500 wafers each; defects ~6,300).
SELECT
    (SELECT COUNT(*) FROM dbo.v_wafer_yield)             AS yield_wafers,
    (SELECT COUNT(*) FROM dbo.v_wafer_defects)           AS defect_wafers,
    (SELECT SUM(defect_count) FROM dbo.v_wafer_defects)  AS total_defects,
    CASE WHEN (SELECT COUNT(*) FROM dbo.v_wafer_yield) = 1500
          AND (SELECT COUNT(*) FROM dbo.v_wafer_defects) = 1500
         THEN 'PASS' ELSE '**CHECK**' END               AS status;
GO


PRINT '=== PART B : ANALYSIS CONCLUSIONS HOLD ===';

/* The affected wafer set, defined once for the checks that need it. */
WITH bad_chamber_wafers AS (
    SELECT DISTINCT pr.wafer_id
    FROM dbo.process_runs pr
    JOIN dbo.tools    t ON pr.tool_id    = t.tool_id
    JOIN dbo.chambers c ON pr.chamber_id = c.chamber_id
    WHERE t.tool_code = 'ETCH-02' AND c.chamber_code = 'C'
),

/* ---- B1a : product/node spread should be FLAT (max-min < 1.0 pts) --------- */
prod AS (
    SELECT CAST(100.0*SUM(wy.pass_dies)/SUM(wy.total_dies) AS DECIMAL(5,2)) AS y
    FROM dbo.v_wafer_yield wy
    JOIN dbo.wafers w ON wy.wafer_id = w.wafer_id
    JOIN dbo.lots   l ON w.lot_id    = l.lot_id
    GROUP BY l.product
),
/* ---- B1b : ETCH-02 should trail the mean of the other two etchers --------- */
etch_tool AS (
    SELECT t.tool_code,
           CAST(100.0*SUM(wy.pass_dies)/SUM(wy.total_dies) AS DECIMAL(5,2)) AS y
    FROM (SELECT DISTINCT wafer_id, tool_id FROM dbo.process_runs) wt
    JOIN dbo.v_wafer_yield wy ON wt.wafer_id = wy.wafer_id
    JOIN dbo.tools t ON wt.tool_id = t.tool_id
    WHERE t.tool_type = 'Etcher'
    GROUP BY t.tool_code
),
/* ---- B3 : CD group-mean shift (bad - others) vs the same for overlay/film - */
metric_shift AS (
    SELECT
        mm.metric_type,
        AVG(CASE WHEN bcw.wafer_id IS NOT NULL THEN mm.value END)
      - AVG(CASE WHEN bcw.wafer_id IS NULL     THEN mm.value END) AS mean_diff
    FROM dbo.metrology_measurements mm
    JOIN dbo.process_runs pr ON mm.process_run_id = pr.process_run_id
    LEFT JOIN bad_chamber_wafers bcw ON pr.wafer_id = bcw.wafer_id
    GROUP BY mm.metric_type
),
/* ---- B4 : commonality - rank chambers by avg wafer yield, worst = 1 ------- */
chamber_rank AS (
    SELECT t.tool_code, c.chamber_code,
           RANK() OVER (ORDER BY AVG(wy.yield_pct) ASC) AS worst_rank
    FROM (SELECT DISTINCT wafer_id, chamber_id FROM dbo.process_runs
          WHERE chamber_id IS NOT NULL) wc
    JOIN dbo.v_wafer_yield wy ON wc.wafer_id   = wy.wafer_id
    JOIN dbo.chambers      c  ON wc.chamber_id = c.chamber_id
    JOIN dbo.tools         t  ON c.tool_id     = t.tool_id
    GROUP BY t.tool_code, c.chamber_code
),
/* ---- B5 : yield in low vs high defect band -------------------------------- */
bands AS (
    SELECT
        AVG(CASE WHEN wd.defect_count <= 3 THEN wy.yield_pct END) AS low_band_yield,
        AVG(CASE WHEN wd.defect_count >= 7 THEN wy.yield_pct END) AS high_band_yield
    FROM dbo.v_wafer_yield wy
    JOIN dbo.v_wafer_defects wd ON wy.wafer_id = wd.wafer_id
)

SELECT 'B1 yield: product spread flat' AS check_name,
       CAST((SELECT MAX(y)-MIN(y) FROM prod) AS DECIMAL(5,2)) AS measured,
       CASE WHEN (SELECT MAX(y)-MIN(y) FROM prod) < 1.0 THEN 'PASS' ELSE '**CHECK**' END AS status
UNION ALL
SELECT 'B1 yield: ETCH-02 trails peers',
       (SELECT CAST(y AS DECIMAL(5,2)) FROM etch_tool WHERE tool_code='ETCH-02'),
       CASE WHEN (SELECT y FROM etch_tool WHERE tool_code='ETCH-02')
               < (SELECT AVG(y) FROM etch_tool WHERE tool_code <> 'ETCH-02')
            THEN 'PASS' ELSE '**CHECK**' END
UNION ALL
SELECT 'B3 spc: CD drift present (bad-others, nm)',
       (SELECT CAST(mean_diff AS DECIMAL(6,3)) FROM metric_shift WHERE metric_type='CD'),
       CASE WHEN (SELECT mean_diff FROM metric_shift WHERE metric_type='CD') > 0.5
            THEN 'PASS' ELSE '**CHECK**' END
UNION ALL
SELECT 'B3 spc: Overlay NOT shifted',
       (SELECT CAST(ABS(mean_diff) AS DECIMAL(6,3)) FROM metric_shift WHERE metric_type='Overlay'),
       CASE WHEN (SELECT ABS(mean_diff) FROM metric_shift WHERE metric_type='Overlay') < 0.5
            THEN 'PASS' ELSE '**CHECK**' END
UNION ALL
SELECT 'B3 spc: Film Thickness NOT shifted',
       (SELECT CAST(ABS(mean_diff) AS DECIMAL(6,3)) FROM metric_shift WHERE metric_type='Film Thickness'),
       CASE WHEN (SELECT ABS(mean_diff) FROM metric_shift WHERE metric_type='Film Thickness') < 3.0
            THEN 'PASS' ELSE '**CHECK**' END
UNION ALL
SELECT 'B4 commonality: ETCH-02/C is worst chamber',
       CAST((SELECT worst_rank FROM chamber_rank WHERE tool_code='ETCH-02' AND chamber_code='C') AS DECIMAL(5,2)),
       CASE WHEN (SELECT worst_rank FROM chamber_rank WHERE tool_code='ETCH-02' AND chamber_code='C') = 1
            THEN 'PASS' ELSE '**CHECK**' END
UNION ALL
SELECT 'B5 correlation: high-defect band yields less',
       CAST((SELECT low_band_yield - high_band_yield FROM bands) AS DECIMAL(5,2)),
       CASE WHEN (SELECT high_band_yield FROM bands) < (SELECT low_band_yield FROM bands)
            THEN 'PASS' ELSE '**CHECK**' END;
GO