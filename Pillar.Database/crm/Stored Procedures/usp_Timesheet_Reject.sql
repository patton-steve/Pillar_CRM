-- Sends every submitted entry on a week back to draft with one reason the person sees. To send back a single entry,
-- use crm.usp_TimeEntry_Reject; the week then shows REJECTED until that entry is resubmitted.
CREATE PROCEDURE crm.usp_Timesheet_Reject
    @TimesheetId    INT,
    @Reason         NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME();

    IF NULLIF(LTRIM(@Reason), N'') IS NULL THROW 50541, N'A rejection reason is required.', 1;

    BEGIN TRAN;

    UPDATE e
    SET TimeEntryStatusId = d.Id, SubmittedAt = NULL,
        RejectedAt = @Now, RejectedBy = @UserId, RejectedReason = @Reason,
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId AND s.SystemCode = 'SUBMITTED'
    JOIN lkp.TimeEntryStatus AS d ON d.TenantId = e.TenantId AND d.SystemCode = 'DRAFT'
    WHERE e.TenantId = @TenantId AND e.TimesheetId = @TimesheetId AND e.DeletedAt IS NULL;

    IF @@ROWCOUNT = 0 THROW 50587, N'There is no submitted time on this timesheet to reject.', 1;

    UPDATE crm.Timesheet SET RejectedAt = @Now, RejectedBy = @UserId, RejectedReason = @Reason
    WHERE TenantId = @TenantId AND Id = @TimesheetId;
    EXEC crm.usp_Timesheet_SyncStatus @TenantId = @TenantId, @TimesheetId = @TimesheetId;

    COMMIT;
END;
