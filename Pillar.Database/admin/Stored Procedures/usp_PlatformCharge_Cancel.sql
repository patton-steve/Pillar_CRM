-- Cancels a one-time charge that hasn't been billed or paid yet (Pillar staff, handoff 26). A reason is required and audited.
CREATE PROCEDURE admin.usp_PlatformCharge_Cancel
    @ChargeId   INT,
    @Reason     NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;

    DECLARE @T INT, @Summary NVARCHAR(400);
    BEGIN TRAN;
    UPDATE admin.PlatformCharge
    SET Status = 'CANCELLED', CancelledAt = SYSUTCDATETIME(), @T = TenantId,
        @Summary = CONCAT(N'Cancelled charge ', FORMAT(Amount, 'C', 'en-US'), N': ', LEFT(Description, 100))
    WHERE Id = @ChargeId AND Status = 'PENDING';
    IF @@ROWCOUNT = 0 THROW 52624, N'Only a charge that hasn''t been billed or paid can be cancelled.', 1;
    EXEC admin.usp_PlatformAudit_Write @Action = 'CHARGE_CANCEL', @TenantId = @T, @EntityType = 'CHARGE', @EntityKey = @ChargeId,
         @Summary = @Summary, @Reason = @Reason;
    COMMIT;
END;
