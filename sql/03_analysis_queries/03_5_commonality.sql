/* ============================================================================
   FabYield - Stage 3.5 : Commonality analysis  (THE HEADLINE)
   ----------------------------------------------------------------------------
   The question every yield investigation asks: given a set of wafers, which
   TOOL/CHAMBER has wafers that fail at a higher rate than its peers?

   The query is NOT told about ETCH-02/C. It rediscovers it from the data by:
     1. taking each wafer's yield (from v_wafer_yield),
     2. walking process_runs so each (wafer -> chamber) pass is a row,
     3. grouping by chamber and averaging the yield of wafers that used it,
     4. ranking chambers worst-yield first.

   This is ONLY possible because process_runs ties wafers to the exact chamber
   they ran in - the design decision made back in Stage 1. The ~6-point yield
   gap on ETCH-02/C, invisible per-wafer and invisible to by-tool / by-metrology
   views, becomes obvious once wafers are grouped by the CHAMBER they shared.
   ============================================================================ */

USE FabYield;
GO


/* ---- 3.5a  Commonality ranking: avg wafer yield by chamber ---------------- */
/* One row per chamber that wafers passed through. We DISTINCT the wafer/chamber
   pairs first (a wafer may hit a chamber at more than one step - count it once),
   then average those wafers' yields per chamber and rank worst-first. */
WITH wafer_chamber AS (
    SELECT DISTINCT pr.wafer_id, pr.chamber_id
    FROM dbo.process_runs pr
    WHERE pr.chamber_id IS NOT NULL          -- only chamber-bearing runs (etch/dep)
)
SELECT
    t.tool_code,
    c.chamber_code,
    COUNT(DISTINCT wc.wafer_id)                       AS wafers_through,
    CAST(AVG(wy.yield_pct) AS DECIMAL(5,2))           AS avg_yield_pct,
    /* rank so the worst chamber is #1 - this is the "commonality hit" */
    RANK() OVER (ORDER BY AVG(wy.yield_pct) ASC)      AS worst_rank
FROM wafer_chamber wc
JOIN dbo.v_wafer_yield wy ON wc.wafer_id   = wy.wafer_id
JOIN dbo.chambers      c  ON wc.chamber_id = c.chamber_id
JOIN dbo.tools         t  ON c.tool_id     = t.tool_id
GROUP BY t.tool_code, c.chamber_code
ORDER BY avg_yield_pct ASC;   -- worst chamber floats to the top


/* ---- 3.5b  Statistical confirmation: the suspect vs all other etch chambers */
/* Having identified the suspect, quantify how much it stands apart: compare the
   yield of ITS wafers against the yield of wafers from all OTHER etch chambers.
   A clear multi-point gap = a real outlier, not just first in a sorted list. */
WITH wafer_chamber AS (
    SELECT DISTINCT pr.wafer_id, pr.chamber_id
    FROM dbo.process_runs pr
    WHERE pr.chamber_id IS NOT NULL
),
labeled AS (
    SELECT
        wy.yield_pct,
        CASE WHEN t.tool_code = 'ETCH-02' AND c.chamber_code = 'C'
             THEN 'Suspect: ETCH-02/C'
             ELSE 'Other etch chambers' END AS grp
    FROM wafer_chamber wc
    JOIN dbo.v_wafer_yield wy ON wc.wafer_id   = wy.wafer_id
    JOIN dbo.chambers      c  ON wc.chamber_id = c.chamber_id
    JOIN dbo.tools         t  ON c.tool_id     = t.tool_id
    WHERE t.tool_type = 'Etcher'          -- compare like with like: etch chambers only
)
SELECT
    grp,
    COUNT(*)                                AS wafers,
    CAST(AVG(yield_pct) AS DECIMAL(5,2))    AS avg_yield_pct,
    CAST(MIN(yield_pct) AS DECIMAL(5,2))    AS min_yield,
    CAST(MAX(yield_pct) AS DECIMAL(5,2))    AS max_yield,
    CAST(STDEV(yield_pct) AS DECIMAL(5,2))  AS sigma
FROM labeled
GROUP BY grp
ORDER BY avg_yield_pct ASC;