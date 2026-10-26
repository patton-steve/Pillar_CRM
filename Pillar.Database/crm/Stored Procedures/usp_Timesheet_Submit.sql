-- Submits every draft entry on a week: the session user's own week, or anyone's when the session user holds
-- time.enter_others. Refused while a timer is running on the week, when there is nothing to submit, or when
-- TimeEntry.NoteRequired is on and an entry has no description. When TimeEntry.RequireApproval resolves to 0 for the
-- week's owner, the entries are approved (rate frozen) in the same step, as usp_TimeEntry_Submit does for one entry.
-- A week left waiting for approval notifies everyone who can approve time (TIMESHEET_SUBMITTED).
-- Handoff 23: the week's draft expense report (ap.Bill.TimesheetId) is submitted in the same step. It follows
-- AP.RequireApproval for the owner (off: it goes straight to OPEN). A week with only expenses can be submitted too.
CREATE PROCEDURE crm.usp_Timesheet_Submit
    @TimesheetId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @Actor    INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @OwnerId INT, @Require BIT, @NoteRequired BIT, @Target VARCHAR(30),
            @ReportId INT, @ExpRequire BIT, @ExpTarget VARCHAR(30);

    IF @TenantId IS NULL OR @Actor IS NULL THROW 50501, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    SELECT @OwnerId = AppUserId FROM crm.Timesheet WHERE TenantId = @TenantId AND Id = @TimesheetId;
    IF @OwnerId IS NULL THROW 50582, N'Timesheet not found.', 1;
    IF @OwnerId <> @Actor AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @Actor, 'time.enter_others'))
        THROW 50512, N'You can only enter your own time.', 1;

    SELECT @Require = ISNULL(TRY_CONVERT(BIT, Value), 1) FROM admin.fn_Setting(@TenantId, @OwnerId, 'TimeEntry.RequireApproval');
    SELECT @NoteRequired = ISNULL(TRY_CONVERT(BIT, Value), 0) FROM admin.fn_Setting(@TenantId, @OwnerId, 'TimeEntry.NoteRequired');
    SET @Target = CASE WHEN @Require = 1 THEN 'SUBMITTED' ELSE 'APPROVED' END;
    SELECT @ExpRequire = ISNULL(TRY_CONVERT(BIT, Value), 1) FROM admin.fn_Setting(@TenantId, @OwnerId, 'AP.RequireApproval');
    SET @ExpTarget = CASE WHEN @ExpRequire = 1 THEN 'SUBMITTED' ELSE 'OPEN' END;

    BEGIN TRAN;

    DECLARE @Draft TABLE (Id INT PRIMARY KEY, Running BIT, NoNote BIT);
    INSERT INTO @Draft (Id, Running, NoNote)
    SELECT e.Id, IIF(e.EnteredMinutes IS NULL, 1, 0), IIF(NULLIF(LTRIM(RTRIM(e.Description)), N'') IS NULL, 1, 0)
    FROM crm.TimeEntry AS e WITH (UPDLOCK)
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
    WHERE e.TenantId = @TenantId AND e.TimesheetId = @TimesheetId AND e.DeletedAt IS NULL AND s.SystemCode = 'DRAFT';

    SELECT @ReportId = b.Id
    FROM ap.Bill AS b WITH (UPDLOCK)
    JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId AND s.SystemCode = 'DRAFT'
    WHERE b.TenantId = @TenantId AND b.TimesheetId = @TimesheetId AND b.VoidedAt IS NULL
      AND EXISTS (SELECT 1 FROM ap.BillLine AS l WHERE l.TenantId = b.TenantId AND l.BillId = b.Id);

    IF NOT EXISTS (SELECT 1 FROM @Draft) AND @ReportId IS NULL
        THROW 50583, N'There is no unsubmitted time or expenses on this timesheet.', 1;
    IF EXISTS (SELECT 1 FROM @Draft WHERE Running = 1) THROW 50584, N'Stop the running timer before submitting the week.', 1;
    IF @NoteRequired = 1 AND EXISTS (SELECT 1 FROM @Draft WHERE NoNote = 1)
        THROW 50585, N'Every entry needs a description before the week can be submitted.', 1;

    UPDATE e
    SET TimeEntryStatusId = st.Id,
        SubmittedAt = @Now,
        ApprovedAt  = CASE WHEN @Target = 'APPROVED' THEN @Now END,
        ApprovedBy  = CASE WHEN @Target = 'APPROVED' THEN @Actor END,
        RateApplied = r.Rate, RateSource = r.RateSource,
        RejectedAt = NULL, RejectedBy = NULL, RejectedReason = NULL,
        ModifiedAt = @Now, ModifiedBy = @Actor
    FROM crm.TimeEntry AS e
    JOIN @Draft AS d ON d.Id = e.Id
    JOIN crm.ClientTask AS t ON t.TenantId = e.TenantId AND t.Id = e.TaskId
    JOIN lkp.TimeEntryStatus AS st ON st.TenantId = e.TenantId AND st.SystemCode = @Target
    OUTER APPLY crm.fn_ResolveRate(e.TenantId, e.ProjectId, e.AppUserId, t.TaskTypeId, e.WorkDate) AS r
    WHERE e.TenantId = @TenantId;

    IF @ReportId IS NOT NULL
    BEGIN
        EXEC ap.usp_Bill_Recalculate @BillId = @ReportId;
        UPDATE b
        SET BillStatusId = s.Id,
            DueDate = COALESCE(b.DueDate, b.BillDate),
            SubmittedAt = @Now,
            ApprovedAt = CASE WHEN @ExpTarget = 'OPEN' THEN @Now END,
            ApprovedBy = CASE WHEN @ExpTarget = 'OPEN' THEN @Actor END,
            RejectedAt = NULL, RejectedBy = NULL, RejectedReason = NULL,
            ModifiedAt = @Now, ModifiedBy = @Actor
        FROM ap.Bill AS b
        JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.SystemCode = @ExpTarget
        WHERE b.TenantId = @TenantId AND b.Id = @ReportId;
    END;

    UPDATE crm.Timesheet
    SET SubmittedAt = @Now, SubmittedBy = @Actor,
        ApprovedAt = CASE WHEN @Target = 'APPROVED' AND EXISTS (SELECT 1 FROM @Draft) THEN @Now ELSE ApprovedAt END,
        ApprovedBy = CASE WHEN @Target = 'APPROVED' AND EXISTS (SELECT 1 FROM @Draft) THEN @Actor ELSE ApprovedBy END
    WHERE TenantId = @TenantId AND Id = @TimesheetId;

    EXEC crm.usp_Timesheet_SyncStatus @TenantId = @TenantId, @TimesheetId = @TimesheetId;

    IF (@Target = 'SUBMITTED' AND EXISTS (SELECT 1 FROM @Draft)) OR (@ExpTarget = 'SUBMITTED' AND @ReportId IS NOT NULL)
    BEGIN
        DECLARE @Title NVARCHAR(200);
        SELECT @Title = CONCAT(u.DisplayName, N'''s week of ', FORMAT(s.WeekStart, 'MMM d', 'en-US'), N' is ready for approval')
        FROM crm.Timesheet AS s JOIN sec.AppUser AS u ON u.TenantId = s.TenantId AND u.Id = s.AppUserId
        WHERE s.TenantId = @TenantId AND s.Id = @TimesheetId;
        EXEC sec.usp_Notification_Raise @NotificationType = 'TIMESHEET_SUBMITTED', @EntityType = 'TIMESHEET',
             @EntityId = @TimesheetId, @Title = @Title;
    END;

    COMMIT;
END;
