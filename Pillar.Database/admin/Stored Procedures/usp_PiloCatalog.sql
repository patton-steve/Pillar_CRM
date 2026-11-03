-- What Ask Pilo may query (handoff 24): every rpt view and column with its type and MS_Description, in order. The API builds
-- the model's catalog from it. Runs on the main API connection or on pillar_ai_reader; it returns metadata only.
CREATE PROCEDURE admin.usp_PiloCatalog
AS
BEGIN
    SET NOCOUNT ON;

    SELECT v.name AS ViewName, CONCAT(N'rpt.', v.name) AS QualifiedName, CONVERT(NVARCHAR(1000), vp.value) AS ViewDescription,
           c.column_id AS Ordinal, c.name AS ColumnName,
           CASE WHEN t.name IN (N'nvarchar', N'varchar', N'nchar', N'char')
                THEN CONCAT(t.name, N'(', IIF(c.max_length = -1, N'max', CONVERT(NVARCHAR(10), IIF(t.name LIKE N'n%', c.max_length / 2, c.max_length))), N')')
                WHEN t.name IN (N'decimal', N'numeric') THEN CONCAT(t.name, N'(', c.precision, N',', c.scale, N')')
                ELSE t.name END AS DataType,
           c.is_nullable AS IsNullable, CONVERT(NVARCHAR(1000), cp.value) AS ColumnDescription
    FROM sys.views AS v
    JOIN sys.schemas AS s ON s.schema_id = v.schema_id AND s.name = N'rpt'
    JOIN sys.columns AS c ON c.object_id = v.object_id
    JOIN sys.types AS t ON t.user_type_id = c.user_type_id
    LEFT JOIN sys.extended_properties AS vp ON vp.class = 1 AND vp.major_id = v.object_id AND vp.minor_id = 0 AND vp.name = N'MS_Description'
    LEFT JOIN sys.extended_properties AS cp ON cp.class = 1 AND cp.major_id = v.object_id AND cp.minor_id = c.column_id AND cp.name = N'MS_Description'
    ORDER BY v.name, c.column_id;
END;
