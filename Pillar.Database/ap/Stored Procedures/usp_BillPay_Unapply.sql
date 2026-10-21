-- Reverses one bill payment application (kept with ReversedAt).
CREATE PROCEDURE ap.usp_BillPay_Unapply
    @ApplicationId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT), @BillId INT, @BillPayId INT;

    BEGIN TRAN;

    UPDATE ap.BillPayApplication
    SET ReversedAt = SYSUTCDATETIME(), ReversedBy = CAST(SESSION_CONTEXT(N'UserId') AS INT),
        @BillId = BillId, @BillPayId = BillPayId
    WHERE TenantId = @TenantId AND Id = @ApplicationId AND ReversedAt IS NULL;

    IF @@ROWCOUNT = 0 THROW 50871, N'Application not found or already reversed.', 1;

    EXEC ap.usp_BillApplicationTotals_Sync @BillId = @BillId, @BillPayId = @BillPayId;

    COMMIT;
END;
