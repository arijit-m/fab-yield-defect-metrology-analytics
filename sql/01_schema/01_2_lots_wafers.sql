/* ============================================================================
   FabYield - Stage 1.2 : Production hierarchy (lots -> wafers)
   ----------------------------------------------------------------------------
   Introduces the schema's first FOREIGN KEY: wafers.lot_id -> lots.lot_id.

   DROP ORDER NOTE: a table cannot be dropped while another table's foreign key
   still points at it. 'wafers' points at 'lots', so we drop the child (wafers) FIRST, 
   then the parent (lots). We CREATE in the opposite order: parent first.
   ============================================================================ */

USE FabYield;
GO


/* Drop children before parents (reverse of create order) so re-running is safe within this stage. 
   Note: once later stages add FKs, generally run each stage once and do not re-run earlier ones. */

   -- Lets first generate wafers
IF OBJECT_ID('dbo.wafers', 'U') IS NOT NULL
    DROP TABLE dbo.wafers;
GO
   -- Now lets generate lots where wafers will be assigned
IF OBJECT_ID('dbo.lots', 'U') IS NOT NULL
    DROP TABLE dbo.lots;
GO


/* ----------------------------------------------------------------------------
   TABLE: lots
   A lot is a batch of wafers (~25) that travels the line together as one unit,
   all of the same product on the same technology node. Product and node live
   HERE so yield can later be sliced by product / node.
   ---------------------------------------------------------------------------- */
CREATE TABLE dbo.lots (
    lot_id          INT           IDENTITY(1,1) NOT NULL,  -- surrogate PK, auto 1,2,3...
    lot_number      NVARCHAR(20)  NOT NULL,                -- business key, e.g. 'LOT-24001'
    product         NVARCHAR(50)  NOT NULL,                -- product name, e.g. 'SoC-A17'
    technology_node NVARCHAR(20)  NOT NULL,                -- '7nm','5nm','3nm'
    planned_qty     INT           NOT NULL                 -- wafers planned in the lot
        CONSTRAINT DF_lots_planned_qty DEFAULT (25),        -- standard cassette = 25
    start_date      DATE          NULL,                    -- when the lot started the line
    status          NVARCHAR(20)  NOT NULL                 -- 'In Process','Completed','Hold','Scrapped'
        CONSTRAINT DF_lots_status DEFAULT ('In Process'),
    CONSTRAINT PK_lots            PRIMARY KEY (lot_id),
    CONSTRAINT UQ_lots_lot_number UNIQUE      (lot_number) -- no duplicate lot numbers
);
GO


/* ----------------------------------------------------------------------------
   TABLE: wafers
   One physical wafer, tied to its lot via lot_id. slot_no is its position (1-25) in the cassette. 
   Every downstream measurement and test traces back
   to a wafer_id, so this is a heavily-referenced table.

   Two natural keys are enforced:
     1) wafer_scribe        - the laser-etched unique wafer ID (real-world key)
     2) (lot_id, slot_no)   - a wafer is also uniquely a slot within a lot
   ---------------------------------------------------------------------------- */
CREATE TABLE dbo.wafers (
    wafer_id     INT          IDENTITY(1,1) NOT NULL,   -- surrogate PK
    wafer_scribe NVARCHAR(30) NOT NULL,                 -- etched wafer ID, e.g. 'LOT-24001.07'
    lot_id       INT          NOT NULL,                 -- FK -> lots.lot_id (which lot this wafer belongs to)
    slot_no      INT          NOT NULL,                 -- position 1-25 in the cassette
    status       NVARCHAR(20) NOT NULL                  -- 'Good','Scrapped','Hold','Engineering'
        CONSTRAINT DF_wafers_status DEFAULT ('Good'),

    CONSTRAINT PK_wafers PRIMARY KEY (wafer_id),

    -- Foreign key: every wafer must reference an existing lot.
    -- Each wafer belongs to a specific lot.
    -- This blocks orphan wafers, and blocks deleting a lot that still has wafers.
    CONSTRAINT FK_wafers_lots
        FOREIGN KEY (lot_id) REFERENCES dbo.lots (lot_id),

    -- The scribe ID is globally unique across all wafers.
    CONSTRAINT UQ_wafers_wafer_scribe UNIQUE (wafer_scribe),

    -- A given slot within a given lot can hold only one wafer.
    CONSTRAINT UQ_wafers_lot_slot UNIQUE (lot_id, slot_no),

    -- Data-quality guard: reject impossible slot numbers (cassette = 25 slots).
    CONSTRAINT CK_wafers_slot_no CHECK (slot_no BETWEEN 1 AND 25)
);
GO