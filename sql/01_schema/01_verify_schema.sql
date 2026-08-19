USE FabYield;
GO

/* ---- Count 1: all 12 tables should be listed ---- */
SELECT name AS table_name
FROM sys.tables
ORDER BY name;

/* ---- Count 2: every foreign key in the database, child -> parent ---- */
SELECT fk.name  AS fk_name,
       tp.name  AS child_table,
       ref.name AS parent_table
FROM sys.foreign_keys fk
JOIN sys.tables tp  ON fk.parent_object_id     = tp.object_id
JOIN sys.tables ref ON fk.referenced_object_id = ref.object_id
ORDER BY tp.name, ref.name;

/* ---- Count 3: quick totals ---- */
SELECT
    (SELECT COUNT(*) FROM sys.tables)       AS table_count,
    (SELECT COUNT(*) FROM sys.foreign_keys) AS fk_count;