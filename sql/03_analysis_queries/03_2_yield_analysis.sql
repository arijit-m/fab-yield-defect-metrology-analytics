/* ============================================================================
   FabYield - Stage 3.2 : Yield analysis
   ----------------------------------------------------------------------------
   Yield sliced the way a fab reports it: by lot, product, technology node, and
   tool. All four read from v_wafer_yield (Stage 3.1) - we never recompute yield.

   CORRECT AGGREGATION: to roll wafer yield up to a group, we SUM pass_dies and
   SUM total_dies across the group, then divide - NOT average the per-wafer
   percentages. Averaging percentages weights a small wafer the same as a large
   one; summing dies first is die-weighted and stays correct if die counts vary.
   (Here all wafers have 144 dies, so both agree - but the correct form shows
   the reasoning and is future-proof.)
   ============================================================================ */

USE FabYield;
GO


/* ---- 3.2a  Yield by LOT ---------------------------------------------------- */
SELECT
    l.lot_number,
    l.product,
    l.technology_node,
    COUNT(DISTINCT wy.wafer_id)                                   AS wafers,
    SUM(wy.total_dies)                                            AS total_dies,
    SUM(wy.pass_dies)                                             AS pass_dies,
    CAST(100.0 * SUM(wy.pass_dies) / SUM(wy.total_dies) AS DECIMAL(5,2)) AS yield_pct
FROM dbo.v_wafer_yield wy
JOIN dbo.wafers w ON wy.wafer_id = w.wafer_id
JOIN dbo.lots   l ON w.lot_id    = l.lot_id
GROUP BY l.lot_number, l.product, l.technology_node
ORDER BY yield_pct ASC;   -- worst-yielding lots first (where you'd investigate)


/* ---- 3.2b  Yield by PRODUCT ------------------------------------------------ */
SELECT
    l.product,
    COUNT(DISTINCT wy.wafer_id)                                   AS wafers,
    CAST(100.0 * SUM(wy.pass_dies) / SUM(wy.total_dies) AS DECIMAL(5,2)) AS yield_pct
FROM dbo.v_wafer_yield wy
JOIN dbo.wafers w ON wy.wafer_id = w.wafer_id
JOIN dbo.lots   l ON w.lot_id    = l.lot_id
GROUP BY l.product
ORDER BY yield_pct DESC;


/* ---- 3.2c  Yield by TECHNOLOGY NODE ---------------------------------------- */
SELECT
    l.technology_node,
    COUNT(DISTINCT wy.wafer_id)                                   AS wafers,
    CAST(100.0 * SUM(wy.pass_dies) / SUM(wy.total_dies) AS DECIMAL(5,2)) AS yield_pct
FROM dbo.v_wafer_yield wy
JOIN dbo.wafers w ON wy.wafer_id = w.wafer_id
JOIN dbo.lots   l ON w.lot_id    = l.lot_id
GROUP BY l.technology_node
ORDER BY yield_pct DESC;


/* ---- 3.2d  Yield by TOOL --------------------------------------------------- */
/* A wafer's yield is attributed to EVERY tool it ran on (via process_runs).
   DISTINCT wafer/tool pairs first, so a wafer that used a tool at several steps
   is counted once per tool - then roll yield up per tool. Tools whose wafers
   yield low are commonality-analysis warm-up. */
WITH wafer_tool AS (
    SELECT DISTINCT pr.wafer_id, pr.tool_id
    FROM dbo.process_runs pr
)
SELECT
    t.tool_code,
    t.tool_type,
    COUNT(DISTINCT wt.wafer_id)                                   AS wafers_touched,
    CAST(100.0 * SUM(wy.pass_dies) / SUM(wy.total_dies) AS DECIMAL(5,2)) AS yield_pct
FROM wafer_tool wt
JOIN dbo.v_wafer_yield wy ON wt.wafer_id = wy.wafer_id
JOIN dbo.tools         t  ON wt.tool_id  = t.tool_id
GROUP BY t.tool_code, t.tool_type
ORDER BY yield_pct ASC;   -- lowest-yield tools first