-- Reverses one application (kept for audit with ReversedAt). The amount returns to the payment or credit as unapplied.
CREATE PROCEDURE ar.usp_InvoicePay_Unapply
    @ApplicationId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @InvoiceId INT, @InvoicePayId INT, @CreditMemoId INT;

    BEGIN TRAN;

    UPDATE ar.InvoicePayApplication
    SET ReversedAt = SYSUTCDATETIME(), ReversedBy = CAST(SESSION_CONTEXT(N'UserId') AS INT),
        @InvoiceId = InvoiceId, @InvoicePayId = InvoicePayId, @CreditMemoId = CreditMemoId
    WHERE TenantId = @TenantId AND Id = @ApplicationId AND ReversedAt IS NULL;

    IF @@ROWCOUNT = 0 THROW 50711, N'Application not found or already reversed.', 1;

    EXEC ar.usp_ApplicationTotals_Sync @InvoiceId = @InvoiceId, @InvoicePayId = @InvoicePayId, @CreditMemoId = @CreditMemoId;

    COMMIT;
END;
