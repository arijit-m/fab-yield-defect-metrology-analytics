/* ============================================================================
   FabYield - Stage 1.4 : Event / transaction tables
   ----------------------------------------------------------------------------
   These tables record EVENTS (things that happened to a wafer), unlike the
   catalog and hierarchy tables built so far. We create them one at a time:
       1.4a  process_runs        (this message)
       1.4b  defect_inspections
       1.4c  bin_results
   All three live in this one file: 01_4_event_tables.sql
   ============================================================================ */

USE FabYield;
GO


/* ----------------------------------------------------------------------------
   1.4a  TABLE: process_runs
   THE central fact table. One row = one wafer passing through one process step,
   on one tool, (optionally) in one chamber, at one point in time.

   This is what makes COMMONALITY ANALYSIS possible: given a set of failing
   wafers, join through process_runs to find the tool/chamber they all shared.

   FOUR foreign keys - one per noun in "this wafer went through this step on
   this tool in this chamber":
       wafer_id        -> wafers
       process_step_id -> process_steps
       tool_id         -> tools
       chamber_id      -> chambers   (NULLABLE - not every tool has chambers)
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.process_runs', 'U') IS NOT NULL
    DROP TABLE dbo.process_runs;
GO

CREATE TABLE dbo.process_runs (
    process_run_id  INT       IDENTITY(1,1) NOT NULL,   -- surrogate PK
    wafer_id        INT       NOT NULL,                 -- FK -> wafers (which wafer)
    process_step_id INT       NOT NULL,                 -- FK -> process_steps (which operation)
    tool_id         INT       NOT NULL,                 -- FK -> tools (which equipment)
    chamber_id      INT       NULL,                     -- FK -> chambers (which chamber, if any)
    run_start       DATETIME2 NOT NULL,                 -- when the run began (date + time)
    run_end         DATETIME2 NULL,                     -- when it finished (NULL while in progress)
    run_status      NVARCHAR(20) NOT NULL               -- 'Completed','Aborted','Rework'
        CONSTRAINT DF_process_runs_run_status DEFAULT ('Completed'),

    CONSTRAINT PK_process_runs PRIMARY KEY (process_run_id),

    -- One FK per link. Each guarantees the referenced parent row exists.
    CONSTRAINT FK_process_runs_wafers
        FOREIGN KEY (wafer_id)        REFERENCES dbo.wafers (wafer_id),
    CONSTRAINT FK_process_runs_steps
        FOREIGN KEY (process_step_id) REFERENCES dbo.process_steps (process_step_id),
    CONSTRAINT FK_process_runs_tools
        FOREIGN KEY (tool_id)         REFERENCES dbo.tools (tool_id),
    CONSTRAINT FK_process_runs_chambers
        FOREIGN KEY (chamber_id)      REFERENCES dbo.chambers (chamber_id)
);
GO

/* ----------------------------------------------------------------------------
   1.4b  TABLE: defect_inspections
   One row = one inspection EVENT on one wafer: on this date, using this
   inspection tool, we scanned the wafer and found 'defect_count' defects.

   This is the HEADER. The individual defects found in this inspection are
   listed in the 'defects' table (Stage 1.5), each pointing back here.

   Storing defect_count here (the tool's reported total) lets us later
   cross-check it against the number of detailed rows in 'defects'.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.defect_inspections', 'U') IS NOT NULL
    DROP TABLE dbo.defect_inspections;
GO

CREATE TABLE dbo.defect_inspections (
    inspection_id   INT       IDENTITY(1,1) NOT NULL,   -- surrogate PK
    wafer_id        INT       NOT NULL,                 -- FK -> wafers (which wafer was inspected)
    tool_id         INT       NOT NULL,                 -- FK -> tools (which inspection tool)
    inspection_date DATETIME2 NOT NULL,                 -- when the inspection happened
    inspection_step NVARCHAR(50) NULL,                  -- where in the flow, e.g. 'Post-Etch','Post-Litho'
    defect_count    INT       NOT NULL                  -- total defects the tool reported
        CONSTRAINT DF_defect_inspections_defect_count DEFAULT (0),

    CONSTRAINT PK_defect_inspections PRIMARY KEY (inspection_id),

    -- Which wafer was inspected (required).
    CONSTRAINT FK_defect_inspections_wafers
        FOREIGN KEY (wafer_id) REFERENCES dbo.wafers (wafer_id),

    -- Which inspection tool did the scan (required).
    CONSTRAINT FK_defect_inspections_tools
        FOREIGN KEY (tool_id)  REFERENCES dbo.tools (tool_id),

    -- Data-quality guard: a defect count can never be negative.
    CONSTRAINT CK_defect_inspections_count CHECK (defect_count >= 0)
);
GO

/* ----------------------------------------------------------------------------
   1.4c  TABLE: bin_results
   Die-level final electrical test. One row = one die on one wafer, and the
   bin it sorted into. 'bin_codes' (Stage 1.1) says whether that bin is a pass
   or a specific failure mode.

   YIELD comes from here: pass dies / total dies. This is the outcome number
   every other table gets correlated against.

   NAMING NOTE: the narrative calls a die's result its "bin_code", but the FK
   column is 'bin_code_id' -> bin_codes.bin_code_id. Same idea: "bin_code" is
   the human concept, 'bin_code_id' is the surrogate key that stores the link.

   CROSS-PROJECT NOTE: (die_x, die_y, bin) is the same shape the Python
   wafer-map defect-classification project consumes - this table bridges the
   SQL and ML halves of the portfolio.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.bin_results', 'U') IS NOT NULL
    DROP TABLE dbo.bin_results;
GO

CREATE TABLE dbo.bin_results (
    bin_result_id INT NOT NULL IDENTITY(1,1),           -- surrogate PK
    wafer_id      INT NOT NULL,                          -- FK -> wafers (which wafer this die is on)
    bin_code_id   INT NOT NULL,                          -- FK -> bin_codes (the die's test result)
    die_x         INT NOT NULL,                          -- die column position on the wafer
    die_y         INT NOT NULL,                          -- die row position on the wafer

    CONSTRAINT PK_bin_results PRIMARY KEY (bin_result_id),

    -- Which wafer this die belongs to (required).
    CONSTRAINT FK_bin_results_wafers
        FOREIGN KEY (wafer_id)    REFERENCES dbo.wafers (wafer_id),

    -- What test result the die got (required).
    CONSTRAINT FK_bin_results_bin_codes
        FOREIGN KEY (bin_code_id) REFERENCES dbo.bin_codes (bin_code_id),

    -- One die per (wafer, x, y): no two dies share a coordinate on a wafer.
    CONSTRAINT UQ_bin_results_wafer_die UNIQUE (wafer_id, die_x, die_y)
);
GO