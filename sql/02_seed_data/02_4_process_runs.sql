/* ============================================================================
   FabYield - Stage 2.4 : Seed data (GENERATED) - process_runs
   ----------------------------------------------------------------------------
   THE central fact table. One row = one wafer at one process step, on one tool,
   (optionally) in one chamber. 1500 wafers x 10 steps = 15,000 runs.

   HOW ROWS ARE GENERATED (no recursion needed - we multiply existing tables):
     wafers (1500)  CROSS JOIN  process_steps (10)   ->  15,000 (wafer, step) pairs
   then each pair is assigned a tool + chamber appropriate to that step's module.

   TWO KEY DEVICES:
     1) run_targets CTE - a catalog of every valid (module -> tool -> chamber)
        a run could be assigned to. Etch/Deposition contribute one row PER
        CHAMBER; no-chamber modules contribute one row per tool (chamber = NULL).
        Options are numbered 1..N within each module (opt_no).
     2) modulo round-robin - wafer_id % (option count) picks which tool/chamber,
        dealing wafers evenly across the options like dealing cards.

   THE PLANTED SIGNAL (bad actor): ETCH-02, Chamber C.
     In the etch ordering (tool_code, chamber_code) it is option 6 of 8, so
     wafers with (wafer_id % 8) = 5 route through it - at BOTH etch steps.
     IMPORTANT: at THIS stage that chamber gets the SAME ~375 runs as every
     other etch chamber. The distribution is intentionally EVEN. The bad
     chamber looks normal here. Its higher failure rate is applied later, in
     Stage 2.6 (bin_results), so that Stage 3 commonality analysis can
     *rediscover* it from yield data - the way a real yield engineer would.
     We identify it by business identity (ETCH-02 / C), never a magic number.
   ============================================================================ */

USE FabYield;
GO


/* Re-runnable: clear process_runs' own children first (metrology_measurements),
   then process_runs itself. defects/bin_results don't depend on process_runs,
   but metrology_measurements does. All still empty at this point anyway. */
DELETE FROM dbo.metrology_measurements;
DELETE FROM dbo.process_runs;
GO


/* ----------------------------------------------------------------------------
   Generate all 15,000 runs in one set-based INSERT.
   ---------------------------------------------------------------------------- */
WITH
/* (a) Every valid place a run can be assigned, grouped by process module.
       ROW_NUMBER numbers the options 1..N *within* each module. */
targets_raw AS (
    -- Lithography -> scanners, no chamber
    SELECT 'Lithography' AS module, t.tool_id, CAST(NULL AS INT) AS chamber_id,
           ROW_NUMBER() OVER (ORDER BY t.tool_code) AS opt_no
    FROM dbo.tools t
    WHERE t.tool_type = 'Scanner'

    UNION ALL
    -- Etch -> etchers, one option per chamber  (ETCH-02/C is option 6 of 8)
    SELECT 'Etch', t.tool_id, c.chamber_id,
           ROW_NUMBER() OVER (ORDER BY t.tool_code, c.chamber_code)
    FROM dbo.tools t
    JOIN dbo.chambers c ON c.tool_id = t.tool_id
    WHERE t.tool_type = 'Etcher'

    UNION ALL
    -- Deposition -> dep tools, one option per chamber
    SELECT 'Deposition', t.tool_id, c.chamber_id,
           ROW_NUMBER() OVER (ORDER BY t.tool_code, c.chamber_code)
    FROM dbo.tools t
    JOIN dbo.chambers c ON c.tool_id = t.tool_id
    WHERE t.tool_type = 'Deposition'

    UNION ALL
    -- CMP -> single tool, no chamber
    SELECT 'CMP', t.tool_id, NULL, ROW_NUMBER() OVER (ORDER BY t.tool_code)
    FROM dbo.tools t
    WHERE t.tool_type = 'CMP'

    UNION ALL
    -- Implant -> single tool, no chamber
    SELECT 'Implant', t.tool_id, NULL, ROW_NUMBER() OVER (ORDER BY t.tool_code)
    FROM dbo.tools t
    WHERE t.tool_type = 'Implant'

    UNION ALL
    -- Metrology -> CD-SEM + overlay tool, no chamber
    SELECT 'Metrology', t.tool_id, NULL, ROW_NUMBER() OVER (ORDER BY t.tool_code)
    FROM dbo.tools t
    WHERE t.tool_type IN ('Metrology', 'CD-SEM')
),
/* (b) Add the option COUNT per module, so we can modulo against it. */
run_targets AS (
    SELECT module, tool_id, chamber_id, opt_no,
           COUNT(*) OVER (PARTITION BY module) AS opt_count
    FROM targets_raw
),
/* (c) Every (wafer, step) pair - 1500 x 10 = 15,000 rows. We also pull the
       lot start_date so run timestamps can progress along the route. */
wafer_step AS (
    SELECT w.wafer_id,
           l.start_date,
           ps.process_step_id,
           ps.process_module,
           ps.sequence_order
    FROM dbo.wafers w
    JOIN dbo.lots   l ON w.lot_id = l.lot_id
    CROSS JOIN dbo.process_steps ps
)
INSERT INTO dbo.process_runs
    (wafer_id, process_step_id, tool_id, chamber_id, run_start, run_end, run_status)
SELECT
    ws.wafer_id,
    ws.process_step_id,
    rt.tool_id,
    rt.chamber_id,
    /* run_start: lot start, pushed later by sequence_order so steps progress in
       route order (each step ~30 min after the previous nominal position). */
    DATEADD(MINUTE, ws.sequence_order * 30, CAST(ws.start_date AS DATETIME2)) AS run_start,
    /* run_end: 20 minutes after start (a nominal run duration). */
    DATEADD(MINUTE, ws.sequence_order * 30 + 20, CAST(ws.start_date AS DATETIME2)) AS run_end,
    'Completed' AS run_status
FROM wafer_step ws
/* Round-robin: pick the option whose number equals wafer_id mod (option count).
   Because all options in a module share opt_count, exactly one opt_no matches. */
JOIN run_targets rt
      ON rt.module = ws.process_module
     AND rt.opt_no = (ws.wafer_id % rt.opt_count) + 1;
GO