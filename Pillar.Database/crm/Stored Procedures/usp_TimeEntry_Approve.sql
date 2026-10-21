-- Approves a submitted entry and freezes its rate. Who may approve (time.approve) is checked by the API.
CREATE PROCEDURE crm.usp_TimeEntry_Approve
    @TimeEntryId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @ProjectId INT, @OwnerId INT, @TaskTypeId INT, @WorkDate DATE, @Rate DECIMAL(19,4), @RateSource VARCHAR(10);

    SELECT @ProjectId = e.ProjectId, @OwnerId = e.AppUserId, @TaskTypeId = t.TaskTypeId, @WorkDate = e.WorkDate
    FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
    JOIN crm.ClientTask AS t ON t.TenantId = e.TenantId AND t.Id = e.TaskId
    WHERE e.TenantId = @TenantId AND e.Id = @TimeEntryId AND e.DeletedAt IS NULL AND s.SystemCode = 'SUBMITTED';

    IF @ProjectId IS NULL THROW 50531, N'Only submitted entries can be approved.', 1;

    SELECT @Rate = Rate, @RateSource = RateSource
    FROM crm.fn_ResolveRate(@TenantId, @ProjectId, @OwnerId, @TaskTypeId, @WorkDate);

    UPDATE e
    SET TimeEntryStatusId = s.Id, ApprovedAt = @Now, ApprovedBy = @UserId,
        RateApplied = @Rate, RateSource = @RateSource,
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.SystemCode = 'APPROVED'
    WHERE e.TenantId = @TenantId AND e.Id = @TimeEntryId;

    DECLARE @SheetId INT = (SELECT TimesheetId FROM crm.TimeEntry WHERE TenantId = @TenantId AND Id = @TimeEntryId);
    EXEC crm.usp_Timesheet_SyncStatus @TenantId = @TenantId, @TimesheetId = @SheetId;
END;
