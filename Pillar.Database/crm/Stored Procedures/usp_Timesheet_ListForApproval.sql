-- Time > Approvals: one row per person per week for the tab picked. Needs time.approve. The UI shows the sub-tab only
-- while TimeEntry.RequireApproval is on (with it off, submitting approves, so Submitted stays empty).
--   @Tab SUBMITTED  waiting for approval
--        APPROVED   approved, with billable time not yet on an issued invoice
--        REJECTED   sent back and not yet resubmitted
--        COMPLETE   approved and every billable entry is on an issued invoice (computed here, not a stored status;
--                   a voided invoice puts its entries back to APPROVED, so the week moves back by itself)
-- @PeriodFrom/@PeriodTo pick weeks that overlap the range (NULL = open ended). Expand a row with the week's entries.
-- Handoff 23: each week also carries its expense report (ap.usp_Expense_List shows the lines); a week with only expenses is listed.
CREATE PROCEDURE crm.usp_Timesheet_ListForApproval
    @Tab            VARCHAR(10) = 'SUBMITTED',
    @PeriodFrom     DATE = NULL,
    @PeriodTo       DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51601, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'time.approve'))
        THROW 51602, N'You need permission to approve time to see timesheet approvals.', 1;
    IF @Tab IS NULL OR NOT (@Tab = 'SUBMITTED' OR @Tab = 'APPROVED' OR @Tab = 'REJECTED' OR @Tab = 'COMPLETE')
        THROW 51603, N'Tab must be SUBMITTED, APPROVED, REJECTED or COMPLETE.', 1;

    WITH Sheet AS (
        SELECT t.Id AS TimesheetId, t.PublicId, t.AppUserId, u.DisplayName AS PersonName, t.WeekStart, t.WeekEnd,
               ts.SystemCode AS StatusCode, t.SubmittedAt, t.ApprovedAt, t.ApprovedBy, ab.DisplayName AS ApprovedByName,
               t.RejectedAt, t.RejectedReason,
               x.EntryCount, x.Hours, x.BillableHours, x.BillableAmount, x.InvoicedCount, x.UnbilledCount,
               CONVERT(BIT, IIF(ts.SystemCode = 'APPROVED' AND x.UnbilledCount = 0, 1, 0)) AS IsComplete,
               xr.BillId AS ExpenseBillId, xr.BillNumber AS ExpenseBillNumber, xr.StatusCode AS ExpenseStatus,
               ISNULL(xr.LineCount, 0) AS ExpenseCount, ISNULL(xr.Total, 0) AS ExpenseTotal
        FROM crm.Timesheet AS t
        JOIN lkp.TimesheetStatus AS ts ON ts.TenantId = t.TenantId AND ts.Id = t.TimesheetStatusId
        JOIN sec.AppUser AS u ON u.TenantId = t.TenantId AND u.Id = t.AppUserId
        LEFT JOIN sec.AppUser AS ab ON ab.TenantId = t.TenantId AND ab.Id = t.ApprovedBy
        CROSS APPLY (
            SELECT COUNT(*) AS EntryCount,
                   ISNULL(SUM(e.Hours), 0) AS Hours,
                   ISNULL(SUM(IIF(e.IsBillable = 1, e.Hours, 0)), 0) AS BillableHours,
                   ISNULL(SUM(e.AmountBillable), 0) AS BillableAmount,
                   ISNULL(SUM(IIF(es.SystemCode = 'INVOICED', 1, 0)), 0) AS InvoicedCount,
                   ISNULL(SUM(IIF(e.IsBillable = 1 AND es.SystemCode = 'APPROVED', 1, 0)), 0) AS UnbilledCount
            FROM crm.TimeEntry AS e
            JOIN lkp.TimeEntryStatus AS es ON es.TenantId = e.TenantId AND es.Id = e.TimeEntryStatusId
            WHERE e.TenantId = t.TenantId AND e.TimesheetId = t.Id AND e.DeletedAt IS NULL
        ) AS x
        OUTER APPLY (
            SELECT b.Id AS BillId, b.BillNumber, bs.SystemCode AS StatusCode, b.Total,
                   (SELECT COUNT(*) FROM ap.BillLine AS l WHERE l.TenantId = b.TenantId AND l.BillId = b.Id) AS LineCount
            FROM ap.Bill AS b
            JOIN lkp.BillStatus AS bs ON bs.TenantId = b.TenantId AND bs.Id = b.BillStatusId
            WHERE b.TenantId = t.TenantId AND b.TimesheetId = t.Id AND b.VoidedAt IS NULL
        ) AS xr
        WHERE t.TenantId = @TenantId
          AND (@PeriodFrom IS NULL OR t.WeekEnd >= @PeriodFrom)
          AND (@PeriodTo IS NULL OR t.WeekStart <= @PeriodTo)
          AND (x.EntryCount > 0 OR xr.LineCount > 0)
    )
    SELECT TimesheetId, PublicId, AppUserId, PersonName, WeekStart, WeekEnd, StatusCode, IsComplete,
           EntryCount, Hours, BillableHours, BillableAmount, InvoicedCount,
           SubmittedAt, ApprovedAt, ApprovedBy, ApprovedByName, RejectedAt, RejectedReason,
           ExpenseBillId, ExpenseBillNumber, ExpenseStatus, ExpenseCount, ExpenseTotal
    FROM Sheet
    WHERE (@Tab = 'COMPLETE' AND IsComplete = 1)
       OR (@Tab = 'APPROVED' AND StatusCode = 'APPROVED' AND IsComplete = 0)
       OR (@Tab <> 'COMPLETE' AND @Tab <> 'APPROVED' AND StatusCode = @Tab)
    ORDER BY WeekStart DESC, PersonName;
END;
