/* ============================================================================
   FabYield - Stage 3.4 : SPC control charts (CD / Overlay / Film Thickness)
   ----------------------------------------------------------------------------
   Statistical Process Control: compute each metric's natural variation and set
   control limits at mean +/- 3 sigma (UCL/LCL). ~99.7% of in-control data sits
   within +/-3 sigma, so points outside are genuine alarms.

   HONEST NOTE ON A SUBTLE SHIFT: our planted CD drift (~1 nm) is SMALLER than
   the natural CD spread (~1.5 nm), so most individual bad-chamber readings still
   fall INSIDE +/-3 sigma. A point-outside-limits rule therefore catches only a
   few. The detector that works for a small SUSTAINED shift is comparing the
   bad-group MEAN to the centre line - which is why real fabs also use run rules
   (e.g. "8 consecutive points on one side of centre"). 

   STDEV() is SQL Server's sample standard deviation aggregate (our sigma).
   ============================================================================ */

USE FabYield;
GO


/* ---- 3.4a  Overall control limits, one row per metric --------------------- */
WITH stats AS (
    SELECT
        metric_type,
        COUNT(*)                                   AS readings,
        CAST(AVG(value)   AS DECIMAL(12,4))        AS center_line,   -- process mean
        CAST(STDEV(value) AS DECIMAL(12,4))        AS sigma          -- std deviation
    FROM dbo.metrology_measurements
    GROUP BY metric_type
)
SELECT
    metric_type,
    readings,
    center_line,
    sigma,
    CAST(center_line + 3 * sigma AS DECIMAL(12,4)) AS ucl,   -- upper control limit
    CAST(center_line - 3 * sigma AS DECIMAL(12,4)) AS lcl,   -- lower control limit
    /* how many individual readings fall outside +/-3 sigma */
    (SELECT COUNT(*)
     FROM dbo.metrology_measurements mm
     WHERE mm.metric_type = s.metric_type
       AND (mm.value > s.center_line + 3 * s.sigma
         OR mm.value < s.center_line - 3 * s.sigma)) AS points_out_of_control
FROM stats s
ORDER BY metric_type;


/* ---- 3.4b  CD: bad-chamber group vs overall limits ------------------------ */
/* The subtle-shift detector: compare each group's MEAN CD to the overall centre
   line and limits. Even though few individual points breach +/-3 sigma, the
   bad-chamber group MEAN sits visibly above centre. */
WITH bad_chamber_wafers AS (
    SELECT DISTINCT pr.wafer_id
    FROM dbo.process_runs pr
    JOIN dbo.tools    t ON pr.tool_id    = t.tool_id
    JOIN dbo.chambers c ON pr.chamber_id = c.chamber_id
    WHERE t.tool_code = 'ETCH-02' AND c.chamber_code = 'C'
),
cd AS (
    SELECT mm.value,
           CASE WHEN bcw.wafer_id IS NOT NULL THEN 'ETCH-02/C' ELSE 'Others' END AS grp
    FROM dbo.metrology_measurements mm
    JOIN dbo.process_runs pr ON mm.process_run_id = pr.process_run_id
    LEFT JOIN bad_chamber_wafers bcw ON pr.wafer_id = bcw.wafer_id
    WHERE mm.metric_type = 'CD'
),
overall AS (   -- overall CD centre line + sigma, as scalars
    SELECT AVG(value) AS mu, STDEV(value) AS sg FROM cd
)
SELECT
    c.grp,
    COUNT(*)                                        AS readings,
    CAST(AVG(c.value) AS DECIMAL(12,4))             AS group_mean_cd,
    (SELECT CAST(mu AS DECIMAL(12,4)) FROM overall) AS overall_center,
    (SELECT CAST(mu + 3*sg AS DECIMAL(12,4)) FROM overall) AS ucl,
    /* how far the group mean sits above centre, in sigma units (the shift size) */
    CAST( (AVG(c.value) - (SELECT mu FROM overall)) / (SELECT sg FROM overall)
          AS DECIMAL(6,3))                          AS group_mean_shift_in_sigma
FROM cd c
GROUP BY c.grp
ORDER BY c.grp;


/* ---- 3.4c  Per-tool CD centre lines --------------------------------------- */
/* Compute CD mean/sigma WITHIN each tool. ETCH-02's centre line should sit
   above the other etchers, because ~1/3 of its wafers carry the chamber-C drift.
   This is the SPC view of "which tool is shifted". */
WITH cd_by_tool AS (
    SELECT
        t.tool_code,
        mm.value
    FROM dbo.metrology_measurements mm
    JOIN dbo.process_runs pr ON mm.process_run_id = pr.process_run_id
    JOIN dbo.tools t ON pr.tool_id = t.tool_id
    WHERE mm.metric_type = 'CD'
)
SELECT
    tool_code,
    COUNT(*)                                AS readings,
    CAST(AVG(value)   AS DECIMAL(12,4))     AS center_line_cd,
    CAST(STDEV(value) AS DECIMAL(12,4))     AS sigma
FROM cd_by_tool
GROUP BY tool_code
ORDER BY center_line_cd DESC;   -- highest (most shifted) tool first