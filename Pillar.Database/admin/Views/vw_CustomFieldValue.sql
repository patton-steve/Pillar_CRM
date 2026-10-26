-- Custom field values with their field, one row per record per field that has a value. For list pages (join on
-- EntityType + RecordId and pivot the ShowInList fields in the API), search, and reports. Filter on the typed columns;
-- DisplayValue is plain text for printing (dates ISO, yes/no as Yes/No, pick lists as the option label).
CREATE VIEW admin.vw_CustomFieldValue
AS
SELECT v.TenantId, v.EntityType, v.RecordId, v.FieldId, d.FieldKey, d.Label, d.DataType, d.SortOrder, d.ShowInList, d.IsActive,
       v.ValueText, v.ValueInt, v.ValueDecimal, v.ValueDate, v.ValueBit, v.OptionId, o.Label AS OptionLabel,
       CASE d.DataType
           WHEN 'TEXT'    THEN v.ValueText
           WHEN 'INT'     THEN CONVERT(NVARCHAR(400), v.ValueInt)
           WHEN 'DECIMAL' THEN CONVERT(NVARCHAR(400), v.ValueDecimal)
           WHEN 'DATE'    THEN CONVERT(NVARCHAR(400), v.ValueDate, 23)
           WHEN 'BIT'     THEN CASE v.ValueBit WHEN 1 THEN N'Yes' ELSE N'No' END
           WHEN 'LIST'    THEN o.Label
       END AS DisplayValue,
       v.ModifiedAt, v.ModifiedBy
FROM admin.CustomFieldValue AS v
JOIN admin.CustomFieldDefinition AS d ON d.TenantId = v.TenantId AND d.Id = v.FieldId
LEFT JOIN admin.CustomFieldOption AS o ON o.TenantId = v.TenantId AND o.FieldId = v.FieldId AND o.Id = v.OptionId;
