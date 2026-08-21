/* ============================================================================
   FabYield - Stage 2.2 : Seed data - chambers
   ----------------------------------------------------------------------------
   Loads process chambers for the multi-chamber tools (etchers, deposition).
   Scanners / CMP / implant / metrology are modelled as single-chamber tools:
   they get NO chamber rows, and their process_runs carry chamber_id = NULL.

   KEY PATTERN INTRODUCED HERE - "look up the parent's generated ID":
   chambers.tool_id must reference a real tools.tool_id. Those IDs were assigned
   by IDENTITY, so we must NOT hard-code them. Instead each INSERT uses
   INSERT ... SELECT to pull tool_id FROM tools by matching the stable business
   key tool_code. This same pattern drives every generated stage that follows.
   ============================================================================ */

USE FabYield;
GO


/* Clear existing chamber rows so this seed is re-runnable while process_runs
   (the only child of chambers) is still empty. */
DELETE FROM dbo.chambers;
GO


/* ----------------------------------------------------------------------------
   Each block below inserts the chambers for one tool. The SELECT finds that
   tool's IDENTITY-assigned tool_id by its tool_code, and pairs it with each
   chamber_code via a small VALUES list CROSS JOINed to the matched tool row.

   Read the first block slowly - the rest are the same shape:
     - (VALUES ('A'),('B'),('C')) v(chamber_code)  = the chambers we want
     - CROSS JOIN dbo.tools t WHERE t.tool_code=...  = the one parent tool row
     - result: one row per chamber, each carrying the correct tool_id
   ---------------------------------------------------------------------------- */

-- ETCH-01 : chambers A, B, C
INSERT INTO dbo.chambers (tool_id, chamber_code, chamber_name)
SELECT t.tool_id, v.chamber_code, t.tool_name + ' Ch ' + v.chamber_code
FROM dbo.tools t
CROSS JOIN (VALUES ('A'), ('B'), ('C')) AS v(chamber_code)
WHERE t.tool_code = 'ETCH-01';

-- ETCH-02 : chambers A, B, C
INSERT INTO dbo.chambers (tool_id, chamber_code, chamber_name)
SELECT t.tool_id, v.chamber_code, t.tool_name + ' Ch ' + v.chamber_code
FROM dbo.tools t
CROSS JOIN (VALUES ('A'), ('B'), ('C')) AS v(chamber_code)
WHERE t.tool_code = 'ETCH-02';

-- ETCH-03 : chambers A, B (this tool has only two)
INSERT INTO dbo.chambers (tool_id, chamber_code, chamber_name)
SELECT t.tool_id, v.chamber_code, t.tool_name + ' Ch ' + v.chamber_code
FROM dbo.tools t
CROSS JOIN (VALUES ('A'), ('B')) AS v(chamber_code)
WHERE t.tool_code = 'ETCH-03';

-- DEP-01 : chambers A, B, C, D
INSERT INTO dbo.chambers (tool_id, chamber_code, chamber_name)
SELECT t.tool_id, v.chamber_code, t.tool_name + ' Ch ' + v.chamber_code
FROM dbo.tools t
CROSS JOIN (VALUES ('A'), ('B'), ('C'), ('D')) AS v(chamber_code)
WHERE t.tool_code = 'DEP-01';

-- DEP-02 : chambers A, B
INSERT INTO dbo.chambers (tool_id, chamber_code, chamber_name)
SELECT t.tool_id, v.chamber_code, t.tool_name + ' Ch ' + v.chamber_code
FROM dbo.tools t
CROSS JOIN (VALUES ('A'), ('B')) AS v(chamber_code)
WHERE t.tool_code = 'DEP-02';
GO