-- Voids a bill with no payments applied whose expenses are not on a live client invoice.
CREATE PROCEDURE ap.usp_Bill_Void
    @BillId     INT,
    @Reason     NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT), @Now DATETIME2(0) = SYSUTCDATETIME(),
            @Status VARCHAR(30), @Paid DECIMAL(19,2);

    IF NULLIF(LTRIM(@Reason), N'') IS NULL THROW 50851, N'A void reason is required.', 1;

    BEGIN TRAN;

    SELECT @Status = s.SystemCode, @Paid = b.AmountPaid
    FROM ap.Bill AS b WITH (UPDLOCK)
    JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
    WHERE b.TenantId = @TenantId AND b.Id = @BillId;

    IF @Status IS NULL OR @Status = 'VOID' THROW 50852, N'Bill not found or already void.', 1;
    IF @Paid <> 0 THROW 50853, N'Unapply payments from this bill before voiding it.', 1;
    IF EXISTS (SELECT 1 FROM ap.BillLine WHERE TenantId = @TenantId AND BillId = @BillId AND InvoiceEntryId IS NOT NULL)
        THROW 50854, N'Some expenses on this bill are on a client invoice. Remove them from the invoice first.', 1;

    UPDATE b
    SET BillStatusId = v.Id, VoidedAt = @Now, VoidedBy = @UserId, VoidReason = @Reason, ModifiedAt = @Now, ModifiedBy = @UserId
    FROM ap.Bill AS b
    JOIN lkp.BillStatus AS v ON v.TenantId = b.TenantId AND v.SystemCode = 'VOID'
    WHERE b.TenantId = @TenantId AND b.Id = @BillId;

    COMMIT;
END;
