-- Voids a bill payment (stopped check, entered in error): reverses its applications, then marks it void.
CREATE PROCEDURE ap.usp_BillPay_Void
    @BillPayId  INT,
    @Reason     NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT), @Now DATETIME2(0) = SYSUTCDATETIME(), @BillId INT;
    DECLARE @bills TABLE (BillId INT);

    IF NULLIF(LTRIM(@Reason), N'') IS NULL THROW 50881, N'A void reason is required.', 1;

    BEGIN TRAN;

    UPDATE ap.BillPay SET VoidedAt = @Now, VoidedBy = @UserId, VoidReason = @Reason
    WHERE TenantId = @TenantId AND Id = @BillPayId AND VoidedAt IS NULL;
    IF @@ROWCOUNT = 0 THROW 50882, N'Payment not found or already void.', 1;

    UPDATE ap.BillPayApplication SET ReversedAt = @Now, ReversedBy = @UserId
    OUTPUT inserted.BillId INTO @bills
    WHERE TenantId = @TenantId AND BillPayId = @BillPayId AND ReversedAt IS NULL;

    EXEC ap.usp_BillApplicationTotals_Sync @BillPayId = @BillPayId;

    DECLARE b CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT BillId FROM @bills;
    OPEN b;
    FETCH NEXT FROM b INTO @BillId;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC ap.usp_BillApplicationTotals_Sync @BillId = @BillId;
        FETCH NEXT FROM b INTO @BillId;
    END;
    CLOSE b; DEALLOCATE b;

    COMMIT;
END;
