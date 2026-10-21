-- Submits a draft: the session user's own, or anyone's when the session user holds time.enter_others.
-- When TimeEntry.RequireApproval is off for the entry's owner (tenant setting or per-user override),
-- the entry is approved in the same step.
CREATE PROCEDURE crm.usp_TimeEntry_Submit
    @TimeEntryId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @Actor    INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @UserId   INT,      -- the entry's owner
            @Require  BIT, @Target VARCHAR(30), @Now DATETIME2(0) = SYSUTCDATETIME(),
            @ProjectId INT, @TaskTypeId INT, @WorkDate DATE, @Rate DECIMAL(19,4), @RateSource VARCHAR(10);

    SELECT @ProjectId = e.ProjectId, @TaskTypeId = t.TaskTypeId, @WorkDate = e.WorkDate, @UserId = e.AppUserId
    FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
    JOIN crm.ClientTask AS t ON t.TenantId = e.TenantId AND t.Id = e.TaskId
    WHERE e.TenantId = @TenantId AND e.Id = @TimeEntryId
      AND (e.AppUserId = @Actor OR EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @Actor, 'time.enter_others')))
      AND e.DeletedAt IS NULL AND s.SystemCode = 'DRAFT' AND e.EnteredMinutes IS NOT NULL;

    IF @ProjectId IS NULL THROW 50521, N'Only completed draft entries you may enter can be submitted (stop a running timer first).', 1;

    IF EXISTS (SELECT 1 FROM admin.fn_Setting(@TenantId, @UserId, 'TimeEntry.NoteRequired') WHERE TRY_CONVERT(BIT, Value) = 1)
       AND EXISTS (SELECT 1 FROM crm.TimeEntry WHERE TenantId = @TenantId AND Id = @TimeEntryId AND NULLIF(LTRIM(RTRIM(Description)), N'') IS NULL)
        THROW 50513, N'A description is required for every time entry.', 1;

    SELECT @Require = ISNULL(TRY_CAST(Value AS BIT), 1) FROM admin.fn_Setting(@TenantId, @UserId, 'TimeEntry.RequireApproval');
    SET @Target = CASE WHEN @Require = 1 THEN 'SUBMITTED' ELSE 'APPROVED' END;

    SELECT @Rate = Rate, @RateSource = RateSource
    FROM crm.fn_ResolveRate(@TenantId, @ProjectId, @UserId, @TaskTypeId, @WorkDate);

    UPDATE e
    SET TimeEntryStatusId = s.Id,
        SubmittedAt = @Now,
        ApprovedAt  = CASE WHEN @Target = 'APPROVED' THEN @Now END,
        ApprovedBy  = CASE WHEN @Target = 'APPROVED' THEN @Actor END,
        RateApplied = @Rate, RateSource = @RateSource,
        RejectedAt = NULL, RejectedBy = NULL, RejectedReason = NULL,
        ModifiedAt = @Now, ModifiedBy = @Actor
    FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.SystemCode = @Target
    WHERE e.TenantId = @TenantId AND e.Id = @TimeEntryId;

    DECLARE @SheetId INT = (SELECT TimesheetId FROM crm.TimeEntry WHERE TenantId = @TenantId AND Id = @TimeEntryId);
    EXEC crm.usp_Timesheet_SyncStatus @TenantId = @TenantId, @TimesheetId = @SheetId;
END;
