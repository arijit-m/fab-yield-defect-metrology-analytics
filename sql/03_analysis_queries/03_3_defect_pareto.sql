/* ============================================================================
   FabYield - Stage 3.3 : Defect Pareto
   ----------------------------------------------------------------------------
   Ranks defect types biggest-first with a running CUMULATIVE % - the classic
   80/20 view that tells a fab which defect types to prioritise.

   KEY TECHNIQUE - windowed running total:
     SUM(count) OVER (ORDER BY count DESC) computes a RUNNING sum (row + all
     rows above it), unlike a plain SUM which collapses to one number. That
     running sum, over the grand total, is the cumulative % a Pareto needs.
   ============================================================================ */

USE FabYield;
GO


/* ---- 3.3a  Overall defect Pareto ------------------------------------------ */
WITH type_counts AS (
    /* Count defects per type, and carry the killer flag + category. */
    SELECT
        dt.defect_name,
        dt.category,
        dt.is_killer,
        COUNT(*) AS defect_count
    FROM dbo.defects d
    JOIN dbo.defect_types dt ON d.defect_type_id = dt.defect_type_id
    GROUP BY dt.defect_name, dt.category, dt.is_killer
)
SELECT
    defect_name,
    category,
    is_killer,
    defect_count,
    /* this type's share of all defects */
    CAST(100.0 * defect_count
         / SUM(defect_count) OVER ()               AS DECIMAL(5,2)) AS pct_of_total,
    /* RUNNING cumulative % - this row plus every row ranked above it */
    CAST(100.0 * SUM(defect_count) OVER (ORDER BY defect_count DESC
                                         ROWS UNBOUNDED PRECEDING)
         / SUM(defect_count) OVER ()               AS DECIMAL(5,2)) AS cumulative_pct
FROM type_counts
ORDER BY defect_count DESC;


/* ---- 3.3b  Defect MIX: bad-chamber wafers vs the rest ---------------------- */
/* Shows the bad chamber changes the defect MIX (more Particle/Flake), not just
   the count. Each defect is tagged by whether its wafer passed through ETCH-02/C,
   then we show each type's % share WITHIN each group so the shapes compare
   fairly despite the groups being very different sizes. */
WITH bad_chamber_wafers AS (
    SELECT DISTINCT pr.wafer_id
    FROM dbo.process_runs pr
    JOIN dbo.tools    t ON pr.tool_id    = t.tool_id
    JOIN dbo.chambers c ON pr.chamber_id = c.chamber_id
    WHERE t.tool_code = 'ETCH-02' AND c.chamber_code = 'C'
),
tagged AS (
    /* Every defect, tagged with the group of the wafer it was found on. */
    SELECT
        dt.defect_name,
        CASE WHEN bcw.wafer_id IS NOT NULL THEN 'ETCH-02/C' ELSE 'Others' END AS grp
    FROM dbo.defects d
    JOIN dbo.defect_inspections di ON d.inspection_id = di.inspection_id
    JOIN dbo.defect_types       dt ON d.defect_type_id = dt.defect_type_id
    LEFT JOIN bad_chamber_wafers bcw ON di.wafer_id = bcw.wafer_id
)
SELECT
    defect_name,
    /* % of the bad-chamber group's defects that are this type */
    CAST(100.0 * SUM(CASE WHEN grp = 'ETCH-02/C' THEN 1 ELSE 0 END)
         / NULLIF(SUM(SUM(CASE WHEN grp = 'ETCH-02/C' THEN 1 ELSE 0 END)) OVER (), 0)
         AS DECIMAL(5,2)) AS pct_bad_group,
    /* % of the others group's defects that are this type */
    CAST(100.0 * SUM(CASE WHEN grp = 'Others' THEN 1 ELSE 0 END)
         / NULLIF(SUM(SUM(CASE WHEN grp = 'Others' THEN 1 ELSE 0 END)) OVER (), 0)
         AS DECIMAL(5,2)) AS pct_others_group
FROM tagged
GROUP BY defect_name
ORDER BY pct_bad_group DESC;