-- Approves every submitted entry on a week and freezes their rates. Who may approve (time.approve) is checked by the API.
-- Entries still in draft (added after the submit, or sent back one by one) are left alone and keep the week from showing APPROVED.
CREATE PROCEDURE crm.usp_Timesheet_Approve
    @TimesheetId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;

    UPDATE e
    SET TimeEntryStatusId = a.Id, ApprovedAt = @Now, ApprovedBy = @UserId,
        RateApplied = r.Rate, RateSource = r.RateSource,
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId AND s.SystemCode = 'SUBMITTED'
    JOIN lkp.TimeEntryStatus AS a ON a.TenantId = e.TenantId AND a.SystemCode = 'APPROVED'
    JOIN crm.ClientTask AS t ON t.TenantId = e.TenantId AND t.Id = e.TaskId
    OUTER APPLY crm.fn_ResolveRate(e.TenantId, e.ProjectId, e.AppUserId, t.TaskTypeId, e.WorkDate) AS r
    WHERE e.TenantId = @TenantId AND e.TimesheetId = @TimesheetId AND e.DeletedAt IS NULL;

    IF @@ROWCOUNT = 0 THROW 50586, N'There is no submitted time on this timesheet to approve.', 1;

    UPDATE crm.Timesheet SET ApprovedAt = @Now, ApprovedBy = @UserId WHERE TenantId = @TenantId AND Id = @TimesheetId;
    EXEC crm.usp_Timesheet_SyncStatus @TenantId = @TenantId, @TimesheetId = @TimesheetId;

    COMMIT;
END;
