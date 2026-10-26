-- Records one charge attempt the API made against a statement (IsPlatformAdmin; called after the processor answers,
-- including from its webhook). Success adds to AmountPaid and, once covered, marks the statement and its fees PAID.
-- Failure marks the statement PAST_DUE and counts the attempt. Handoff 22: it also sets NextRetryAt (1, 3, then 5 days later;
-- none after the fourth failure, when Pillar follows up by hand), tells the tenant's billing.manage holders (PLAN_PAYMENT_FAILED,
-- in-app and email: the banner shows while the statement is PAST_DUE, no lockout) and puts it in Pillar's back-office inbox.
-- @Note is kept on the payment row (admin.usp_PlatformStatement_MarkPaid uses it).
-- Idempotent on @ProcessorChargeId: a repeated webhook for the same charge does nothing.
CREATE PROCEDURE admin.usp_PlatformStatement_RecordPayment
    @StatementId        INT,
    @Amount             DECIMAL(19,2),
    @Succeeded          BIT,
    @ProcessorChargeId  VARCHAR(100) = NULL,
    @PaymentMethodId    INT = NULL,
    @FailureReason      NVARCHAR(500) = NULL,
    @Note               NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0
        THROW 51011, N'Platform payments are recorded by Pillar only.', 1;
    IF @ProcessorChargeId IS NOT NULL AND EXISTS (SELECT 1 FROM admin.PlatformPayment WHERE ProcessorChargeId = @ProcessorChargeId)
        RETURN;

    DECLARE @TenantId INT, @Now DATETIME2(0) = SYSUTCDATETIME(), @Attempts INT, @Title NVARCHAR(200), @Number VARCHAR(20);

    BEGIN TRAN;

    SELECT @TenantId = TenantId
    FROM admin.PlatformStatement WITH (UPDLOCK)
    WHERE Id = @StatementId AND Status IN ('OPEN', 'PAST_DUE');
    IF @TenantId IS NULL THROW 51012, N'Only open or past-due statements can take a payment.', 1;
    IF @Succeeded = 1 AND @Amount > (SELECT BalanceDue FROM admin.PlatformStatement WHERE Id = @StatementId)
        THROW 51013, N'Payment is more than the balance due.', 1;

    INSERT INTO admin.PlatformPayment (TenantId, StatementId, PaymentMethodId, Amount, Succeeded, ProcessorChargeId, FailureReason, Note, MethodDisplay)
    SELECT @TenantId, @StatementId, @PaymentMethodId, @Amount, @Succeeded, @ProcessorChargeId, @FailureReason, @Note,
           (SELECT CONCAT(m.Brand, N' ending ', m.Last4) FROM admin.TenantPaymentMethod AS m
            WHERE m.TenantId = @TenantId AND m.Id = @PaymentMethodId);

    IF @Succeeded = 1
    BEGIN
        UPDATE admin.PlatformStatement
        SET AmountPaid = AmountPaid + @Amount, LastAttemptAt = @Now, NextRetryAt = NULL,
            Status = CASE WHEN AmountPaid + @Amount >= AmountDue THEN 'PAID' ELSE Status END,
            PaidAt = CASE WHEN AmountPaid + @Amount >= AmountDue THEN @Now END
        WHERE Id = @StatementId;

        UPDATE f SET FeeStatus = 'PAID'
        FROM admin.PlatformFee AS f
        JOIN admin.PlatformStatement AS s ON s.TenantId = f.TenantId AND s.Id = f.PlatformStatementId
        WHERE s.Id = @StatementId AND s.Status = 'PAID' AND f.FeeStatus = 'BILLED';
    END
    ELSE
    BEGIN
        UPDATE admin.PlatformStatement
        SET Status = 'PAST_DUE', FailedAttempts = FailedAttempts + 1, LastAttemptAt = @Now,
            NextRetryAt = CASE FailedAttempts + 1 WHEN 1 THEN DATEADD(DAY, 1, @Now) WHEN 2 THEN DATEADD(DAY, 3, @Now)
                                                  WHEN 3 THEN DATEADD(DAY, 5, @Now) END,
            @Attempts = FailedAttempts + 1, @Number = StatementNumber
        WHERE Id = @StatementId;

        SET @Title = CONCAT(N'Pillar couldn''t charge your card for statement ', @Number);
        EXEC sec.usp_Notification_Raise @NotificationType = 'PLAN_PAYMENT_FAILED', @EntityType = 'STATEMENT', @EntityId = @StatementId,
             @Title = @Title, @Body = @FailureReason, @ForTenantId = @TenantId;
        SET @Title = CONCAT(N'Charge failed (attempt ', @Attempts, N'): ', (SELECT Name FROM admin.Tenant WHERE Id = @TenantId));
        EXEC admin.usp_PlatformNotification_Raise @Kind = 'PAYMENT_FAILED', @Title = @Title, @Body = @FailureReason,
             @TenantId = @TenantId, @EntityType = 'STATEMENT', @EntityId = @StatementId, @SendEmail = 0;
    END;

    COMMIT;
END;
