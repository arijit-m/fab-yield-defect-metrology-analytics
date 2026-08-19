/* ============================================================================
   FabYield - Stage 2.1 : Seed data - reference lookups
   ----------------------------------------------------------------------------
   Loads the four catalog tables that everything else points at. No foreign
   keys among them, so order here does not matter. These are the CONTROLLED
   VOCABULARY of the fab - named, realistic, hand-written (not generated).

   RE-RUNNABLE: each table is cleared with DELETE first, so you can run this
   script repeatedly WHILE later (child) tables are still empty. Once Stage 2.2+
   load data, re-seeding requires clearing children first (master script later).
   ============================================================================ */

USE FabYield;
GO


/* Clear existing rows so this seed is idempotent (safe to re-run for now). */
DELETE FROM dbo.bin_codes;
DELETE FROM dbo.defect_types;
DELETE FROM dbo.process_steps;
DELETE FROM dbo.tools;
GO


/* ----------------------------------------------------------------------------
   tools : the physical equipment. Multiple etchers and scanners on purpose -
   commonality analysis can only find a "bad tool/chamber" if there are peers
   to compare against. is_active defaults to 1, so we omit it here.
   ---------------------------------------------------------------------------- */
INSERT INTO dbo.tools (tool_code, tool_name, tool_type, manufacturer, model, install_date)
VALUES
    ('LITHO-01', 'Litho Scanner 1', 'Scanner',    'ASML',              'NXE:3400', '2021-03-15'),
    ('LITHO-02', 'Litho Scanner 2', 'Scanner',    'ASML',              'NXE:3400', '2021-06-20'),
    ('ETCH-01',  'Etcher 1',        'Etcher',     'Lam Research',      'Kiyo',     '2020-11-01'),
    ('ETCH-02',  'Etcher 2',        'Etcher',     'TEL',              'Tactras',  '2021-01-10'),
    ('ETCH-03',  'Etcher 3',        'Etcher',     'Applied Materials', 'Centris',  '2021-09-05'),
    ('DEP-01',   'Deposition 1',    'Deposition', 'Applied Materials', 'Producer', '2020-08-12'),
    ('DEP-02',   'Deposition 2',    'Deposition', 'TEL',              'Trias',    '2021-02-18'),
    ('CMP-01',   'CMP 1',           'CMP',        'Applied Materials', 'Reflexion','2020-10-22'),
    ('IMP-01',   'Implanter 1',     'Implant',    'Applied Materials', 'VIISta',   '2020-07-30'),
    ('CDSEM-01', 'CD-SEM 1',        'CD-SEM',     'Hitachi',           'CG6300',   '2021-04-01'),
    ('OVL-01',   'Overlay Tool 1',  'Metrology',  'KLA',               'Archer',   '2021-04-01'),
    ('INSP-01',  'Inspector 1',     'Inspection', 'KLA',               '2935',     '2021-05-14'),
    ('INSP-02',  'Inspector 2',     'Inspection', 'Applied Materials', 'SEMVision','2021-07-19');
GO


/* ----------------------------------------------------------------------------
   process_steps : a small but coherent front-to-back-of-line flow.
   sequence_order gives nominal route order (used later to order a wafer's runs).
   ---------------------------------------------------------------------------- */
INSERT INTO dbo.process_steps (step_code, step_name, process_module, sequence_order, description)
VALUES
    ('DEP-100',   'STI Oxide Deposition',    'Deposition',   10, 'Shallow trench isolation fill'),
    ('CMP-100',   'STI CMP',                 'CMP',          20, 'Planarize STI oxide'),
    ('IMP-100',   'Well Implant',            'Implant',      30, 'Well / channel doping'),
    ('LITHO-100', 'Gate Litho Expose',       'Lithography',  40, 'Gate layer exposure'),
    ('ETCH-100',  'Gate Etch',               'Etch',         50, 'Gate pattern etch'),
    ('LITHO-200', 'Metal-1 Litho Expose',    'Lithography',  60, 'Metal-1 layer exposure'),
    ('ETCH-200',  'Metal-1 Etch',            'Etch',         70, 'Metal-1 pattern etch'),
    ('DEP-200',   'Metal-1 Deposition',      'Deposition',   80, 'Metal-1 fill'),
    ('CMP-200',   'Metal-1 CMP',             'CMP',          90, 'Planarize metal-1'),
    ('METR-100',  'CD / Overlay Metrology',  'Metrology',   100, 'Post-litho CD and overlay measure');
GO


/* ----------------------------------------------------------------------------
   defect_types : classification catalog. is_killer varies per row (it drives
   the Pareto later), so it is specified explicitly.
   ---------------------------------------------------------------------------- */
INSERT INTO dbo.defect_types (defect_code, defect_name, category, is_killer, typical_root_cause)
VALUES
    ('PART',    'Particle',      'Particle',      1, 'Chamber contamination'),
    ('SCRATCH', 'Scratch',       'Mechanical',    1, 'Wafer handling / CMP'),
    ('BRIDGE',  'Bridge',        'Pattern',       1, 'Litho focus / etch profile'),
    ('OPEN',    'Open',          'Pattern',       1, 'Etch residue / underetch'),
    ('RESIDUE', 'Residue',       'Contamination', 0, 'Incomplete etch clean'),
    ('VOID',    'Void',          'Pattern',       1, 'Deposition void'),
    ('CONTAM',  'Contamination', 'Contamination', 0, 'Clean process excursion'),
    ('FLAKE',   'Flake',         'Particle',      0, 'Chamber wall flaking');
GO


/* ----------------------------------------------------------------------------
   bin_codes : sort/test bins. is_pass varies (bin 1 is the only pass) and is
   the column the YIELD calculation keys off, so it is specified explicitly.
   ---------------------------------------------------------------------------- */
INSERT INTO dbo.bin_codes (bin_number, bin_name, bin_category, is_pass)
VALUES
    (1, 'Pass',        'Pass',            1),
    (2, 'Open',        'Hard Fail',       0),
    (3, 'Short',       'Hard Fail',       0),
    (4, 'Speed Fail',  'Parametric Fail', 0),
    (5, 'Leakage',     'Parametric Fail', 0),
    (6, 'IDDQ',        'Parametric Fail', 0),
    (7, 'Gross Fail',  'Hard Fail',       0),
    (8, 'Functional',  'Hard Fail',       0);
GO