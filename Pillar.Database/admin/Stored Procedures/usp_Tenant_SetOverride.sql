-- Pillar sets or clears (@Value NULL) one of a tenant's Pillar-only settings from the back office, with a required reason:
-- fee overrides (Platform.FeeRateOverride, Platform.FeeCapOverride, Platform.MonthlyMinimumOverride), seats
-- (Seats.IncludedOverride, Seats.ExtraPriceOverride, Tenant.MaxUsers), Pilo (Pilo.MonthlyReportsOverride) and feature flags.
-- Only PLATFORM_ONLY and TENANT_READ settings; the old and new values go in Pillar's audit trail.
CREATE PROCEDURE admin.usp_Tenant_SetOverride
    @TenantId   INT,
    @SettingKey VARCHAR(100),
    @Value      NVARCHAR(400),
    @Reason     NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId) THROW 52202, N'Unknown tenant.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.SettingDefinition WHERE SettingKey = @SettingKey AND Visibility <> 'TENANT_EDIT')
        THROW 52255, N'Only Pillar-managed settings can be overridden here.', 1;

    DECLARE @Old NVARCHAR(400), @Change NVARCHAR(MAX), @Summary NVARCHAR(400), @Clear BIT = IIF(@Value IS NULL, 1, 0);
    SELECT @Old = Value FROM admin.TenantSetting WHERE TenantId = @TenantId AND SettingKey = @SettingKey;

    BEGIN TRAN;
    EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = @SettingKey, @Value = @Value, @Clear = @Clear;
    SET @Change = (SELECT @SettingKey AS field, @Old AS [from], @Value AS [to] FOR JSON PATH, INCLUDE_NULL_VALUES);
    SET @Summary = CONCAT(IIF(@Clear = 1, N'Cleared ', N'Set '), @SettingKey);
    EXEC admin.usp_PlatformAudit_Write @Action = 'SET_OVERRIDE', @TenantId = @TenantId, @EntityType = 'SETTING', @EntityKey = @SettingKey,
         @Summary = @Summary, @Reason = @Reason, @ChangeJson = @Change;
    COMMIT;
END;
