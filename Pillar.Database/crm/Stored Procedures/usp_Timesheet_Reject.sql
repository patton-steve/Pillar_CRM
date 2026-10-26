-- Sends every submitted or approved entry on a week back to draft with one reason the person sees. Needs time.approve.
-- An approved week can be sent back only while none of its time is on an invoice (draft or issued); after that the
-- approver edits entries with crm.usp_TimeEntry_Update instead. To send back a single submitted entry,
-- use crm.usp_TimeEntry_Reject; the week then shows REJECTED until that entry is resubmitted.
-- The week's owner is notified (TIMESHEET_REJECTED) with the reason.
-- Handoff 23: the week's expense report goes back to DRAFT with it, while it is submitted, or approved with nothing paid
-- and no line on an invoice (52311 otherwise).
CREATE PROCEDURE crm.usp_Timesheet_Reject
    @TimesheetId    INT,
    @Reason         NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(), @TimeRows INT, @ExpRows INT;

    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'time.approve'))
        THROW 51604, N'You need permission to approve time to send a timesheet back.', 1;
    IF NULLIF(LTRIM(@Reason), N'') IS NULL THROW 50541, N'A rejection reason is required.', 1;
    IF EXISTS (SELECT 1 FROM crm.TimeEntry AS e
               JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
               WHERE e.TenantId = @TenantId AND e.TimesheetId = @TimesheetId AND e.DeletedAt IS NULL
                 AND (e.InvoiceEntryId IS NOT NULL OR s.SystemCode = 'INVOICED'))
        THROW 51605, N'Some of this week''s time is already on an invoice. Edit the entries instead, or remove them from the draft invoice first.', 1;

    IF EXISTS (SELECT 1 FROM ap.Bill AS b
               JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
               WHERE b.TenantId = @TenantId AND b.TimesheetId = @TimesheetId AND b.VoidedAt IS NULL AND s.SystemCode <> 'DRAFT'
                 AND (b.AmountPaid > 0 OR EXISTS (SELECT 1 FROM ap.BillLine AS l
                                                  WHERE l.TenantId = b.TenantId AND l.BillId = b.Id AND l.InvoiceEntryId IS NOT NULL)))
        THROW 52311, N'This week''s expenses are already reimbursed or billed to a client, so the week can''t be sent back.', 1;

    BEGIN TRAN;

    UPDATE e
    SET TimeEntryStatusId = d.Id, SubmittedAt = NULL,
        ApprovedAt = NULL, ApprovedBy = NULL,
        RejectedAt = @Now, RejectedBy = @UserId, RejectedReason = @Reason,
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
                                 AND (s.SystemCode = 'SUBMITTED' OR s.SystemCode = 'APPROVED')
    JOIN lkp.TimeEntryStatus AS d ON d.TenantId = e.TenantId AND d.SystemCode = 'DRAFT'
    WHERE e.TenantId = @TenantId AND e.TimesheetId = @TimesheetId AND e.DeletedAt IS NULL;

    SET @TimeRows = @@ROWCOUNT;

    UPDATE b
    SET BillStatusId = d.Id, SubmittedAt = NULL, ApprovedAt = NULL, ApprovedBy = NULL,
        RejectedAt = @Now, RejectedBy = @UserId, RejectedReason = @Reason,
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM ap.Bill AS b
    JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
                            AND (s.SystemCode = 'SUBMITTED' OR s.SystemCode = 'OPEN')
    JOIN lkp.BillStatus AS d ON d.TenantId = b.TenantId AND d.SystemCode = 'DRAFT'
    WHERE b.TenantId = @TenantId AND b.TimesheetId = @TimesheetId AND b.VoidedAt IS NULL;
    SET @ExpRows = @@ROWCOUNT;

    IF @TimeRows = 0 AND @ExpRows = 0 THROW 50587, N'There is no submitted or approved time or expenses on this timesheet to send back.', 1;

    UPDATE crm.Timesheet SET RejectedAt = @Now, RejectedBy = @UserId, RejectedReason = @Reason
    WHERE TenantId = @TenantId AND Id = @TimesheetId;
    EXEC crm.usp_Timesheet_SyncStatus @TenantId = @TenantId, @TimesheetId = @TimesheetId;

    DECLARE @Title NVARCHAR(200);
    SELECT @Title = CONCAT(N'Your week of ', FORMAT(WeekStart, 'MMM d', 'en-US'), N' was sent back')
    FROM crm.Timesheet WHERE TenantId = @TenantId AND Id = @TimesheetId;
    EXEC sec.usp_Notification_Raise @NotificationType = 'TIMESHEET_REJECTED', @EntityType = 'TIMESHEET',
         @EntityId = @TimesheetId, @Title = @Title, @Body = @Reason;

    COMMIT;
END;
