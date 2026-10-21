-- Submits a draft bill or expense report. With AP.RequireApproval off (for the submitting user), it goes straight to OPEN.
-- Sets DueDate from the payment term (bills without a term are due on BillDate).
CREATE PROCEDURE ap.usp_Bill_Submit
    @BillId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME(), @Require BIT, @Target VARCHAR(30);

    IF NOT EXISTS (
        SELECT 1 FROM ap.Bill AS b
        JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId AND s.SystemCode = 'DRAFT'
        WHERE b.TenantId = @TenantId AND b.Id = @BillId)
        THROW 50821, N'Only draft bills can be submitted.', 1;
    IF NOT EXISTS (SELECT 1 FROM ap.BillLine WHERE TenantId = @TenantId AND BillId = @BillId)
        THROW 50822, N'The bill has no lines.', 1;

    SELECT @Require = ISNULL(TRY_CAST(Value AS BIT), 1) FROM admin.fn_Setting(@TenantId, @UserId, 'AP.RequireApproval');
    SET @Target = CASE WHEN @Require = 1 THEN 'SUBMITTED' ELSE 'OPEN' END;

    BEGIN TRAN;

    EXEC ap.usp_Bill_Recalculate @BillId = @BillId;

    UPDATE b
    SET BillStatusId = s.Id,
        DueDate = COALESCE(b.DueDate, DATEADD(DAY, ISNULL(pt.DueDays, 0), b.BillDate)),
        SubmittedAt = @Now,
        ApprovedAt = CASE WHEN @Target = 'OPEN' THEN @Now END,
        ApprovedBy = CASE WHEN @Target = 'OPEN' THEN @UserId END,
        RejectedAt = NULL, RejectedBy = NULL, RejectedReason = NULL,
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM ap.Bill AS b
    JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.SystemCode = @Target
    LEFT JOIN lkp.PaymentTerm AS pt ON pt.TenantId = b.TenantId AND pt.Id = b.PaymentTermId
    WHERE b.TenantId = @TenantId AND b.Id = @BillId;

    COMMIT;
END;
