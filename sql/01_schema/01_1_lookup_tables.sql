/* ============================================================================
   FabYield - Stage 1.1 : Foundation / lookup tables
   ----------------------------------------------------------------------------
   These four tables are reference catalogs with NO foreign keys, so they are
   created first. Everything else in the schema will eventually point at them.
   Order within this file does not matter (no dependencies between the four).
   ============================================================================ */

USE FabYield;   -- make sure every object below is created inside our database
GO


/* ----------------------------------------------------------------------------
   TABLE: tools
   Physical fab equipment: scanners, etchers, CMP tools, inspection tools, etc.
   A single tool can contain multiple process chambers (handled later in 1.3).
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.tools', 'U') IS NOT NULL   -- 'U' = user table; guard for re-runs
    DROP TABLE dbo.tools;
GO

CREATE TABLE dbo.tools (
    tool_id       INT           IDENTITY(1,1) NOT NULL,  -- surrogate PK, auto 1,2,3...
    tool_code     NVARCHAR(20)  NOT NULL,                -- business key, e.g. 'LITHO-01'
    tool_name     NVARCHAR(100) NULL,                    -- friendly name, optional
    tool_type     NVARCHAR(50)  NOT NULL,                -- 'Scanner','Etcher','CMP','Inspection','CD-SEM'
    manufacturer  NVARCHAR(50)  NULL,                    -- 'ASML','Applied Materials','TEL','KLA'
    model         NVARCHAR(50)  NULL,                    -- tool model designation
    install_date  DATE          NULL,                    -- when the tool went online
    is_active     BIT           NOT NULL
        CONSTRAINT DF_tools_is_active DEFAULT (1),        -- default: tool is in service
    CONSTRAINT PK_tools           PRIMARY KEY (tool_id),
    CONSTRAINT UQ_tools_tool_code UNIQUE      (tool_code) -- no duplicate tool codes
);
GO


/* ----------------------------------------------------------------------------
   TABLE: process_steps
   The catalog of fab operations (the route/recipe steps a wafer goes through):
   litho expose, etch, deposition, CMP, implant, metrology, etc.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.process_steps', 'U') IS NOT NULL
    DROP TABLE dbo.process_steps;
GO

CREATE TABLE dbo.process_steps (
    process_step_id INT           IDENTITY(1,1) NOT NULL, -- surrogate PK
    step_code       NVARCHAR(20)  NOT NULL,               -- business key, e.g. 'LITHO-100'
    step_name       NVARCHAR(100) NOT NULL,               -- 'Gate Litho Expose'
    process_module  NVARCHAR(50)  NOT NULL,               -- 'Lithography','Etch','Deposition','CMP','Implant','Metrology'
    sequence_order  INT           NULL,                   -- nominal position in the process flow
    description     NVARCHAR(255) NULL,
    CONSTRAINT PK_process_steps            PRIMARY KEY (process_step_id),
    CONSTRAINT UQ_process_steps_step_code  UNIQUE      (step_code)
);
GO


/* ----------------------------------------------------------------------------
   TABLE: defect_types
   Classification catalog for defects found during inspection.
   'is_killer' distinguishes yield-killing defects from nuisance defects.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.defect_types', 'U') IS NOT NULL
    DROP TABLE dbo.defect_types;
GO

CREATE TABLE dbo.defect_types (
    defect_type_id     INT           IDENTITY(1,1) NOT NULL,  -- surrogate PK
    defect_code        NVARCHAR(20)  NOT NULL,                -- 'PART','SCRATCH','BRIDGE'
    defect_name        NVARCHAR(100) NOT NULL,                -- 'Particle','Scratch','Bridge'
    category           NVARCHAR(50)  NOT NULL,                -- 'Particle','Pattern','Contamination','Mechanical'
    is_killer          BIT           NOT NULL
        CONSTRAINT DF_defect_types_is_killer DEFAULT (0),      -- default: treat as nuisance until classified
    typical_root_cause NVARCHAR(255) NULL,
    description        NVARCHAR(255) NULL,
    CONSTRAINT PK_defect_types              PRIMARY KEY (defect_type_id),
    CONSTRAINT UQ_defect_types_defect_code  UNIQUE      (defect_code)
);
GO


/* ----------------------------------------------------------------------------
   TABLE: bin_codes
   Catalog of sort/test bins used to classify each die at electrical test.
   Bin 1 is conventionally 'Pass'; higher bins are various failure modes.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.bin_codes', 'U') IS NOT NULL
    DROP TABLE dbo.bin_codes;
GO

CREATE TABLE dbo.bin_codes (
    bin_code_id   INT           IDENTITY(1,1) NOT NULL,   -- surrogate PK
    bin_number    INT           NOT NULL,                 -- numeric bin as reported by the tester/sort
    bin_name      NVARCHAR(100) NOT NULL,                 -- 'Pass','Open','Short','Speed Fail'
    bin_category  NVARCHAR(50)  NOT NULL,                 -- 'Pass','Hard Fail','Parametric Fail'
    is_pass       BIT           NOT NULL
        CONSTRAINT DF_bin_codes_is_pass DEFAULT (0),       -- default: fail unless marked pass
    description   NVARCHAR(255) NULL,
    CONSTRAINT PK_bin_codes             PRIMARY KEY (bin_code_id),
    CONSTRAINT UQ_bin_codes_bin_number  UNIQUE      (bin_number)
);
GO