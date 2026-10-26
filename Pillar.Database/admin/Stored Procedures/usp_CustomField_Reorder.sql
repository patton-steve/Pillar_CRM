-- Saves the drag order of one record type's custom fields (needs settings.custom_fields). @FieldIds is a JSON array of field ids
-- in the new order, e.g. [7, 3, 9]; fields left out keep their place after the listed ones.
CREATE PROCEDURE admin.usp_CustomField_Reorder
    @EntityType     VARCHAR(20),
    @FieldIds       NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51201, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.custom_fields'))
        THROW 51202, N'You need permission to change settings to manage custom fields.', 1;
    IF ISJSON(@FieldIds) = 0 THROW 51211, N'Field order must be a JSON array of field ids.', 1;

    WITH ordered AS (
        SELECT d.Id, ROW_NUMBER() OVER (ORDER BY CASE WHEN j.[key] IS NULL THEN 1 ELSE 0 END,
                                                 CONVERT(INT, j.[key]), d.SortOrder, d.Id) AS Seq
        FROM admin.CustomFieldDefinition AS d
        LEFT JOIN OPENJSON(@FieldIds) AS j ON TRY_CONVERT(INT, j.value) = d.Id
        WHERE d.TenantId = @TenantId AND d.EntityType = UPPER(@EntityType))
    UPDATE d SET SortOrder = o.Seq * 10, ModifiedAt = SYSUTCDATETIME(), ModifiedBy = @UserId
    FROM admin.CustomFieldDefinition AS d JOIN ordered AS o ON o.Id = d.Id
    WHERE d.TenantId = @TenantId AND d.SortOrder <> o.Seq * 10;

    EXEC admin.usp_Audit_Write @Area = 'custom_fields', @EntityType = 'CUSTOM_FIELD', @Action = 'UPDATE',
         @Summary = N'Reordered custom fields', @ChangeJson = @FieldIds;
END;
