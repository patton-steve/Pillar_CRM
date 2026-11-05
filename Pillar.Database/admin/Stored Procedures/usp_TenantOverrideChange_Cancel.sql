-- Cancels a scheduled override change before its date (Pillar staff, handoff 26). A reason is required and audited.
CREATE PROCEDURE admin.usp_TenantOverrideChange_Cancel
    @OverrideChangeId   INT,
    @Reason             NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;

    DECLARE @T INT, @Key VARCHAR(100), @Summary NVARCHAR(400);
    BEGIN TRAN;
    UPDATE admin.TenantOverrideChange
    SET CancelledAt = SYSUTCDATETIME(), @T = TenantId, @Key = SettingKey,
        @Summary = CONCAT(N'Cancelled the ', CONVERT(CHAR(10), EffectiveDate, 23), N' change to ', SettingKey)
    WHERE Id = @OverrideChangeId AND AppliedAt IS NULL AND CancelledAt IS NULL;
    IF @@ROWCOUNT = 0 THROW 52614, N'Only a scheduled override change can be cancelled.', 1;
    EXEC admin.usp_PlatformAudit_Write @Action = 'OVERRIDE_CANCEL', @TenantId = @T, @EntityType = 'SETTING', @EntityKey = @Key,
         @Summary = @Summary, @Reason = @Reason;
    COMMIT;
END;
