/* ============================================================================
   FabYield - Stage 2.5a : Utility - reusable numbers (tally) table
   ----------------------------------------------------------------------------
   A "tally table" is a permanent helper holding the integers 1..N and nothing
   else. It is the standard set-based tool for EXPANDING a count into rows:
   to turn "this wafer has 5 defects" into 5 rows, we JOIN to this table and
   keep rows where n <= 5. No loops, no recursion, no MAXRECURSION ceiling.

   Built ONCE here, reused in 2.5b (defects), 2.6 (dies), 2.7 (measurements).

   HOW IT'S FILLED: cross-joining a system catalog view to itself produces many
   rows cheaply; ROW_NUMBER() numbers them 1..N. sys.all_objects has hundreds
   of rows, so its cross join yields tens of thousands - we cap at 10,000 with
   TOP, which is more than any per-wafer count we will ever expand.
   ============================================================================ */

USE FabYield;
GO


/* This IS a table we can drop safely - nothing references it with a foreign
   key; it is a standalone utility. Safe to re-run. */
IF OBJECT_ID('dbo.numbers', 'U') IS NOT NULL
    DROP TABLE dbo.numbers;
GO

CREATE TABLE dbo.numbers (
    n INT NOT NULL,
    CONSTRAINT PK_numbers PRIMARY KEY (n)   -- PK also indexes it for fast joins
);
GO


/* Fill 1..10000. ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) just numbers the
   cross-joined rows in arbitrary order - we don't care about order, only that
   we get 1,2,3,...  TOP (10000) caps how many we keep. */
INSERT INTO dbo.numbers (n)
SELECT TOP (10000)
       ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;   -- self cross join = plenty of raw rows
GO