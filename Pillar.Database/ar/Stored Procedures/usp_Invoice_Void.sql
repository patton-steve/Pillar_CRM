-- Voids an issued invoice with no payments applied: status VOID, its time goes back to APPROVED and unlinked
-- (billable again in a later run), rebilled expenses and fixed-fee milestones are released, and a negative REVERSAL row offsets the platform fee. The number is kept.
CREATE PROCEDURE ar.usp_Invoice_Void
    @InvoiceId  INT,
    @Reason     NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME(), @Status VARCHAR(30), @Paid DECIMAL(19,2);

    IF NULLIF(LTRIM(@Reason), N'') IS NULL THROW 50621, N'A void reason is required.', 1;

    BEGIN TRAN;

    SELECT @Status = s.SystemCode, @Paid = i.AmountPaid
    FROM ar.Invoice AS i WITH (UPDLOCK)
    JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
    WHERE i.TenantId = @TenantId AND i.Id = @InvoiceId;

    IF @Status IS NULL OR @Status IN ('DRAFT', 'VOID') THROW 50622, N'Only issued invoices can be voided (delete drafts instead).', 1;
    IF @Paid <> 0 THROW 50623, N'Unapply payments from this invoice before voiding it.', 1;

    UPDATE e
    SET TimeEntryStatusId = s.Id, InvoiceEntryId = NULL, ModifiedAt = @Now, ModifiedBy = @UserId
    FROM crm.TimeEntry AS e
    JOIN ar.InvoiceEntry AS l ON l.TenantId = e.TenantId AND l.Id = e.InvoiceEntryId
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.SystemCode = 'APPROVED'
    WHERE e.TenantId = @TenantId AND l.InvoiceId = @InvoiceId;

    -- rebilled expenses become billable again
    UPDATE bl SET InvoiceEntryId = NULL
    FROM ap.BillLine AS bl
    JOIN ar.InvoiceEntry AS l ON l.TenantId = bl.TenantId AND l.Id = bl.InvoiceEntryId
    WHERE bl.TenantId = @TenantId AND l.InvoiceId = @InvoiceId;

    -- fixed-fee milestones become billable again
    UPDATE m SET InvoiceEntryId = NULL
    FROM crm.ProjectBillingMilestone AS m
    JOIN ar.InvoiceEntry AS l ON l.TenantId = m.TenantId AND l.Id = m.InvoiceEntryId
    WHERE m.TenantId = @TenantId AND l.InvoiceId = @InvoiceId;

    UPDATE i
    SET InvoiceStatusId = s.Id, VoidedAt = @Now, VoidedBy = @UserId, VoidReason = @Reason,
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM ar.Invoice AS i
    JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.SystemCode = 'VOID'
    WHERE i.TenantId = @TenantId AND i.Id = @InvoiceId;

    INSERT INTO admin.PlatformFee (TenantId, InvoiceId, FeeBaseAmount, FeeRate, FeeAmount, FeeStatus, ReversalOfFeeId)
    SELECT f.TenantId, f.InvoiceId, -f.FeeBaseAmount, f.FeeRate, -f.FeeAmount, 'REVERSAL', f.Id
    FROM admin.PlatformFee AS f
    WHERE f.TenantId = @TenantId AND f.InvoiceId = @InvoiceId AND f.ReversalOfFeeId IS NULL
      AND NOT EXISTS (SELECT 1 FROM admin.PlatformFee AS r WHERE r.ReversalOfFeeId = f.Id);

    COMMIT;
END;
