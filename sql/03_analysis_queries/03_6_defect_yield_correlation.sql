/* ============================================================================
   FabYield - Stage 3.6 : Defect-to-yield correlation  (closing the loop)
   ----------------------------------------------------------------------------
   Ties the two halves of the story together: wafers with MORE defects tend to
   yield WORSE. This turns "the bad chamber makes defects" + "the bad chamber
   loses yield" (shown separately) into one causal chain: defects cost yield.

   Reuses BOTH Stage 3.1 views: v_wafer_defects (defects/wafer) joined to
   v_wafer_yield (yield/wafer) on wafer_id.
   ============================================================================ */

USE FabYield;
GO


/* ---- 3.6a  Yield vs defect load ------------------------------------------- */
/* Bucket every wafer by how many defects it carries, then show average yield
   per bucket. Yield should FALL as the defect bucket rises = the correlation. */
WITH wafer_stats AS (
    SELECT
        wy.wafer_id,
        wy.yield_pct,
        wd.defect_count,
        /* bucket the defect load into readable bands */
        CASE
            WHEN wd.defect_count <= 3 THEN '0-3  (low)'
            WHEN wd.defect_count <= 6 THEN '4-6  (medium)'
            WHEN wd.defect_count <= 9 THEN '7-9  (high)'
            ELSE                          '10+  (very high)'
        END AS defect_band
    FROM dbo.v_wafer_yield   wy
    JOIN dbo.v_wafer_defects wd ON wy.wafer_id = wd.wafer_id
)
SELECT
    defect_band,
    COUNT(*)                                 AS wafers,
    CAST(AVG(yield_pct)   AS DECIMAL(5,2))   AS avg_yield_pct,
    CAST(AVG(defect_count * 1.0) AS DECIMAL(5,2)) AS avg_defects
FROM wafer_stats
GROUP BY defect_band
ORDER BY avg_defects ASC;   -- low-defect band first; watch yield descend


/* ---- 3.6b  The full fingerprint: ETCH-02/C vs others ---------------------- */
/* One summary row per group showing the COMPLETE signal in a single grid:
   defects up, yield down, particle/flake share up. This is the project's
   one-table summary. */
WITH bad_chamber_wafers AS (
    SELECT DISTINCT pr.wafer_id
    FROM dbo.process_runs pr
    JOIN dbo.tools    t ON pr.tool_id    = t.tool_id
    JOIN dbo.chambers c ON pr.chamber_id = c.chamber_id
    WHERE t.tool_code = 'ETCH-02' AND c.chamber_code = 'C'
),
/* Per-wafer: yield, defect count, and how many of its defects are Particle/Flake. */
per_wafer AS (
    SELECT
        w.wafer_id,
        CASE WHEN bcw.wafer_id IS NOT NULL THEN 'ETCH-02/C (bad)' ELSE 'All others' END AS grp,
        wy.yield_pct,
        wd.defect_count,
        (SELECT COUNT(*)
         FROM dbo.defect_inspections di
         JOIN dbo.defects d          ON d.inspection_id = di.inspection_id
         JOIN dbo.defect_types dtp   ON d.defect_type_id = dtp.defect_type_id
         WHERE di.wafer_id = w.wafer_id
           AND dtp.defect_name IN ('Particle', 'Flake')) AS particle_flake_count
    FROM dbo.wafers w
    JOIN dbo.v_wafer_yield   wy ON w.wafer_id = wy.wafer_id
    JOIN dbo.v_wafer_defects wd ON w.wafer_id = wd.wafer_id
    LEFT JOIN bad_chamber_wafers bcw ON w.wafer_id = bcw.wafer_id
)
SELECT
    grp,
    COUNT(*)                                       AS wafers,
    CAST(AVG(yield_pct)   AS DECIMAL(5,2))         AS avg_yield_pct,
    CAST(AVG(defect_count * 1.0) AS DECIMAL(5,2))  AS avg_defects,
    /* particle+flake as a % of all this group's defects */
    CAST(100.0 * SUM(particle_flake_count) / NULLIF(SUM(defect_count), 0)
         AS DECIMAL(5,2))                          AS particle_flake_pct
FROM per_wafer
GROUP BY grp
ORDER BY avg_yield_pct ASC;