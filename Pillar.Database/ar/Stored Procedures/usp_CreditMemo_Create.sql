-- Issues a numbered credit memo for a client. With @SourceInvoiceId and @ApplyToSource = 1 it is applied
-- straight to that invoice's balance (any excess stays as client credit).
CREATE PROCEDURE ar.usp_CreditMemo_Create
    @ClientId           INT,
    @Amount             DECIMAL(19,2),
    @Reason             NVARCHAR(500),
    @CreditDate         DATE = NULL,
    @SourceInvoiceId    INT = NULL,
    @ApplyToSource      BIT = 1,
    @CreditMemoId       INT = NULL OUTPUT,
    @CreditMemoNumber   NVARCHAR(50) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT), @Number INT, @Balance DECIMAL(19,2);

    IF NULLIF(LTRIM(@Reason), N'') IS NULL THROW 50731, N'A reason is required.', 1;

    IF @CreditDate IS NULL
        SELECT @CreditDate = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE t.TimeZoneId AS DATE)
        FROM admin.Tenant AS t WHERE t.Id = @TenantId;

    BEGIN TRAN;

    EXEC admin.usp_NextNumber @TenantId = @TenantId, @SequenceKey = 'CREDITMEMO', @Count = 1,
         @FirstValue = @Number OUTPUT, @Formatted = @CreditMemoNumber OUTPUT;

    INSERT INTO ar.CreditMemo (TenantId, ClientId, CreditMemoNumber, CreditDate, Amount, Reason, SourceInvoiceId)
    VALUES (@TenantId, @ClientId, @CreditMemoNumber, @CreditDate, @Amount, @Reason, @SourceInvoiceId);
    SET @CreditMemoId = SCOPE_IDENTITY();

    IF @SourceInvoiceId IS NOT NULL AND @ApplyToSource = 1
    BEGIN
        SELECT @Balance = i.BalanceDue
        FROM ar.Invoice AS i
        JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId AND s.SystemCode IN ('ISSUED', 'PARTIAL')
        WHERE i.TenantId = @TenantId AND i.Id = @SourceInvoiceId;

        IF @Balance > 0
        BEGIN
            SET @Balance = CASE WHEN @Balance < @Amount THEN @Balance ELSE @Amount END;
            EXEC ar.usp_InvoicePay_Apply @InvoiceId = @SourceInvoiceId, @CreditMemoId = @CreditMemoId, @Amount = @Balance;
        END;
    END;

    COMMIT;
END;
