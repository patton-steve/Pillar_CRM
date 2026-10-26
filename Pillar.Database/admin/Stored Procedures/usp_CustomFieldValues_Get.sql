-- The "Custom fields" section of a record page: every active field for @EntityType in display order, with this record's
-- value (NULL when blank). No rows means the tenant has no fields for this record type, so the page hides the section.
-- @RecordId NULL returns the empty form for a new record. Options is a JSON array of a LIST field's active choices
-- ([{"id": 4, "label": "Renewal"}]), plus the record's current choice if it has since been retired.
-- Needs the record type's view permission (client.view, project.view or ap.view).
CREATE PROCEDURE admin.usp_CustomFieldValues_Get
    @EntityType     VARCHAR(20),
    @RecordId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    SET @EntityType = UPPER(@EntityType);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51201, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId,
                       CASE WHEN @EntityType = 'CLIENT' OR @EntityType = 'CONTACT' THEN 'client.view'
                            WHEN @EntityType = 'PROJECT' OR @EntityType = 'TASK' THEN 'project.view'
                            ELSE 'ap.view' END))
        THROW 51219, N'You don''t have access to this record.', 1;
    IF @RecordId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admin.fn_CustomFieldRecordExists(@TenantId, @EntityType, @RecordId))
        THROW 51213, N'Record not found.', 1;

    SELECT d.Id AS FieldId, d.FieldKey, d.Label, d.DataType, d.MaxLength, d.IsRequired, d.HelpText, d.SortOrder, d.ShowInList,
           v.ValueText, v.ValueInt, v.ValueDecimal, v.ValueDate, v.ValueBit, v.OptionId,
           CASE d.DataType
               WHEN 'TEXT'    THEN v.ValueText
               WHEN 'INT'     THEN CONVERT(NVARCHAR(400), v.ValueInt)
               WHEN 'DECIMAL' THEN CONVERT(NVARCHAR(400), v.ValueDecimal)
               WHEN 'DATE'    THEN CONVERT(NVARCHAR(400), v.ValueDate, 23)
               WHEN 'BIT'     THEN CASE v.ValueBit WHEN 1 THEN N'Yes' WHEN 0 THEN N'No' END
               WHEN 'LIST'    THEN (SELECT o.Label FROM admin.CustomFieldOption AS o
                                    WHERE o.TenantId = v.TenantId AND o.FieldId = v.FieldId AND o.Id = v.OptionId)
           END AS DisplayValue,
           CASE WHEN d.DataType = 'LIST' THEN
               (SELECT o.Id AS id, o.Label AS label
                FROM admin.CustomFieldOption AS o
                WHERE o.TenantId = d.TenantId AND o.FieldId = d.Id AND (o.IsActive = 1 OR o.Id = v.OptionId)
                ORDER BY o.SortOrder, o.Id
                FOR JSON PATH)
           END AS Options
    FROM admin.CustomFieldDefinition AS d
    LEFT JOIN admin.CustomFieldValue AS v
        ON v.TenantId = d.TenantId AND v.EntityType = d.EntityType AND v.FieldId = d.Id AND v.RecordId = @RecordId
    WHERE d.TenantId = @TenantId AND d.EntityType = @EntityType AND d.IsActive = 1
    ORDER BY d.SortOrder, d.Id;
END;
