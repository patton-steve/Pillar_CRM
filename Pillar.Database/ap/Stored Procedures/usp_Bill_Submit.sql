-- Submits a draft bill or expense report. With AP.RequireApproval off (for the submitting user), it goes straight to OPEN.
-- Sets DueDate from the payment term (bills without a term are due on BillDate). A bill left waiting for approval
-- notifies everyone who can approve bills (BILL_AWAITING_APPROVAL). A weekly expense report (TimesheetId set) is refused:
-- it goes in with crm.usp_Timesheet_Submit.
CREATE PROCEDURE ap.usp_Bill_Submit
    @BillId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME(), @Require BIT, @Target VARCHAR(30);

    IF EXISTS (SELECT 1 FROM ap.Bill WHERE TenantId = @TenantId AND Id = @BillId AND TimesheetId IS NOT NULL)
        THROW 52312, N'This expense report goes with its timesheet week. Submit, approve or send back the week instead.', 1;

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

    IF @Target = 'SUBMITTED'
    BEGIN
        DECLARE @Title NVARCHAR(200);
        SELECT @Title = CONCAT(b.BillNumber, N' from ', COALESCE(v.Name, u.DisplayName), N' is waiting for approval')
        FROM ap.Bill AS b
        LEFT JOIN ap.Vendor AS v ON v.TenantId = b.TenantId AND v.Id = b.VendorId
        LEFT JOIN sec.AppUser AS u ON u.TenantId = b.TenantId AND u.Id = b.PayeeUserId
        WHERE b.TenantId = @TenantId AND b.Id = @BillId;
        EXEC sec.usp_Notification_Raise @NotificationType = 'BILL_AWAITING_APPROVAL', @EntityType = 'BILL',
             @EntityId = @BillId, @Title = @Title;
    END;

    COMMIT;
END;
