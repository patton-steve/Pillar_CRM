-- Voids a payment (bounced check, entered in error): reverses all its applications, then marks it void.
-- Refused once any of it has been refunded.
CREATE PROCEDURE ar.usp_InvoicePay_Void
    @InvoicePayId   INT,
    @Reason         NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME(), @Refunded DECIMAL(19,2), @InvoiceId INT;
    DECLARE @invoices TABLE (InvoiceId INT);

    IF NULLIF(LTRIM(@Reason), N'') IS NULL THROW 50721, N'A void reason is required.', 1;

    BEGIN TRAN;

    SELECT @Refunded = AmountRefunded FROM ar.InvoicePay WITH (UPDLOCK)
    WHERE TenantId = @TenantId AND Id = @InvoicePayId AND VoidedAt IS NULL;

    IF @Refunded IS NULL THROW 50722, N'Payment not found or already void.', 1;
    IF @Refunded > 0 THROW 50723, N'A payment with refunds cannot be voided.', 1;

    UPDATE ar.InvoicePayApplication
    SET ReversedAt = @Now, ReversedBy = @UserId
    OUTPUT inserted.InvoiceId INTO @invoices
    WHERE TenantId = @TenantId AND InvoicePayId = @InvoicePayId AND ReversedAt IS NULL;

    UPDATE ar.InvoicePay
    SET VoidedAt = @Now, VoidedBy = @UserId, VoidReason = @Reason
    WHERE TenantId = @TenantId AND Id = @InvoicePayId;

    EXEC ar.usp_ApplicationTotals_Sync @InvoicePayId = @InvoicePayId;

    DECLARE inv CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT InvoiceId FROM @invoices;
    OPEN inv;
    FETCH NEXT FROM inv INTO @InvoiceId;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC ar.usp_ApplicationTotals_Sync @InvoiceId = @InvoiceId;
        FETCH NEXT FROM inv INTO @InvoiceId;
    END;
    CLOSE inv; DEALLOCATE inv;

    COMMIT;
END;
