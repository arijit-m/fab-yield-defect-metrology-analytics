/* ============================================================================
   FabYield - Stage 3.1 : Foundational analysis views
   ----------------------------------------------------------------------------
   Reusable building blocks for the analysis layer. Defining "yield" and
   "defect load" ONCE as views means every downstream query (yield-by-lot,
   commonality, correlation) reuses the same definition - the DRY principle.

   A VIEW is a saved query that acts like a virtual table: it stores no data,
   it re-runs its SELECT each time you read from it. CREATE OR ALTER VIEW makes
   the script re-runnable (creates if new, replaces if it exists).

   These views are kept LEAN (single responsibility): v_wafer_yield returns
   yield per wafer and nothing else, so it can be sliced ANY way downstream by
   joining it to wafers/lots/tools - rather than baking one slicing into it.
   ============================================================================ */

USE FabYield;
GO


/* ----------------------------------------------------------------------------
   VIEW: v_wafer_yield
   One row per wafer: total dies, passing dies, and yield %.
   Yield = pass dies / total dies, read from bin_results against bin_codes.is_pass.
   ---------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.v_wafer_yield AS
SELECT
    br.wafer_id,
    COUNT(*)                                              AS total_dies,   -- all dies on the wafer
    SUM(CASE WHEN bc.is_pass = 1 THEN 1 ELSE 0 END)       AS pass_dies,    -- count only passes
    CAST( 100.0 * SUM(CASE WHEN bc.is_pass = 1 THEN 1 ELSE 0 END) / COUNT(*)
          AS DECIMAL(5,2) )                               AS yield_pct     -- pass/total as a %
FROM dbo.bin_results br
JOIN dbo.bin_codes  bc ON br.bin_code_id = bc.bin_code_id
GROUP BY br.wafer_id;
GO


/* ----------------------------------------------------------------------------
   VIEW: v_wafer_defects
   One row per wafer: how many individual defects were found on it (across its
   inspection(s)). Wafers with NO defects still need to appear with 0, so we
   LEFT JOIN from wafers outward and COUNT the defect rows (not *).
   ---------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.v_wafer_defects AS
SELECT
    w.wafer_id,
    COUNT(d.defect_id) AS defect_count   -- COUNT(col) ignores NULLs => 0 for clean wafers
FROM dbo.wafers w
LEFT JOIN dbo.defect_inspections di ON di.wafer_id      = w.wafer_id
LEFT JOIN dbo.defects            d  ON d.inspection_id  = di.inspection_id
GROUP BY w.wafer_id;
GO