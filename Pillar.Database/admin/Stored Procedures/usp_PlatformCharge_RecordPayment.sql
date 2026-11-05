-- The API reports the card charge for a CHARGE_NOW one-time charge (Pillar staff or the platform job, handoff 26).
-- Succeeded: PAID with the processor's charge id (a repeated report with the same id is ignored). Failed: the charge moves to
-- NEXT_STATEMENT, so it's billed on the next statement instead, and the failure is noted.
CREATE PROCEDURE admin.usp_PlatformCharge_RecordPayment
    @ChargeId           INT,
    @Succeeded          BIT,
    @PaymentMethodId    INT = NULL,
    @ProcessorChargeId  VARCHAR(100) = NULL,
    @FailureReason      NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF EXISTS (SELECT 1 FROM admin.PlatformCharge WHERE Id = @ChargeId AND Status = 'PAID' AND ProcessorChargeId = @ProcessorChargeId) RETURN;

    UPDATE admin.PlatformCharge
    SET Status = IIF(@Succeeded = 1, 'PAID', 'PENDING'),
        BillOn = IIF(@Succeeded = 1, BillOn, 'NEXT_STATEMENT'),
        PaidAt = IIF(@Succeeded = 1, SYSUTCDATETIME(), NULL),
        PaymentMethodId = @PaymentMethodId, ProcessorChargeId = @ProcessorChargeId,
        Note = IIF(@Succeeded = 1, Note, LEFT(CONCAT(N'Card charge failed (', ISNULL(@FailureReason, N'no reason given'),
                                                     N'); moved to the next statement.'), 500))
    WHERE Id = @ChargeId AND Status = 'PENDING' AND BillOn = 'CHARGE_NOW';
    IF @@ROWCOUNT = 0 THROW 52625, N'That charge isn''t waiting to be charged now.', 1;
END;
