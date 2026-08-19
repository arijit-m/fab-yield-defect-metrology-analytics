/* ============================================================================
   FabYield - Stage 1.5 : Leaf detail tables (metrology_measurements, defects)
   ----------------------------------------------------------------------------
   The finest-grained tables in the schema. Each row hangs off an EVENT row
   created in Stage 1.4:
       metrology_measurements -> process_runs        (one measurement per run)
       defects                -> defect_inspections  (one defect per inspection)
   Creating these completes the 12-table schema.
   ============================================================================ */

USE FabYield;
GO


/* ----------------------------------------------------------------------------
   TABLE: metrology_measurements
   One row = one metrology reading taken during a process run: a CD, an overlay,
   a film thickness, etc. Each has a measured 'value' vs its 'target', plus
   optional spec limits. This is the raw material for SPC / control-chart queries.

   It links to process_runs only. Because a run already knows its wafer, tool,
   chamber and step, every measurement inherits all that context through that
   single FK - no need to repeat those columns here.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.metrology_measurements', 'U') IS NOT NULL
    DROP TABLE dbo.metrology_measurements;
GO

CREATE TABLE dbo.metrology_measurements (
    measurement_id  INT           IDENTITY(1,1) NOT NULL,  -- surrogate PK
    process_run_id  INT           NOT NULL,                -- FK -> process_runs (which run produced this reading)
    metric_type     NVARCHAR(30)  NOT NULL,                -- 'CD','Overlay','Film Thickness','Sheet Resistance'
    value           DECIMAL(12,4) NOT NULL,                -- the measured value
    target          DECIMAL(12,4) NULL,                    -- nominal target for this metric
    spec_low        DECIMAL(12,4) NULL,                    -- lower spec limit (NULL if a monitor w/o limits)
    spec_high       DECIMAL(12,4) NULL,                    -- upper spec limit
    unit            NVARCHAR(15)  NULL,                     -- 'nm','A','ohm/sq' - the unit of 'value'
    measured_at     DATETIME2     NULL,                     -- when the reading was taken

    CONSTRAINT PK_metrology_measurements PRIMARY KEY (measurement_id),

    -- Every measurement belongs to exactly one process run.
    CONSTRAINT FK_metrology_measurements_runs
        FOREIGN KEY (process_run_id) REFERENCES dbo.process_runs (process_run_id),

    -- Data-quality guard: if BOTH limits are given, low must not exceed high.
    -- (When either is NULL the check passes - partial limits are allowed.)
    CONSTRAINT CK_metrology_measurements_spec
        CHECK (spec_low IS NULL OR spec_high IS NULL OR spec_low <= spec_high)
);
GO


/* ----------------------------------------------------------------------------
   TABLE: defects
   One row = one individual defect found during an inspection. This breaks a
   defect_inspection's total 'defect_count' into its constituent defects, each
   classified by a defect_type. This is what powers the defect PARETO
   ("which defect type drives the most loss").

   Two foreign keys:
       inspection_id  -> defect_inspections (which inspection found it)
       defect_type_id -> defect_types       (what kind of defect it is)

   Location uses continuous micrometre coordinates (x_um, y_um) because a defect
   can sit anywhere on the wafer - unlike bin_results' integer die grid.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.defects', 'U') IS NOT NULL
    DROP TABLE dbo.defects;
GO

CREATE TABLE dbo.defects (
    defect_id      INT           IDENTITY(1,1) NOT NULL,   -- surrogate PK
    inspection_id  INT           NOT NULL,                 -- FK -> defect_inspections (which inspection found it)
    defect_type_id INT           NOT NULL,                 -- FK -> defect_types (what kind it is)
    x_um           DECIMAL(12,4) NULL,                     -- defect X location on wafer, micrometres
    y_um           DECIMAL(12,4) NULL,                     -- defect Y location on wafer, micrometres
    defect_size_um DECIMAL(10,4) NULL,                     -- defect size in micrometres (NULL if not sized)

    CONSTRAINT PK_defects PRIMARY KEY (defect_id),

    -- Which inspection event found this defect (required).
    CONSTRAINT FK_defects_inspections
        FOREIGN KEY (inspection_id)  REFERENCES dbo.defect_inspections (inspection_id),

    -- What type of defect it is (required).
    CONSTRAINT FK_defects_defect_types
        FOREIGN KEY (defect_type_id) REFERENCES dbo.defect_types (defect_type_id),

    -- Data-quality guard: a physical size can't be negative.
    CONSTRAINT CK_defects_size CHECK (defect_size_um IS NULL OR defect_size_um >= 0)
);
GO