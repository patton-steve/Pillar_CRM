-- Daily platform job (IsPlatformAdmin), run by admin.usp_PlanChange_ApplyDue and at the end of each deploy (handoff 26):
--   1. copies onto admin.[Plan] each plan's latest version (admin.PlanVersion) whose EffectiveFrom has come, so admin.[Plan]
--      always shows today's terms; versions it passes over are marked applied too
--   2. applies scheduled override changes (admin.TenantOverrideChange) whose EffectiveDate has come, keeping the value each replaced
-- Billing never depends on this having run: statements and fees read admin.fn_TenantTerms by date. Returns the counts.
CREATE PROCEDURE admin.usp_PlanVersion_ApplyDue
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE), @Now DATETIME2(0) = SYSUTCDATETIME(), @Plans INT, @Overrides INT = 0,
            @Id INT, @T INT, @Key VARCHAR(100), @Value NVARCHAR(400), @Clear BIT;

    BEGIN TRAN;
    UPDATE p
    SET FeeRate = v.FeeRate, PerInvoiceCap = v.PerInvoiceCap, MonthlyMinimum = v.MonthlyMinimum, FeePerHeadCap = v.FeePerHeadCap,
        ExcludeExpensesFromFee = v.ExcludeExpensesFromFee, MonthlyPrice = v.MonthlyPrice, IncludedSeats = v.IncludedSeats,
        ExtraSeatPrice = v.ExtraSeatPrice, MaxSeats = v.MaxSeats, IncludedAiReports = v.IncludedAiReports,
        AiOveragePrice = v.AiOveragePrice, IncludedAiSearches = v.IncludedAiSearches
    FROM admin.[Plan] AS p
    CROSS APPLY (SELECT TOP (1) pv.* FROM admin.PlanVersion AS pv
                 WHERE pv.PlanId = p.Id AND pv.CancelledAt IS NULL AND pv.EffectiveFrom <= @Today
                 ORDER BY pv.EffectiveFrom DESC) AS v
    WHERE EXISTS (SELECT 1 FROM admin.PlanVersion AS x
                  WHERE x.PlanId = p.Id AND x.CancelledAt IS NULL AND x.EffectiveFrom <= @Today AND x.AppliedAt IS NULL);
    SET @Plans = @@ROWCOUNT;
    UPDATE admin.PlanVersion SET AppliedAt = @Now WHERE CancelledAt IS NULL AND EffectiveFrom <= @Today AND AppliedAt IS NULL;
    COMMIT;

    DECLARE due CURSOR LOCAL FAST_FORWARD FOR
        SELECT c.Id, c.TenantId, c.SettingKey, c.Value FROM admin.TenantOverrideChange AS c
        WHERE c.AppliedAt IS NULL AND c.CancelledAt IS NULL AND c.EffectiveDate <= @Today
        ORDER BY c.EffectiveDate, c.Id;
    OPEN due;
    FETCH NEXT FROM due INTO @Id, @T, @Key, @Value;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRAN;
        SET @Clear = IIF(@Value IS NULL, 1, 0);
        UPDATE admin.TenantOverrideChange
        SET AppliedAt = @Now, OldValue = (SELECT s.Value FROM admin.TenantSetting AS s WHERE s.TenantId = @T AND s.SettingKey = @Key)
        WHERE Id = @Id;
        EXEC admin.usp_Setting_Set @TenantId = @T, @SettingKey = @Key, @Value = @Value, @Clear = @Clear;
        COMMIT;
        SET @Overrides += 1;
        FETCH NEXT FROM due INTO @Id, @T, @Key, @Value;
    END;
    CLOSE due;
    DEALLOCATE due;

    SELECT @Plans AS PlansUpdated, @Overrides AS OverridesApplied;
END;
