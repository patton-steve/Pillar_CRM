-- Records one charge attempt the API made against a statement (IsPlatformAdmin; called after the processor answers,
-- including from its webhook). Success adds to AmountPaid and, once covered, marks the statement and its fees PAID.
-- Failure marks the statement PAST_DUE and counts the attempt; the API decides when to retry and when to email the tenant.
-- Idempotent on @ProcessorChargeId: a repeated webhook for the same charge does nothing.
CREATE PROCEDURE admin.usp_PlatformStatement_RecordPayment
    @StatementId        INT,
    @Amount             DECIMAL(19,2),
    @Succeeded          BIT,
    @ProcessorChargeId  VARCHAR(100) = NULL,
    @PaymentMethodId    INT = NULL,
    @FailureReason      NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0
        THROW 51011, N'Platform payments are recorded by Pillar only.', 1;
    IF @ProcessorChargeId IS NOT NULL AND EXISTS (SELECT 1 FROM admin.PlatformPayment WHERE ProcessorChargeId = @ProcessorChargeId)
        RETURN;

    DECLARE @TenantId INT, @Now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;

    SELECT @TenantId = TenantId
    FROM admin.PlatformStatement WITH (UPDLOCK)
    WHERE Id = @StatementId AND Status IN ('OPEN', 'PAST_DUE');
    IF @TenantId IS NULL THROW 51012, N'Only open or past-due statements can take a payment.', 1;
    IF @Succeeded = 1 AND @Amount > (SELECT BalanceDue FROM admin.PlatformStatement WHERE Id = @StatementId)
        THROW 51013, N'Payment is more than the balance due.', 1;

    INSERT INTO admin.PlatformPayment (TenantId, StatementId, PaymentMethodId, Amount, Succeeded, ProcessorChargeId, FailureReason, MethodDisplay)
    SELECT @TenantId, @StatementId, @PaymentMethodId, @Amount, @Succeeded, @ProcessorChargeId, @FailureReason,
           (SELECT CONCAT(m.Brand, N' ending ', m.Last4) FROM admin.TenantPaymentMethod AS m
            WHERE m.TenantId = @TenantId AND m.Id = @PaymentMethodId);

    IF @Succeeded = 1
    BEGIN
        UPDATE admin.PlatformStatement
        SET AmountPaid = AmountPaid + @Amount, LastAttemptAt = @Now,
            Status = CASE WHEN AmountPaid + @Amount >= AmountDue THEN 'PAID' ELSE Status END,
            PaidAt = CASE WHEN AmountPaid + @Amount >= AmountDue THEN @Now END
        WHERE Id = @StatementId;

        UPDATE f SET FeeStatus = 'PAID'
        FROM admin.PlatformFee AS f
        JOIN admin.PlatformStatement AS s ON s.TenantId = f.TenantId AND s.Id = f.PlatformStatementId
        WHERE s.Id = @StatementId AND s.Status = 'PAID' AND f.FeeStatus = 'BILLED';
    END
    ELSE
        UPDATE admin.PlatformStatement
        SET Status = 'PAST_DUE', FailedAttempts = FailedAttempts + 1, LastAttemptAt = @Now
        WHERE Id = @StatementId;

    COMMIT;
END;
