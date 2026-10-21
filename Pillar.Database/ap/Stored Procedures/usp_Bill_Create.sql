-- Starts a draft vendor bill (@VendorId) or expense report (@PayeeUserId; defaults to the session user when
-- neither is passed). Numbered now from NumberSequence 'BILL' or 'EXPENSE'. Add lines to ap.BillLine, then submit.
CREATE PROCEDURE ap.usp_Bill_Create
    @VendorId               INT = NULL,
    @PayeeUserId            INT = NULL,
    @BillDate               DATE = NULL,
    @VendorInvoiceNumber    NVARCHAR(50) = NULL,
    @PaymentTermId          INT = NULL,
    @Description            NVARCHAR(500) = NULL,
    @BillId                 INT = NULL OUTPUT,
    @BillNumber             NVARCHAR(50) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT), @Number INT;

    IF @VendorId IS NOT NULL AND @PayeeUserId IS NOT NULL THROW 50811, N'A bill is for a vendor or a user, not both.', 1;
    IF @VendorId IS NULL SET @PayeeUserId = COALESCE(@PayeeUserId, CAST(SESSION_CONTEXT(N'UserId') AS INT));

    IF @BillDate IS NULL
        SELECT @BillDate = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE t.TimeZoneId AS DATE)
        FROM admin.Tenant AS t WHERE t.Id = @TenantId;

    IF @VendorId IS NOT NULL
        SELECT @PaymentTermId = COALESCE(@PaymentTermId, v.PaymentTermId)
        FROM ap.Vendor AS v WHERE v.TenantId = @TenantId AND v.Id = @VendorId;

    BEGIN TRAN;

    DECLARE @SeqKey VARCHAR(30) = CASE WHEN @VendorId IS NOT NULL THEN 'BILL' ELSE 'EXPENSE' END;
    EXEC admin.usp_NextNumber @TenantId = @TenantId, @SequenceKey = @SeqKey, @Count = 1,
         @FirstValue = @Number OUTPUT, @Formatted = @BillNumber OUTPUT;

    INSERT INTO ap.Bill (TenantId, VendorId, PayeeUserId, BillNumber, VendorInvoiceNumber, BillDate, PaymentTermId, BillStatusId, Description)
    SELECT @TenantId, @VendorId, @PayeeUserId, @BillNumber, @VendorInvoiceNumber, @BillDate, @PaymentTermId, s.Id, @Description
    FROM lkp.BillStatus AS s WHERE s.TenantId = @TenantId AND s.SystemCode = 'DRAFT';

    SET @BillId = SCOPE_IDENTITY();

    COMMIT;
END;
