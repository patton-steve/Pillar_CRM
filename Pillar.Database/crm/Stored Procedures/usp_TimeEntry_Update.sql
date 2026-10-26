-- An approver fixes approved time in place instead of sending the week back (Steve 2026-10-21). Needs time.approve.
-- Only APPROVED entries not yet on an invoice (draft or issued). Pass only what changed; @Clear* empties a field.
--   @BilledMinutes  the billed duration (EnteredMinutes keeps what the person logged)
--   @WorkDate       must stay inside the entry's timesheet week
--   @TaskId         must be on the same project
-- The rate frozen at approval is kept. @Reason is required and is logged with the changes in crm.TimeEntryChange.
-- @ChangeId is NULL when nothing actually changed. Errors 51606-51612.
CREATE PROCEDURE crm.usp_TimeEntry_Update
    @TimeEntryId        INT,
    @Reason             NVARCHAR(500),
    @BilledMinutes      INT = NULL,
    @WorkDate           DATE = NULL,
    @TaskId             INT = NULL,
    @Description        NVARCHAR(2000) = NULL,
    @ClearDescription   BIT = 0,
    @InternalNote       NVARCHAR(2000) = NULL,
    @ClearInternalNote  BIT = 0,
    @IsBillable         BIT = NULL,
    @ChangeId           INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @Status VARCHAR(30), @InvoiceEntryId INT, @ProjectId INT, @WeekStart DATE, @WeekEnd DATE, @Owner INT,
            @OldMinutes INT, @OldDate DATE, @OldTask INT, @OldDesc NVARCHAR(2000), @OldNote NVARCHAR(2000), @OldBillable BIT,
            @NewMinutes INT, @NewDate DATE, @NewTask INT, @NewDesc NVARCHAR(2000), @NewNote NVARCHAR(2000), @NewBillable BIT,
            @NoteRequired BIT, @Changes NVARCHAR(MAX);
    SET @ChangeId = NULL;

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51606, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'time.approve'))
        THROW 51607, N'You need permission to approve time to edit approved time.', 1;
    IF NULLIF(LTRIM(@Reason), N'') IS NULL THROW 51608, N'Say why the approved time is being changed.', 1;

    BEGIN TRAN;

    SELECT @Status = s.SystemCode, @InvoiceEntryId = e.InvoiceEntryId, @ProjectId = e.ProjectId, @Owner = e.AppUserId,
           @WeekStart = t.WeekStart, @WeekEnd = t.WeekEnd,
           @OldMinutes = e.BilledMinutes, @OldDate = e.WorkDate, @OldTask = e.TaskId,
           @OldDesc = e.Description, @OldNote = e.InternalNote, @OldBillable = e.IsBillable
    FROM crm.TimeEntry AS e WITH (UPDLOCK)
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
    JOIN crm.Timesheet AS t ON t.TenantId = e.TenantId AND t.Id = e.TimesheetId
    WHERE e.TenantId = @TenantId AND e.Id = @TimeEntryId AND e.DeletedAt IS NULL;
    IF @Status IS NULL THROW 51609, N'Time entry not found.', 1;
    IF @Status <> 'APPROVED' OR @InvoiceEntryId IS NOT NULL
        THROW 51610, N'Only approved time that is not on an invoice can be edited here.', 1;

    SELECT @NewMinutes  = COALESCE(@BilledMinutes, @OldMinutes),
           @NewDate     = COALESCE(@WorkDate, @OldDate),
           @NewTask     = COALESCE(@TaskId, @OldTask),
           @NewDesc     = CASE WHEN @ClearDescription = 1 THEN NULL ELSE COALESCE(@Description, @OldDesc) END,
           @NewNote     = CASE WHEN @ClearInternalNote = 1 THEN NULL ELSE COALESCE(@InternalNote, @OldNote) END,
           @NewBillable = COALESCE(@IsBillable, @OldBillable);

    IF @NewMinutes < 1 OR @NewMinutes > 1440 THROW 51611, N'Time must be between 1 minute and 24 hours.', 1;
    IF @NewDate < @WeekStart OR @NewDate > @WeekEnd
        THROW 51611, N'The date must stay inside the same timesheet week. Send the week back to move time to another week.', 1;
    IF @NewTask <> @OldTask AND NOT EXISTS (SELECT 1 FROM crm.ClientTask
                                            WHERE TenantId = @TenantId AND ProjectId = @ProjectId AND Id = @NewTask AND DeletedAt IS NULL)
        THROW 51611, N'Choose a task on the same project.', 1;
    SELECT @NoteRequired = ISNULL(TRY_CONVERT(BIT, Value), 0) FROM admin.fn_Setting(@TenantId, @Owner, 'TimeEntry.NoteRequired');
    IF @NoteRequired = 1 AND NULLIF(LTRIM(RTRIM(@NewDesc)), N'') IS NULL
        THROW 51612, N'A description is required for every time entry.', 1;

    -- one chip per real change, with the values people see
    SELECT @Changes = (
        SELECT c.field, c.[from], c.[to]
        FROM (VALUES
            (1, N'Hours', CONCAT(FORMAT(@OldMinutes / 60.0, '0.##'), N' h'), CONCAT(FORMAT(@NewMinutes / 60.0, '0.##'), N' h'),
                IIF(@NewMinutes <> @OldMinutes, 1, 0)),
            (2, N'Date', FORMAT(@OldDate, 'MMM d, yyyy', 'en-US'), FORMAT(@NewDate, 'MMM d, yyyy', 'en-US'),
                IIF(@NewDate <> @OldDate, 1, 0)),
            (3, N'Task',
                (SELECT CONCAT(TaskKey, N' ', Title) FROM crm.ClientTask WHERE TenantId = @TenantId AND Id = @OldTask),
                (SELECT CONCAT(TaskKey, N' ', Title) FROM crm.ClientTask WHERE TenantId = @TenantId AND Id = @NewTask),
                IIF(@NewTask <> @OldTask, 1, 0)),
            (4, N'Description', @OldDesc, @NewDesc,
                IIF(EXISTS (SELECT @OldDesc COLLATE DATABASE_DEFAULT EXCEPT SELECT @NewDesc COLLATE DATABASE_DEFAULT), 1, 0)),
            (5, N'Internal note', @OldNote, @NewNote,
                IIF(EXISTS (SELECT @OldNote COLLATE DATABASE_DEFAULT EXCEPT SELECT @NewNote COLLATE DATABASE_DEFAULT), 1, 0)),
            (6, N'Billable', IIF(@OldBillable = 1, N'Yes', N'No'), IIF(@NewBillable = 1, N'Yes', N'No'),
                IIF(@NewBillable <> @OldBillable, 1, 0))
        ) AS c (SortOrder, field, [from], [to], Changed)
        WHERE c.Changed = 1
        ORDER BY c.SortOrder
        FOR JSON PATH, INCLUDE_NULL_VALUES);

    IF @Changes IS NULL
    BEGIN
        COMMIT;
        RETURN;
    END;

    UPDATE crm.TimeEntry
    SET BilledMinutes = @NewMinutes, WorkDate = @NewDate, TaskId = @NewTask, Description = @NewDesc,
        InternalNote = @NewNote, IsBillable = @NewBillable, ModifiedAt = @Now, ModifiedBy = @UserId
    WHERE TenantId = @TenantId AND Id = @TimeEntryId;

    INSERT INTO crm.TimeEntryChange (TenantId, TimeEntryId, ChangedBy, ChangedAt, Reason, ChangeJson)
    VALUES (@TenantId, @TimeEntryId, @UserId, @Now, @Reason, @Changes);
    SET @ChangeId = SCOPE_IDENTITY();

    COMMIT;
END;
