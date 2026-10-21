-- Applies @Amount from a payment (@InvoicePayId) or credit memo (@CreditMemoId) to an issued invoice of the same client.
-- @Amount NULL = as much as possible (the smaller of the invoice balance and the source's unapplied amount).
CREATE PROCEDURE ar.usp_InvoicePay_Apply
    @InvoiceId      INT,
    @InvoicePayId   INT = NULL,
    @CreditMemoId   INT = NULL,
    @Amount         DECIMAL(19,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @ClientId INT, @Balance DECIMAL(19,2), @Status VARCHAR(30),
            @SourceClientId INT, @Available DECIMAL(19,2);

    IF (@InvoicePayId IS NULL AND @CreditMemoId IS NULL) OR (@InvoicePayId IS NOT NULL AND @CreditMemoId IS NOT NULL)
        THROW 50701, N'Pass either @InvoicePayId or @CreditMemoId.', 1;

    BEGIN TRAN;

    SELECT @ClientId = i.ClientId, @Balance = i.BalanceDue, @Status = s.SystemCode
    FROM ar.Invoice AS i WITH (UPDLOCK)
    JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
    WHERE i.TenantId = @TenantId AND i.Id = @InvoiceId;

    IF @Status IS NULL OR @Status NOT IN ('ISSUED', 'PARTIAL') THROW 50702, N'Payments can only be applied to issued, unpaid invoices.', 1;

    IF @InvoicePayId IS NOT NULL
        SELECT @SourceClientId = ClientId, @Available = UnappliedAmount
        FROM ar.InvoicePay WITH (UPDLOCK)
        WHERE TenantId = @TenantId AND Id = @InvoicePayId AND VoidedAt IS NULL;
    ELSE
        SELECT @SourceClientId = ClientId, @Available = UnappliedAmount
        FROM ar.CreditMemo WITH (UPDLOCK)
        WHERE TenantId = @TenantId AND Id = @CreditMemoId AND VoidedAt IS NULL;

    IF @SourceClientId IS NULL THROW 50703, N'Payment or credit not found, or it is void.', 1;
    IF @SourceClientId <> @ClientId THROW 50704, N'The payment or credit belongs to a different client.', 1;

    SET @Amount = COALESCE(@Amount, CASE WHEN @Balance < @Available THEN @Balance ELSE @Available END);
    IF @Amount <= 0 THROW 50705, N'Nothing to apply.', 1;
    IF @Amount > @Balance THROW 50706, N'Amount is more than the invoice balance.', 1;
    IF @Amount > @Available THROW 50707, N'Amount is more than the unapplied amount.', 1;

    INSERT INTO ar.InvoicePayApplication (TenantId, ClientId, InvoiceId, InvoicePayId, CreditMemoId, AmountApplied)
    VALUES (@TenantId, @ClientId, @InvoiceId, @InvoicePayId, @CreditMemoId, @Amount);

    EXEC ar.usp_ApplicationTotals_Sync @InvoiceId = @InvoiceId, @InvoicePayId = @InvoicePayId, @CreditMemoId = @CreditMemoId;

    COMMIT;
END;
