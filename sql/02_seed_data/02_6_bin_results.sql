/* ============================================================================
   FabYield - Stage 2.6 : Seed data (GENERATED) - bin_results (die-level yield)
   ----------------------------------------------------------------------------
   The OUTCOME table: 1500 wafers x 144 dies (12x12) = 216,000 dies, each sorted
   into a bin. This is where the bad chamber finally hits YIELD.

   BRIDGE TO THE ML PROJECT: (die_x, die_y, bin) is exactly the shape the Python
   wafer-map defect-classification project consumes. This table is the handoff
   between the SQL and ML halves of the portfolio.

   DIE GRID: the 2.5a tally table (dbo.numbers) is joined TWICE - once for
   die_x (1..12), once for die_y (1..12) - and cross joined per wafer to make
   144 coordinates each.

   BIN LOGIC (per die, from a random roll 0..99):
     - baseline fail chance ~8% (else Pass / bin 1)
     - EDGE penalty: dies far from center (6.5,6.5) fail a bit more (real fabs
       yield worse at the wafer edge - also gives the ML side spatial structure)
     - SUBTLE bad-chamber boost: ETCH-02/C wafers' dies get ~+6% fail chance.
       Tiny per die; across 144 dies x 187 wafers it becomes a detectable
       wafer-yield dip that Stage 3 resolves by grouping. Ranges overlap, so it
       stays invisible wafer-by-wafer.
   ============================================================================ */

USE FabYield;
GO


/* Re-runnable: bin_results has no children, so a straight clear is fine. */
DELETE FROM dbo.bin_results;
GO


WITH
/* Bad-chamber wafer set - same join path as everywhere else. */
bad_chamber_wafers AS (
    SELECT DISTINCT pr.wafer_id
    FROM dbo.process_runs pr
    JOIN dbo.tools    t ON pr.tool_id    = t.tool_id
    JOIN dbo.chambers c ON pr.chamber_id = c.chamber_id
    WHERE t.tool_code = 'ETCH-02' AND c.chamber_code = 'C'
),
/* Map bin numbers to their IDs so we can assign by a small integer below. */
bc AS (
    SELECT bin_number, bin_code_id FROM dbo.bin_codes
),
/* The 12 grid positions, reused for both x and y (n = 1..12 from tally). */
axis AS (
    SELECT n FROM dbo.numbers WHERE n <= 12
),
/* Every die on every wafer: wafer x (12 x-positions) x (12 y-positions). */
dies AS (
    SELECT
        w.wafer_id,
        ax.n AS die_x,
        ay.n AS die_y,
        CASE WHEN bcw.wafer_id IS NOT NULL THEN 1 ELSE 0 END AS is_bad,
        /* Distance from wafer centre (6.5, 6.5), used for the edge penalty. */
        ( (ax.n - 6.5) * (ax.n - 6.5) + (ay.n - 6.5) * (ay.n - 6.5) ) AS dist_sq
    FROM dbo.wafers w
    CROSS JOIN axis ax          -- die_x 1..12
    CROSS JOIN axis ay          -- die_y 1..12
    LEFT JOIN bad_chamber_wafers bcw ON w.wafer_id = bcw.wafer_id
),
/* Give each die a random roll and compute its total fail threshold. */
rolled AS (
    SELECT
        d.wafer_id, d.die_x, d.die_y, d.is_bad,
        ABS(CHECKSUM(NEWID())) % 100 AS roll,          -- 0..99
        /* fail_threshold = baseline 8  + edge penalty (0..~6) + bad boost (0/6).
           A die FAILS if roll < fail_threshold. */
        8
        + CASE WHEN d.dist_sq > 40 THEN 6
               WHEN d.dist_sq > 25 THEN 3
               ELSE 0 END
        + CASE WHEN d.is_bad = 1 THEN 6 ELSE 0 END      AS fail_threshold
    FROM dies d
)
INSERT INTO dbo.bin_results (wafer_id, bin_code_id, die_x, die_y)
SELECT
    r.wafer_id,
    /* Pass if roll >= threshold, else pick a fail bin from a second draw. */
    CASE
      WHEN r.roll >= r.fail_threshold
           THEN (SELECT bin_code_id FROM bc WHERE bin_number = 1)     -- Pass
      ELSE
           /* Distribute failures across fail bins 2..8 using the roll itself. */
           (SELECT bin_code_id FROM bc WHERE bin_number =
                CASE r.roll % 7
                     WHEN 0 THEN 2  WHEN 1 THEN 3  WHEN 2 THEN 4
                     WHEN 3 THEN 5  WHEN 4 THEN 6  WHEN 5 THEN 7
                     ELSE 8 END)
    END AS bin_code_id,
    r.die_x,
    r.die_y
FROM rolled r;
GO