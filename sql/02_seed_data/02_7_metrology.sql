/* ============================================================================
   FabYield - Stage 2.7 : Seed data (GENERATED) - metrology_measurements
   ----------------------------------------------------------------------------
   The LAST seed stage. Feeds the Stage 3 SPC / control-chart queries.
   Three metrics, each attached to the runs where it is physically measured:
       CD            -> Metrology step (METR-100) runs   target 45 nm
       Overlay       -> Metrology step (METR-100) runs   target 0 nm
       Film Thickness-> Deposition runs                  target 1000 A

   NORMAL-ish DATA: SPC assumes a bell-shaped spread, but CHECKSUM(NEWID())%k is
   FLAT (uniform). Summing TWO uniform draws yields a triangular, bell-leaning
   shape (a mini central-limit effect) - far more realistic for control charts.

   SUBTLE SIGNAL - CD ONLY: bad-chamber (ETCH-02/C) wafers get their CD mean
   nudged +~1 nm. Small vs the ~1.5 nm natural spread, so single readings stay
   in spec and look normal; but the GROUP MEAN is off-centre, which is exactly
   what SPC control rules detect. Overlay and film thickness get NO shift - so
   the drift is ISOLATED to CD, a realistic single-parameter excursion.

   Signal path (as always): measurement -> process_run -> chamber -> ETCH-02/C.
   ============================================================================ */

USE FabYield;
GO


/* Re-runnable: metrology_measurements has no children. */
DELETE FROM dbo.metrology_measurements;
GO


WITH
/* Bad-chamber wafer set - same join path used throughout Stage 2. */
bad_chamber_wafers AS (
    SELECT DISTINCT pr.wafer_id
    FROM dbo.process_runs pr
    JOIN dbo.tools    t ON pr.tool_id    = t.tool_id
    JOIN dbo.chambers c ON pr.chamber_id = c.chamber_id
    WHERE t.tool_code = 'ETCH-02' AND c.chamber_code = 'C'
),
/* Runs eligible for CD + Overlay: the metrology step (METR-100). Carry the
   bad-chamber flag so CD can shift for those wafers. */
metro_runs AS (
    SELECT pr.process_run_id,
           pr.run_start,
           CASE WHEN bcw.wafer_id IS NOT NULL THEN 1 ELSE 0 END AS is_bad
    FROM dbo.process_runs pr
    JOIN dbo.process_steps ps ON pr.process_step_id = ps.process_step_id
    LEFT JOIN bad_chamber_wafers bcw ON pr.wafer_id = bcw.wafer_id
    WHERE ps.step_code = 'METR-100'
),
/* Runs eligible for Film Thickness: deposition runs. */
dep_runs AS (
    SELECT pr.process_run_id, pr.run_start
    FROM dbo.process_runs pr
    JOIN dbo.process_steps ps ON pr.process_step_id = ps.process_step_id
    WHERE ps.process_module = 'Deposition'
)

/* ---- CD : target 45 nm, spec 42..48. Two uniform draws (0..30 each, /10 =>
        0..3.0 each) summed and centred, giving ~ -3..+3 nm bell-ish deviation.
        Bad-chamber wafers add +1.0 nm mean shift. ------------------------------ */
INSERT INTO dbo.metrology_measurements
    (process_run_id, metric_type, value, target, spec_low, spec_high, unit, measured_at)
SELECT
    mr.process_run_id,
    'CD',
    CAST(
        45.0
        + ( (ABS(CHECKSUM(NEWID())) % 31) / 10.0 )      -- draw 1: 0.0..3.0
        + ( (ABS(CHECKSUM(NEWID())) % 31) / 10.0 )      -- draw 2: 0.0..3.0
        - 3.0                                           -- centre => -3.0..+3.0
        + CASE WHEN mr.is_bad = 1 THEN 1.0 ELSE 0 END   -- SUBTLE CD shift
    AS DECIMAL(12,4)),
    45.0, 42.0, 48.0, 'nm', mr.run_start
FROM metro_runs mr

UNION ALL

/* ---- Overlay : target 0 nm, spec -10..+10. Two draws (0..60/10 = 0..6 each),
        centred to ~ -6..+6. NO bad-chamber shift (stays centred). ------------- */
SELECT
    mr.process_run_id,
    'Overlay',
    CAST(
        0.0
        + ( (ABS(CHECKSUM(NEWID())) % 61) / 10.0 )      -- 0.0..6.0
        + ( (ABS(CHECKSUM(NEWID())) % 61) / 10.0 )      -- 0.0..6.0
        - 6.0                                           -- centre => -6.0..+6.0
    AS DECIMAL(12,4)),
    0.0, -10.0, 10.0, 'nm', mr.run_start
FROM metro_runs mr

UNION ALL

/* ---- Film Thickness : target 1000 A, spec 950..1050. Two draws (0..300/10 =
        0..30 each), centred to ~ -30..+30 A. NO bad-chamber shift. ------------- */
SELECT
    dr.process_run_id,
    'Film Thickness',
    CAST(
        1000.0
        + ( (ABS(CHECKSUM(NEWID())) % 301) / 10.0 )     -- 0.0..30.0
        + ( (ABS(CHECKSUM(NEWID())) % 301) / 10.0 )     -- 0.0..30.0
        - 30.0                                          -- centre => -30..+30
    AS DECIMAL(12,4)),
    1000.0, 950.0, 1050.0, 'A', dr.run_start
FROM dep_runs dr;
GO