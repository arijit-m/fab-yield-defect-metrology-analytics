/* ============================================================================
   FabYield - Stage 1.3 : Equipment detail (chambers under tools)
   ----------------------------------------------------------------------------
   Adds the FK chambers.tool_id -> tools.tool_id. A tool can hold many chambers;
   each chamber belongs to exactly one tool.

   WHY THIS TABLE MATTERS: in commonality analysis the CHAMBER is usually the
   real root cause. A tool can look fine while one chamber runs bad. Keeping
   chambers as their own rows (not a text field on tools) is what lets a query
   trace a set of failing wafers down to the exact chamber they shared.

   NOTE: this script creates ONLY 'chambers'. It does not touch 'tools' (built
   in Stage 1.1). This is the "run each stage once, don't re-run earlier ones"
   rule in practice - we never re-drop a table that later tables depend on.
   ============================================================================ */

USE FabYield;
GO


/* 'chambers' has no children yet, so we only need to drop chambers itself. */
IF OBJECT_ID('dbo.chambers', 'U') IS NOT NULL
    DROP TABLE dbo.chambers;
GO


/* ----------------------------------------------------------------------------
   TABLE: chambers
   A process chamber inside a tool. Many tools have multiple chambers, and the
   chamber is the finest-grained piece of equipment we tie a process run to.
   ---------------------------------------------------------------------------- */
CREATE TABLE dbo.chambers (
    chamber_id   INT          IDENTITY(1,1) NOT NULL,   -- surrogate PK, auto 1,2,3...
    tool_id      INT          NOT NULL,                 -- FK -> tools.tool_id (which tool this chamber sits in)
    chamber_code NVARCHAR(10) NOT NULL,                 -- position within the tool, e.g. 'A','B','C','PM1'
    chamber_name NVARCHAR(100) NULL,                    -- optional friendly label
    is_active    BIT          NOT NULL
        CONSTRAINT DF_chambers_is_active DEFAULT (1),    -- default: chamber is in service

    CONSTRAINT PK_chambers PRIMARY KEY (chamber_id),

    -- Foreign key: every chamber must belong to an existing tool. Blocks orphan
    -- chambers, and blocks deleting a tool that still has chambers under it.
    CONSTRAINT FK_chambers_tools
        FOREIGN KEY (tool_id) REFERENCES dbo.tools (tool_id),

    -- Natural key spans BOTH columns: chamber 'A' is only unique within a
    -- tool, since almost every multi-chamber tool has an 'A'. (Same idea as
    -- (lot_id, slot_no) on wafers.)
    CONSTRAINT UQ_chambers_tool_chamber UNIQUE (tool_id, chamber_code)
);
GO