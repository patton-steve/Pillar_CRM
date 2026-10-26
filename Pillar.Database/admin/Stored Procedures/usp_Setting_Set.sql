-- Sets (or clears, with @Value = NULL and @Clear = 1) a tenant or user setting.
-- Tenants may only change TENANT_EDIT settings; TENANT_READ and PLATFORM_ONLY need IsPlatformAdmin.
-- Validates the value against DataType and AllowedValues.
-- Who may change it (handoff 21): a tenant value needs the setting's page permission (SettingDefinition.PermissionCode,
-- e.g. settings.time); a per-user override may be set by that user or by someone with the page permission. Pillar staff
-- (IsPlatformAdmin) and calls without a user in session (sign-up, seeds) skip the check. Tenant-value changes are audited.
CREATE PROCEDURE admin.usp_Setting_Set
    @TenantId       INT,
    @SettingKey     VARCHAR(100),
    @Value          NVARCHAR(400),
    @AppUserId      INT = NULL,     -- set = per-user override
    @Clear          BIT = 0         -- 1 = remove the override and fall back
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @DataType VARCHAR(10), @Visibility VARCHAR(15), @AllowUser BIT, @Allowed NVARCHAR(1000), @Permission VARCHAR(50),
            @IsAdmin BIT = ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0),
            @Actor INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')), @Category NVARCHAR(50),
            @OldValue NVARCHAR(400), @AuditChange NVARCHAR(MAX), @AuditSummary NVARCHAR(400), @AuditArea VARCHAR(30);

    SELECT @DataType = DataType, @Visibility = Visibility, @AllowUser = AllowUserOverride, @Allowed = AllowedValues,
           @Permission = PermissionCode, @Category = Category
    FROM admin.SettingDefinition WHERE SettingKey = @SettingKey;

    IF @DataType IS NULL THROW 50401, N'Unknown setting.', 1;
    IF @Visibility <> 'TENANT_EDIT' AND @IsAdmin = 0 THROW 50402, N'This setting can only be changed by Pillar.', 1;
    IF @AppUserId IS NOT NULL AND @AllowUser = 0 THROW 50403, N'This setting cannot be set per user.', 1;
    IF @IsAdmin = 0 AND @Actor IS NOT NULL AND (@AppUserId IS NULL OR @AppUserId <> @Actor)
       AND (@Permission IS NULL OR NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @Actor, @Permission)))
        THROW 50406, N'You don''t have permission to change this setting.', 1;

    IF @Clear = 0 AND @Value IS NOT NULL
    BEGIN
        IF (@DataType = 'BIT'     AND @Value NOT IN (N'0', N'1'))
        OR (@DataType = 'INT'     AND TRY_CAST(@Value AS INT) IS NULL)
        OR (@DataType = 'DECIMAL' AND TRY_CAST(@Value AS DECIMAL(19,6)) IS NULL)
        OR (@DataType = 'DATE'    AND TRY_CAST(@Value AS DATE) IS NULL)
            THROW 50404, N'Value does not match the setting''s data type.', 1;

        IF @Allowed IS NOT NULL AND NOT EXISTS (SELECT 1 FROM OPENJSON(@Allowed) WHERE [value] = @Value)
            THROW 50405, N'Value is not one of the allowed values.', 1;
    END;

    IF @AppUserId IS NULL
    BEGIN
        SELECT @OldValue = Value FROM admin.TenantSetting WHERE TenantId = @TenantId AND SettingKey = @SettingKey;
        SELECT @AuditChange = (SELECT N'Value' AS field, @OldValue AS [from], IIF(@Clear = 1, NULL, @Value) AS [to]
                               FOR JSON PATH, INCLUDE_NULL_VALUES),
               @AuditSummary = CONCAT(IIF(@Clear = 1, N'Reset ', N'Changed '), @SettingKey),
               @AuditArea = ISNULL(REPLACE(@Permission, 'settings.', ''), 'company');
        EXEC admin.usp_Audit_Write @Area = @AuditArea, @EntityType = 'SETTING', @EntityKey = @SettingKey,
             @Action = 'UPDATE', @Summary = @AuditSummary, @ChangeJson = @AuditChange, @TenantId = @TenantId;
        IF @Clear = 1
            DELETE FROM admin.TenantSetting WHERE TenantId = @TenantId AND SettingKey = @SettingKey;
        ELSE
            MERGE admin.TenantSetting WITH (HOLDLOCK) AS t
            USING (SELECT @TenantId AS TenantId, @SettingKey AS SettingKey) AS s
            ON t.TenantId = s.TenantId AND t.SettingKey = s.SettingKey
            WHEN MATCHED THEN UPDATE SET Value = @Value, ModifiedAt = SYSUTCDATETIME(), ModifiedBy = CAST(SESSION_CONTEXT(N'UserId') AS INT)
            WHEN NOT MATCHED THEN INSERT (TenantId, SettingKey, Value) VALUES (@TenantId, @SettingKey, @Value);
    END
    ELSE
    BEGIN
        IF @Clear = 1
            DELETE FROM admin.UserSetting WHERE TenantId = @TenantId AND AppUserId = @AppUserId AND SettingKey = @SettingKey;
        ELSE
            MERGE admin.UserSetting WITH (HOLDLOCK) AS t
            USING (SELECT @TenantId AS TenantId, @AppUserId AS AppUserId, @SettingKey AS SettingKey) AS s
            ON t.TenantId = s.TenantId AND t.AppUserId = s.AppUserId AND t.SettingKey = s.SettingKey
            WHEN MATCHED THEN UPDATE SET Value = @Value, ModifiedAt = SYSUTCDATETIME(), ModifiedBy = CAST(SESSION_CONTEXT(N'UserId') AS INT)
            WHEN NOT MATCHED THEN INSERT (TenantId, AppUserId, SettingKey, Value) VALUES (@TenantId, @AppUserId, @SettingKey, @Value);
    END;
END;
