-- Sends a submitted entry back to Draft with a reason the user sees.
CREATE PROCEDURE crm.usp_TimeEntry_Reject
    @TimeEntryId    INT,
    @Reason         NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME();

    IF NULLIF(LTRIM(@Reason), N'') IS NULL THROW 50541, N'A rejection reason is required.', 1;

    UPDATE e
    SET TimeEntryStatusId = d.Id, SubmittedAt = NULL,
        RejectedAt = @Now, RejectedBy = @UserId, RejectedReason = @Reason,
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId AND s.SystemCode = 'SUBMITTED'
    JOIN lkp.TimeEntryStatus AS d ON d.TenantId = e.TenantId AND d.SystemCode = 'DRAFT'
    WHERE e.TenantId = @TenantId AND e.Id = @TimeEntryId AND e.DeletedAt IS NULL;

    IF @@ROWCOUNT = 0 THROW 50542, N'Only submitted entries can be rejected.', 1;

    DECLARE @SheetId INT = (SELECT TimesheetId FROM crm.TimeEntry WHERE TenantId = @TenantId AND Id = @TimeEntryId);
    EXEC crm.usp_Timesheet_SyncStatus @TenantId = @TenantId, @TimesheetId = @SheetId;
END;
