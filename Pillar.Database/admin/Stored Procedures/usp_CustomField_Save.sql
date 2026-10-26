-- Adds or edits one custom field (Settings > Custom fields; needs settings.custom_fields). @FieldId NULL adds a field at the end of
-- its record type's list. EntityType, FieldKey and DataType are fixed once the field exists; to change them, retire the
-- field (@IsActive = 0) and add a new one. A TEXT field's MaxLength can't drop below the longest saved value.
-- LIST fields pass their choices in order as JSON: [{"id": 4, "label": "Net new"}, {"label": "Renewal"}]. Entries with an id
-- rename/reorder that option; options left out are deleted if unused and retired if any record uses them.
CREATE PROCEDURE admin.usp_CustomField_Save
    @FieldId        INT = NULL OUTPUT,
    @EntityType     VARCHAR(20),
    @FieldKey       VARCHAR(50),
    @Label          NVARCHAR(100),
    @DataType       VARCHAR(10),
    @MaxLength      INT = NULL,
    @IsRequired     BIT = 0,
    @HelpText       NVARCHAR(400) = NULL,
    @ShowInList     BIT = 0,
    @IsActive       BIT = 1,
    @Options        NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @OldEntity VARCHAR(20), @OldKey VARCHAR(50), @OldType VARCHAR(10);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51201, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.custom_fields'))
        THROW 51202, N'You need permission to change settings to manage custom fields.', 1;

    SELECT @EntityType = UPPER(@EntityType), @DataType = UPPER(@DataType), @FieldKey = LOWER(LTRIM(RTRIM(@FieldKey))),
           @Label = LTRIM(RTRIM(@Label)), @MaxLength = CASE WHEN UPPER(@DataType) = 'TEXT' THEN COALESCE(@MaxLength, 100) END;
    IF NULLIF(@Label, N'') IS NULL THROW 51203, N'A custom field needs a label.', 1;
    IF @DataType = 'LIST' AND (ISJSON(@Options) = 0 OR NOT EXISTS (SELECT 1 FROM OPENJSON(@Options)))
        THROW 51204, N'A pick-list field needs at least one choice.', 1;

    BEGIN TRAN;

    IF @FieldId IS NULL
    BEGIN
        INSERT INTO admin.CustomFieldDefinition
            (TenantId, EntityType, FieldKey, Label, DataType, MaxLength, IsRequired, SortOrder, IsActive, HelpText, ShowInList)
        SELECT @TenantId, @EntityType, @FieldKey, @Label, @DataType, @MaxLength, @IsRequired,
               ISNULL((SELECT MAX(SortOrder) FROM admin.CustomFieldDefinition WITH (UPDLOCK)
                       WHERE TenantId = @TenantId AND EntityType = @EntityType), 0) + 10,
               @IsActive, @HelpText, @ShowInList;
        SET @FieldId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SELECT @OldEntity = EntityType, @OldKey = FieldKey, @OldType = DataType
        FROM admin.CustomFieldDefinition WITH (UPDLOCK) WHERE TenantId = @TenantId AND Id = @FieldId;
        IF @OldEntity IS NULL THROW 51205, N'Custom field not found.', 1;
        IF @OldEntity <> @EntityType OR @OldKey <> @FieldKey OR @OldType <> @DataType
            THROW 51206, N'A custom field''s record type, key and type can''t change. Retire it and add a new field instead.', 1;
        IF @DataType = 'TEXT' AND EXISTS (SELECT 1 FROM admin.CustomFieldValue
                                          WHERE TenantId = @TenantId AND FieldId = @FieldId AND LEN(ValueText) > @MaxLength)
            THROW 51207, N'Some records already have a longer value than the new maximum length.', 1;

        UPDATE admin.CustomFieldDefinition
        SET Label = @Label, MaxLength = @MaxLength, IsRequired = @IsRequired, IsActive = @IsActive, HelpText = @HelpText,
            ShowInList = @ShowInList, ModifiedAt = @Now, ModifiedBy = @UserId
        WHERE TenantId = @TenantId AND Id = @FieldId;
    END;

    IF @DataType = 'LIST'
    BEGIN
        CREATE TABLE #opt (Seq INT NOT NULL, Id INT NULL, Label NVARCHAR(100) NULL);
        INSERT INTO #opt (Seq, Id, Label)
        SELECT CONVERT(INT, j.[key]) + 1, x.id, LTRIM(RTRIM(x.label))
        FROM OPENJSON(@Options) AS j
        CROSS APPLY OPENJSON(j.value) WITH (id INT, label NVARCHAR(100)) AS x;

        IF EXISTS (SELECT 1 FROM #opt WHERE NULLIF(Label, N'') IS NULL)
            THROW 51208, N'Every pick-list choice needs a label.', 1;
        IF EXISTS (SELECT Label FROM #opt GROUP BY Label HAVING COUNT(*) > 1)
            THROW 51209, N'Pick-list choices must be different from each other.', 1;
        IF EXISTS (SELECT 1 FROM #opt AS o WHERE o.Id IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM admin.CustomFieldOption AS c
                                   WHERE c.TenantId = @TenantId AND c.FieldId = @FieldId AND c.Id = o.Id))
            THROW 51210, N'A pick-list choice doesn''t belong to this field.', 1;

        -- left-out options: delete if unused, otherwise retire (old records keep showing the label)
        DELETE c FROM admin.CustomFieldOption AS c
        WHERE c.TenantId = @TenantId AND c.FieldId = @FieldId
          AND NOT EXISTS (SELECT 1 FROM #opt AS o WHERE o.Id = c.Id)
          AND NOT EXISTS (SELECT 1 FROM admin.CustomFieldValue AS v WHERE v.TenantId = c.TenantId AND v.FieldId = c.FieldId AND v.OptionId = c.Id);
        UPDATE c SET IsActive = 0, SortOrder = 100000 + c.Id, ModifiedAt = @Now, ModifiedBy = @UserId
        FROM admin.CustomFieldOption AS c
        WHERE c.TenantId = @TenantId AND c.FieldId = @FieldId AND c.IsActive = 1
          AND NOT EXISTS (SELECT 1 FROM #opt AS o WHERE o.Id = c.Id);

        -- park kept labels first so renames that swap two labels don't trip the unique index
        UPDATE c SET Label = CONVERT(NVARCHAR(100), NEWID())
        FROM admin.CustomFieldOption AS c JOIN #opt AS o ON o.Id = c.Id
        WHERE c.TenantId = @TenantId AND c.FieldId = @FieldId;
        UPDATE c SET Label = o.Label, SortOrder = o.Seq * 10, IsActive = 1, ModifiedAt = @Now, ModifiedBy = @UserId
        FROM admin.CustomFieldOption AS c JOIN #opt AS o ON o.Id = c.Id
        WHERE c.TenantId = @TenantId AND c.FieldId = @FieldId;

        INSERT INTO admin.CustomFieldOption (TenantId, FieldId, Label, SortOrder)
        SELECT @TenantId, @FieldId, o.Label, o.Seq * 10 FROM #opt AS o WHERE o.Id IS NULL;
    END;

    DECLARE @AuditKey NVARCHAR(100) = CONVERT(NVARCHAR(100), @FieldId),
            @AuditSummary NVARCHAR(400) = CONCAT(N'Saved custom field "', @Label, N'" on ', @EntityType, IIF(@IsActive = 0, N' (retired)', N''));
    EXEC admin.usp_Audit_Write @Area = 'custom_fields', @EntityType = 'CUSTOM_FIELD', @EntityKey = @AuditKey,
         @Action = 'UPDATE', @Summary = @AuditSummary;

    COMMIT;
END;
