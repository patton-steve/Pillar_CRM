-- Creates (@TimeEntryId NULL) or updates a draft time entry for the session user, or for @ForUserId when the session user
-- holds time.enter_others (e.g. an owner entering a no-login subcontractor's hours).
-- Duration input depends on TimeEntry.EntryMode:
--   HOUR / HALF_HOUR / QUARTER_HOUR / EXACT -> @Minutes (the API converts 1.25 h or 1:15 to 75)
--   START_END -> @StartTime and @EndTime (@EndTime NULL starts a timer)
-- Checks: user is an active ProjectUser; project OPEN; task not DONE/CANCELLED; client ACTIVE.
-- Timesheets: the entry is filed on the owner's week (crm.usp_Timesheet_Ensure). Drafts are always editable. A submitted
-- entry is editable only when Timesheet.LockOnSubmit is off, and editing sends it back to draft. New time on a submitted
-- week needs LockOnSubmit off or Timesheet.AllowResubmit on; new time on an approved week needs time.approve.
-- TimeEntry.NoteRequired makes Description mandatory once the entry has a duration (a running timer may start without one).
CREATE PROCEDURE crm.usp_TimeEntry_Save
    @TimeEntryId    INT = NULL OUTPUT,
    @TaskId         INT,
    @WorkDate       DATE,
    @Minutes        INT = NULL,
    @StartTime      TIME(0) = NULL,
    @EndTime        TIME(0) = NULL,
    @Description    NVARCHAR(2000) = NULL,
    @InternalNote   NVARCHAR(2000) = NULL,
    @IsBillable     BIT = NULL,
    @ForUserId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @Actor    INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @UserId   INT,      -- whose time this is
            @Mode VARCHAR(12), @Rounding INT, @Billed INT,
            @ProjectId INT, @TaskTypeId INT, @TaskBillable BIT, @BillingType VARCHAR(30),
            @ProjectStatus VARCHAR(30), @TaskStatus VARCHAR(30), @ClientStatus VARCHAR(30),
            @Rate DECIMAL(19,4), @RateSource VARCHAR(10), @DraftId INT,
            @LockOnSubmit BIT, @AllowResubmit BIT, @NoteRequired BIT,
            @OldSheetId INT, @SheetId INT, @SheetStatus VARCHAR(30);

    IF @TenantId IS NULL OR @Actor IS NULL THROW 50501, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    SET @UserId = COALESCE(@ForUserId, @Actor);
    IF @UserId <> @Actor AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @Actor, 'time.enter_others'))
        THROW 50512, N'You can only enter your own time.', 1;

    SELECT @ProjectId = t.ProjectId, @TaskTypeId = t.TaskTypeId, @TaskBillable = t.IsBillable,
           @TaskStatus = ts.SystemCode, @ProjectStatus = ps.SystemCode, @BillingType = bt.SystemCode,
           @ClientStatus = cs.SystemCode
    FROM crm.ClientTask AS t
    JOIN lkp.TaskStatus AS ts ON ts.TenantId = t.TenantId AND ts.Id = t.TaskStatusId
    JOIN crm.ClientProject AS p ON p.TenantId = t.TenantId AND p.Id = t.ProjectId
    JOIN lkp.ProjectStatus AS ps ON ps.TenantId = p.TenantId AND ps.Id = p.ProjectStatusId
    JOIN lkp.BillingType AS bt ON bt.TenantId = p.TenantId AND bt.Id = p.BillingTypeId
    JOIN crm.Client AS c ON c.TenantId = p.TenantId AND c.Id = p.ClientId
    JOIN lkp.ClientStatus AS cs ON cs.TenantId = c.TenantId AND cs.Id = c.ClientStatusId
    WHERE t.TenantId = @TenantId AND t.Id = @TaskId AND t.DeletedAt IS NULL AND p.DeletedAt IS NULL;

    IF @ProjectId IS NULL THROW 50502, N'Task not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.ProjectUser WHERE TenantId = @TenantId AND ProjectId = @ProjectId AND AppUserId = @UserId AND IsActive = 1)
        THROW 50503, N'This person is not assigned to this project.', 1;
    IF @ProjectStatus <> 'OPEN' THROW 50504, N'The project is not open for time entry.', 1;
    IF @TaskStatus IN ('DONE', 'CANCELLED') THROW 50505, N'The task is closed for time entry.', 1;
    IF @ClientStatus <> 'ACTIVE' THROW 50506, N'The client is not active.', 1;

    SELECT @LockOnSubmit = ISNULL(TRY_CONVERT(BIT, Value), 1) FROM admin.fn_Setting(@TenantId, @UserId, 'Timesheet.LockOnSubmit');
    SELECT @AllowResubmit = ISNULL(TRY_CONVERT(BIT, Value), 1) FROM admin.fn_Setting(@TenantId, @UserId, 'Timesheet.AllowResubmit');
    SELECT @NoteRequired = ISNULL(TRY_CONVERT(BIT, Value), 0) FROM admin.fn_Setting(@TenantId, @UserId, 'TimeEntry.NoteRequired');

    IF @TimeEntryId IS NOT NULL
    BEGIN
        SELECT @DraftId = e.Id, @Mode = e.EntryMode, @OldSheetId = e.TimesheetId
        FROM crm.TimeEntry AS e
        JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
        WHERE e.TenantId = @TenantId AND e.Id = @TimeEntryId AND e.AppUserId = @UserId
          AND e.DeletedAt IS NULL AND (s.SystemCode = 'DRAFT' OR (s.SystemCode = 'SUBMITTED' AND @LockOnSubmit = 0));
        IF @DraftId IS NULL THROW 50507, N'Only draft entries for this person can be edited.', 1;
    END
    ELSE
        SELECT @Mode = CAST(Value AS VARCHAR(12)) FROM admin.fn_Setting(@TenantId, @UserId, 'TimeEntry.EntryMode');

    SELECT @Rounding = ISNULL(TRY_CAST(Value AS INT), 0) FROM admin.fn_Setting(@TenantId, @UserId, 'TimeEntry.RoundingMinutes');

    IF @Mode = 'START_END'
    BEGIN
        IF @StartTime IS NULL THROW 50508, N'Start time is required.', 1;
        SET @Minutes = CASE WHEN @EndTime IS NULL THEN NULL
                            ELSE (DATEDIFF(MINUTE, @StartTime, @EndTime) + 1440) % 1440 END;
        IF @Minutes = 0 THROW 50509, N'End time must differ from start time.', 1;
    END
    ELSE
    BEGIN
        IF @Minutes IS NULL OR @Minutes < 1 THROW 50510, N'Time must be greater than zero.', 1;
        IF (@Mode = 'HOUR' AND @Minutes % 60 <> 0) OR (@Mode = 'HALF_HOUR' AND @Minutes % 30 <> 0)
           OR (@Mode = 'QUARTER_HOUR' AND @Minutes % 15 <> 0)
            THROW 50511, N'Time must be entered in the tenant''s required increment.', 1;
        SELECT @StartTime = NULL, @EndTime = NULL;
    END;

    SET @Billed = CASE WHEN @Minutes IS NULL THEN NULL
                       WHEN @Mode IN ('EXACT', 'START_END') AND @Rounding > 0
                            THEN CEILING(@Minutes / CAST(@Rounding AS DECIMAL(9,4))) * @Rounding
                       ELSE @Minutes END;
    IF @Billed > 1440 SET @Billed = 1440;

    IF @NoteRequired = 1 AND @Minutes IS NOT NULL AND NULLIF(LTRIM(RTRIM(@Description)), N'') IS NULL
        THROW 50513, N'A description is required for every time entry.', 1;

    -- non-billable project types never bill; otherwise caller, then task default
    SET @IsBillable = CASE WHEN @BillingType = 'NONBILL' THEN 0 ELSE COALESCE(@IsBillable, @TaskBillable) END;

    SELECT @Rate = Rate, @RateSource = RateSource
    FROM crm.fn_ResolveRate(@TenantId, @ProjectId, @UserId, @TaskTypeId, @WorkDate);

    BEGIN TRAN;

    EXEC crm.usp_Timesheet_Ensure @TenantId = @TenantId, @AppUserId = @UserId, @WorkDate = @WorkDate, @TimesheetId = @SheetId OUTPUT;

    IF @OldSheetId IS NULL OR @OldSheetId <> @SheetId
    BEGIN
        SELECT @SheetStatus = s.SystemCode
        FROM crm.Timesheet AS t
        JOIN lkp.TimesheetStatus AS s ON s.TenantId = t.TenantId AND s.Id = t.TimesheetStatusId
        WHERE t.TenantId = @TenantId AND t.Id = @SheetId;

        IF @SheetStatus = 'SUBMITTED' AND @LockOnSubmit = 1 AND @AllowResubmit = 0
            THROW 50514, N'This week has been submitted. Ask your approver to send it back before adding time.', 1;
        IF @SheetStatus = 'APPROVED' AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @Actor, 'time.approve'))
            THROW 50515, N'This week has been approved. Ask your approver to add the time.', 1;
    END;

    IF @TimeEntryId IS NULL
    BEGIN
        INSERT INTO crm.TimeEntry
            (TenantId, ProjectId, TaskId, AppUserId, WorkDate, EntryMode, StartTime, EndTime, EnteredMinutes, BilledMinutes,
             Description, InternalNote, IsBillable, RateApplied, RateSource, TimeEntryStatusId, TimesheetId)
        SELECT @TenantId, @ProjectId, @TaskId, @UserId, @WorkDate, @Mode, @StartTime, @EndTime, @Minutes, @Billed,
               @Description, @InternalNote, @IsBillable, @Rate, @RateSource, s.Id, @SheetId
        FROM lkp.TimeEntryStatus AS s
        WHERE s.TenantId = @TenantId AND s.SystemCode = 'DRAFT';

        SET @TimeEntryId = SCOPE_IDENTITY();
    END
    ELSE
        -- editing a submitted entry (LockOnSubmit off) sends it back to draft
        UPDATE e
        SET ProjectId = @ProjectId, TaskId = @TaskId, WorkDate = @WorkDate, StartTime = @StartTime, EndTime = @EndTime,
            EnteredMinutes = @Minutes, BilledMinutes = @Billed, Description = @Description, InternalNote = @InternalNote,
            IsBillable = @IsBillable, RateApplied = @Rate, RateSource = @RateSource,
            TimeEntryStatusId = d.Id, SubmittedAt = NULL, TimesheetId = @SheetId,
            ModifiedAt = SYSUTCDATETIME(), ModifiedBy = @Actor
        FROM crm.TimeEntry AS e
        JOIN lkp.TimeEntryStatus AS d ON d.TenantId = e.TenantId AND d.SystemCode = 'DRAFT'
        WHERE e.TenantId = @TenantId AND e.Id = @TimeEntryId;

    EXEC crm.usp_Timesheet_SyncStatus @TenantId = @TenantId, @TimesheetId = @SheetId;
    IF @OldSheetId <> @SheetId EXEC crm.usp_Timesheet_SyncStatus @TenantId = @TenantId, @TimesheetId = @OldSheetId;

    COMMIT;
END;
