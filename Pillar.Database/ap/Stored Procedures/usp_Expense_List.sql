-- Time > My expenses for the week that covers @WeekOf (default today in the tenant's time zone). The session user's own,
-- or @ForUserId's with time.view_all. Result sets:
--   1 the week: timesheet and its status, the expense report (NULL until the first expense), its status, total and
--     the reason when it was sent back
--   2 the lines, with category, project, task, merchant, what Pilo read and the receipt attachment
CREATE PROCEDURE ap.usp_Expense_List
    @WeekOf     DATE = NULL,
    @ForUserId  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @OwnerId  INT, @BillId INT, @TimesheetId INT;
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52301, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    SET @OwnerId = ISNULL(@ForUserId, @UserId);
    IF @OwnerId <> @UserId AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'time.view_all'))
        THROW 52320, N'You need permission to see everyone''s time.', 1;

    IF @WeekOf IS NULL
        SELECT @WeekOf = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE t.TimeZoneId AS DATE)
        FROM admin.Tenant AS t WHERE t.Id = @TenantId;

    SELECT @TimesheetId = TimesheetId FROM crm.fn_WeekFor(@TenantId, @OwnerId, @WeekOf);
    SELECT @BillId = Id FROM ap.Bill WHERE TenantId = @TenantId AND TimesheetId = @TimesheetId AND VoidedAt IS NULL;

    SELECT @OwnerId AS AppUserId, w.WeekStart, w.WeekEnd, w.TimesheetId, ts.SystemCode AS TimesheetStatus,
           b.Id AS BillId, b.PublicId AS BillPublicId, b.BillNumber, bs.SystemCode AS ReportStatus, bs.Name AS ReportStatusName,
           b.Total, b.AmountPaid, b.BalanceDue, b.SubmittedAt, b.ApprovedAt, b.RejectedAt, b.RejectedReason,
           CONVERT(BIT, IIF(b.Id IS NULL OR bs.SystemCode = 'DRAFT', 1, 0)) AS CanEdit
    FROM crm.fn_WeekFor(@TenantId, @OwnerId, @WeekOf) AS w
    LEFT JOIN crm.Timesheet AS t ON t.TenantId = @TenantId AND t.Id = w.TimesheetId
    LEFT JOIN lkp.TimesheetStatus AS ts ON ts.TenantId = t.TenantId AND ts.Id = t.TimesheetStatusId
    LEFT JOIN ap.Bill AS b ON b.TenantId = @TenantId AND b.Id = @BillId
    LEFT JOIN lkp.BillStatus AS bs ON bs.TenantId = b.TenantId AND bs.Id = b.BillStatusId;

    SELECT l.Id AS BillLineId, l.LineNumber, l.ExpenseDate, l.ExpenseCategoryId, c.Name AS CategoryName, c.UnitName,
           l.Description, l.Merchant, l.Quantity, l.UnitPrice, l.Amount, l.IsBillable, l.MarkupPercent, l.BillableAmount,
           l.ProjectId, p.ProjectCode, p.Name AS ProjectName, l.TaskId, k.TaskKey, k.Title AS TaskTitle,
           CONVERT(BIT, IIF(l.InvoiceEntryId IS NULL, 0, 1)) AS IsInvoiced,
           l.ReceiptGenerationId, l.ReceiptReadJson, l.ReceiptConfidence,
           a.PublicId AS ReceiptPublicId, a.FileName AS ReceiptFileName, a.ContentType AS ReceiptContentType
    FROM ap.BillLine AS l
    JOIN lkp.ExpenseCategory AS c ON c.TenantId = l.TenantId AND c.Id = l.ExpenseCategoryId
    LEFT JOIN crm.ClientProject AS p ON p.TenantId = l.TenantId AND p.Id = l.ProjectId
    LEFT JOIN crm.ClientTask AS k ON k.TenantId = l.TenantId AND k.Id = l.TaskId
    OUTER APPLY (SELECT TOP (1) x.PublicId, x.FileName, x.ContentType FROM ap.BillAttachment AS x
                 WHERE x.TenantId = l.TenantId AND x.BillLineId = l.Id AND x.DeletedAt IS NULL ORDER BY x.UploadedAt DESC) AS a
    WHERE l.TenantId = @TenantId AND l.BillId = @BillId
    ORDER BY l.ExpenseDate, l.LineNumber;
END;
