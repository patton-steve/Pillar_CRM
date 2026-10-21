-- Refunds part or all of the unapplied amount of a payment or credit memo back to the client.
CREATE PROCEDURE ar.usp_Refund_Create
    @Amount             DECIMAL(19,2),
    @PaymentMethodId    INT,
    @InvoicePayId       INT = NULL,
    @CreditMemoId       INT = NULL,
    @RefundDate         DATE = NULL,
    @ReferenceNumber    NVARCHAR(100) = NULL,
    @Memo               NVARCHAR(500) = NULL,
    @RefundId           INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @ClientId INT, @Available DECIMAL(19,2);

    IF (@InvoicePayId IS NULL AND @CreditMemoId IS NULL) OR (@InvoicePayId IS NOT NULL AND @CreditMemoId IS NOT NULL)
        THROW 50741, N'Pass either @InvoicePayId or @CreditMemoId.', 1;
    IF @Amount IS NULL OR @Amount <= 0 THROW 50742, N'Refund amount must be greater than zero.', 1;

    IF @RefundDate IS NULL
        SELECT @RefundDate = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE t.TimeZoneId AS DATE)
        FROM admin.Tenant AS t WHERE t.Id = @TenantId;

    BEGIN TRAN;

    IF @InvoicePayId IS NOT NULL
        SELECT @ClientId = ClientId, @Available = UnappliedAmount
        FROM ar.InvoicePay WITH (UPDLOCK) WHERE TenantId = @TenantId AND Id = @InvoicePayId AND VoidedAt IS NULL;
    ELSE
        SELECT @ClientId = ClientId, @Available = UnappliedAmount
        FROM ar.CreditMemo WITH (UPDLOCK) WHERE TenantId = @TenantId AND Id = @CreditMemoId AND VoidedAt IS NULL;

    IF @ClientId IS NULL THROW 50743, N'Payment or credit not found, or it is void.', 1;
    IF @Amount > @Available THROW 50744, N'Refund is more than the unapplied amount.', 1;

    INSERT INTO ar.Refund (TenantId, ClientId, InvoicePayId, CreditMemoId, RefundDate, Amount, PaymentMethodId, ReferenceNumber, Memo)
    VALUES (@TenantId, @ClientId, @InvoicePayId, @CreditMemoId, @RefundDate, @Amount, @PaymentMethodId, @ReferenceNumber, @Memo);
    SET @RefundId = SCOPE_IDENTITY();

    UPDATE ar.InvoicePay SET AmountRefunded = AmountRefunded + @Amount, ModifiedAt = SYSUTCDATETIME()
    WHERE TenantId = @TenantId AND Id = @InvoicePayId;
    UPDATE ar.CreditMemo SET AmountRefunded = AmountRefunded + @Amount, ModifiedAt = SYSUTCDATETIME()
    WHERE TenantId = @TenantId AND Id = @CreditMemoId;

    COMMIT;
END;
