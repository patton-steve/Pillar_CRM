-- Pillar sets or clears (@Value NULL) one of a tenant's Pillar-only settings from the back office, with a required reason:
-- fee overrides (Platform.FeeRateOverride, Platform.FeeCapOverride, Platform.MonthlyMinimumOverride, and from handoff 26
-- Platform.FeePerHeadCapOverride and Platform.ExcludeExpensesOverride), price and seats (Plan.MonthlyPriceOverride,
-- Seats.IncludedOverride, Seats.ExtraPriceOverride, Tenant.MaxUsers = the max seats override), Pilo (Pilo.MonthlyReportsOverride,
-- Pilo.MonthlySearchesOverride) and feature flags. Only PLATFORM_ONLY and TENANT_READ settings.
-- Handoff 26: @EffectiveDate (default today, UTC). Today or earlier applies now; a later date is scheduled in
-- admin.TenantOverrideChange and applied by admin.usp_PlanVersion_ApplyDue (the daily job) on that date. Every change is kept
-- there with the value it replaced, so statements for past months use the override in force then (admin.fn_OverrideAsOf).
-- The old and new values go in Pillar's audit trail. Returns the change's Id and whether it is SCHEDULED or APPLIED.
CREATE PROCEDURE admin.usp_Tenant_SetOverride
    @TenantId       INT,
    @SettingKey     VARCHAR(100),
    @Value          NVARCHAR(400),
    @Reason         NVARCHAR(500),
    @EffectiveDate  DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId) THROW 52202, N'Unknown tenant.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.SettingDefinition WHERE SettingKey = @SettingKey AND Visibility <> 'TENANT_EDIT')
        THROW 52255, N'Only Pillar-managed settings can be overridden here.', 1;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE), @Old NVARCHAR(400), @Change NVARCHAR(MAX), @Summary NVARCHAR(400),
            @Clear BIT = IIF(@Value IS NULL, 1, 0), @ChangeId INT, @Scheduled BIT;
    SET @EffectiveDate = ISNULL(@EffectiveDate, @Today);
    SET @Scheduled = IIF(@EffectiveDate > @Today, 1, 0);
    SELECT @Old = Value FROM admin.TenantSetting WHERE TenantId = @TenantId AND SettingKey = @SettingKey;

    BEGIN TRAN;
    IF @Scheduled = 0
        EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = @SettingKey, @Value = @Value, @Clear = @Clear;

    INSERT INTO admin.TenantOverrideChange (TenantId, SettingKey, Value, OldValue, EffectiveDate, Reason, AppliedAt)
    VALUES (@TenantId, @SettingKey, @Value, IIF(@Scheduled = 0, @Old, NULL), @EffectiveDate, @Reason,
            IIF(@Scheduled = 0, SYSUTCDATETIME(), NULL));
    SET @ChangeId = SCOPE_IDENTITY();

    SET @Change = (SELECT @SettingKey AS field, @Old AS [from], @Value AS [to], @EffectiveDate AS effective FOR JSON PATH, INCLUDE_NULL_VALUES);
    SET @Summary = CONCAT(IIF(@Clear = 1, N'Cleared ', N'Set '), @SettingKey, IIF(@Scheduled = 1, CONCAT(N' from ', CONVERT(CHAR(10), @EffectiveDate, 23)), N''));
    EXEC admin.usp_PlatformAudit_Write @Action = 'SET_OVERRIDE', @TenantId = @TenantId, @EntityType = 'SETTING', @EntityKey = @SettingKey,
         @Summary = @Summary, @Reason = @Reason, @ChangeJson = @Change;
    COMMIT;

    SELECT @ChangeId AS OverrideChangeId, IIF(@Scheduled = 1, 'SCHEDULED', 'APPLIED') AS Status;
END;
