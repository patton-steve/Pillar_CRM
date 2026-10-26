-- Saves a record's custom field values from its page. @Values is a JSON object keyed by FieldKey; only the keys sent are
-- changed, and null or "" clears a value:
--   {"po_reference": "A-1207", "seats": 12, "budget_code": 4.5, "go_live": "2026-11-01", "signed": true, "deal_type": 4}
-- Types: TEXT string (up to MaxLength), INT whole number, DECIMAL number (numbers may also come as strings), DATE "yyyy-mm-dd", BIT true/false,
-- LIST the option id. After saving, every active required field must have a value, so a new record's first save sends
-- them all, and a field made required later is filled in the next time that record's fields are saved.
-- Needs the record type's edit permission (client.edit, project.edit, task.edit or ap.enter).
CREATE PROCEDURE admin.usp_CustomFieldValues_Save
    @EntityType     VARCHAR(20),
    @RecordId       INT,
    @Values         NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @Msg NVARCHAR(2048);
    SET @EntityType = UPPER(@EntityType);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51201, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId,
                       CASE @EntityType WHEN 'CLIENT' THEN 'client.edit' WHEN 'CONTACT' THEN 'client.edit'
                                        WHEN 'PROJECT' THEN 'project.edit' WHEN 'TASK' THEN 'task.edit' ELSE 'ap.enter' END))
        THROW 51220, N'You don''t have permission to edit this record.', 1;
    IF ISJSON(@Values) = 0 OR LEFT(LTRIM(@Values), 1) <> N'{'
        THROW 51212, N'Custom field values must be a JSON object keyed by field key.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.fn_CustomFieldRecordExists(@TenantId, @EntityType, @RecordId))
        THROW 51213, N'Record not found.', 1;

    CREATE TABLE #v (
        FieldId INT NULL, FieldKey NVARCHAR(4000) NOT NULL, Label NVARCHAR(100) NULL, DataType VARCHAR(10) NULL, MaxLength INT NULL,
        Raw NVARCHAR(MAX) NULL, JType INT NOT NULL, IsBlank BIT NOT NULL,
        ValueText NVARCHAR(MAX) NULL, ValueInt BIGINT NULL, ValueDecimal DECIMAL(19,4) NULL, ValueDate DATE NULL,
        ValueBit BIT NULL, OptionId INT NULL);

    INSERT INTO #v (FieldId, FieldKey, Label, DataType, MaxLength, Raw, JType, IsBlank)
    SELECT d.Id, j.[key], d.Label, d.DataType, d.MaxLength, j.value, j.[type],
           CASE WHEN j.[type] = 0 OR (j.[type] = 1 AND LTRIM(RTRIM(j.value)) = N'') THEN 1 ELSE 0 END
    FROM OPENJSON(@Values) AS j
    LEFT JOIN admin.CustomFieldDefinition AS d
        ON d.TenantId = @TenantId AND d.EntityType = @EntityType AND d.FieldKey = j.[key] COLLATE DATABASE_DEFAULT AND d.IsActive = 1;

    SELECT TOP (1) @Msg = CONCAT(N'"', FieldKey, N'" is not a custom field on this record.') FROM #v WHERE FieldId IS NULL;
    IF @Msg IS NOT NULL THROW 51214, @Msg, 1;
    IF EXISTS (SELECT 1 FROM #v GROUP BY FieldId HAVING COUNT(*) > 1)
        THROW 51212, N'Custom field values must be a JSON object keyed by field key.', 1;

    UPDATE #v SET
        ValueText    = CASE WHEN DataType = 'TEXT' AND JType = 1 THEN LTRIM(RTRIM(Raw)) END,
        ValueInt     = CASE WHEN DataType = 'INT' AND (JType = 1 OR JType = 2) THEN TRY_CONVERT(BIGINT, Raw) END,
        ValueDecimal = CASE WHEN DataType = 'DECIMAL' AND (JType = 1 OR JType = 2) THEN TRY_CONVERT(DECIMAL(19,4), Raw) END,
        ValueDate    = CASE WHEN DataType = 'DATE' AND JType = 1 AND Raw LIKE '[12][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]'
                            THEN TRY_CONVERT(DATE, Raw, 23) END,
        ValueBit     = CASE WHEN DataType = 'BIT' AND JType = 3 THEN CASE Raw WHEN 'true' THEN 1 ELSE 0 END END,
        OptionId     = CASE WHEN DataType = 'LIST' AND (JType = 1 OR JType = 2) THEN TRY_CONVERT(INT, Raw) END
    WHERE IsBlank = 0;

    SELECT TOP (1) @Msg = CONCAT(Label, N': ',
        CASE DataType WHEN 'TEXT' THEN N'enter text.' WHEN 'INT' THEN N'enter a whole number.' WHEN 'DECIMAL' THEN N'enter a number.'
                      WHEN 'DATE' THEN N'enter a date (yyyy-mm-dd).' WHEN 'BIT' THEN N'choose yes or no.' ELSE N'choose one of the options.' END)
    FROM #v
    WHERE IsBlank = 0 AND ValueText IS NULL AND ValueInt IS NULL AND ValueDecimal IS NULL AND ValueDate IS NULL
      AND ValueBit IS NULL AND OptionId IS NULL;
    IF @Msg IS NOT NULL THROW 51215, @Msg, 1;

    SELECT TOP (1) @Msg = CONCAT(Label, N': keep it to ', MaxLength, N' characters.') FROM #v WHERE LEN(ValueText) > MaxLength;
    IF @Msg IS NOT NULL THROW 51216, @Msg, 1;

    -- a LIST value must be an active choice, or the retired choice the record already has
    SELECT TOP (1) @Msg = CONCAT(x.Label, N': choose one of the options.')
    FROM #v AS x
    WHERE x.OptionId IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM admin.CustomFieldOption AS o
                      WHERE o.TenantId = @TenantId AND o.FieldId = x.FieldId AND o.Id = x.OptionId AND o.IsActive = 1)
      AND NOT EXISTS (SELECT 1 FROM admin.CustomFieldValue AS v
                      WHERE v.TenantId = @TenantId AND v.EntityType = @EntityType AND v.RecordId = @RecordId
                        AND v.FieldId = x.FieldId AND v.OptionId = x.OptionId);
    IF @Msg IS NOT NULL THROW 51217, @Msg, 1;

    BEGIN TRAN;

    DELETE v FROM admin.CustomFieldValue AS v
    JOIN #v AS x ON x.FieldId = v.FieldId AND x.IsBlank = 1
    WHERE v.TenantId = @TenantId AND v.EntityType = @EntityType AND v.RecordId = @RecordId;

    UPDATE v SET ValueText = x.ValueText, ValueInt = x.ValueInt, ValueDecimal = x.ValueDecimal, ValueDate = x.ValueDate,
                 ValueBit = x.ValueBit, OptionId = x.OptionId, ModifiedAt = @Now, ModifiedBy = @UserId
    FROM admin.CustomFieldValue AS v
    JOIN #v AS x ON x.FieldId = v.FieldId AND x.IsBlank = 0
    WHERE v.TenantId = @TenantId AND v.EntityType = @EntityType AND v.RecordId = @RecordId;

    INSERT INTO admin.CustomFieldValue (TenantId, EntityType, RecordId, FieldId, ValueText, ValueInt, ValueDecimal, ValueDate, ValueBit, OptionId)
    SELECT @TenantId, @EntityType, @RecordId, x.FieldId, x.ValueText, x.ValueInt, x.ValueDecimal, x.ValueDate, x.ValueBit, x.OptionId
    FROM #v AS x
    WHERE x.IsBlank = 0
      AND NOT EXISTS (SELECT 1 FROM admin.CustomFieldValue AS v
                      WHERE v.TenantId = @TenantId AND v.EntityType = @EntityType AND v.RecordId = @RecordId AND v.FieldId = x.FieldId);

    SELECT @Msg = CONCAT(N'Fill in the required custom fields: ', STRING_AGG(d.Label, N', ') WITHIN GROUP (ORDER BY d.SortOrder), N'.')
    FROM admin.CustomFieldDefinition AS d
    WHERE d.TenantId = @TenantId AND d.EntityType = @EntityType AND d.IsActive = 1 AND d.IsRequired = 1
      AND NOT EXISTS (SELECT 1 FROM admin.CustomFieldValue AS v
                      WHERE v.TenantId = d.TenantId AND v.EntityType = d.EntityType AND v.RecordId = @RecordId AND v.FieldId = d.Id)
    HAVING COUNT(*) > 0;
    IF @Msg IS NOT NULL THROW 51218, @Msg, 1;

    COMMIT;
END;
