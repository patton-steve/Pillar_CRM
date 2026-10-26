-- Saves the task page's details box (and board drags): status, assignee, due date and estimate, in one step with a
-- comment from the editor (Steve 2026-10-21). Pass only what changed; @Clear* empties a field. The comment's ChangeJson
-- holds one chip per field that really changed, with display values:
--   [{"field":"Status","from":"To do","to":"In progress"}, {"field":"Estimate","from":"6 h","to":"8 h"}]
-- @Comment is the editor's note (sanitized HTML, optional at this level; the UI asks for it). The editor becomes a watcher.
-- Notifications: crm.trg_ClientTask_Notify sends TASK_ASSIGNED_TO_ME and, for a status change, WATCHED_TASK_CHANGED;
-- other detail changes notify the watchers here. Needs task.edit. Errors 51341-51345.
CREATE PROCEDURE crm.usp_ClientTask_UpdateDetails
    @TaskId             INT,
    @TaskStatusId       INT = NULL,
    @AssignedUserId     INT = NULL,
    @ClearAssignee      BIT = 0,
    @DueDate            DATE = NULL,
    @ClearDueDate       BIT = 0,
    @EstimatedHours     DECIMAL(9,2) = NULL,
    @ClearEstimate      BIT = 0,
    @Comment            NVARCHAR(MAX) = NULL,
    @CommentId          INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @OldStatus INT, @OldAssignee INT, @OldDue DATE, @OldEstimate DECIMAL(9,2),
            @NewStatus INT, @NewAssignee INT, @NewDue DATE, @NewEstimate DECIMAL(9,2),
            @TaskKey VARCHAR(20), @TaskTitle NVARCHAR(200), @Changes NVARCHAR(MAX), @Title NVARCHAR(200), @Watchers NVARCHAR(MAX);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51341, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'task.edit'))
        THROW 51342, N'You don''t have permission to edit tasks.', 1;

    SELECT @OldStatus = TaskStatusId, @OldAssignee = AssignedUserId, @OldDue = DueDate, @OldEstimate = EstimatedHours,
           @TaskKey = TaskKey, @TaskTitle = Title
    FROM crm.ClientTask WITH (UPDLOCK)
    WHERE TenantId = @TenantId AND Id = @TaskId AND DeletedAt IS NULL;
    IF @TaskKey IS NULL THROW 51343, N'Task not found.', 1;

    SELECT @NewStatus   = COALESCE(@TaskStatusId, @OldStatus),
           @NewAssignee = CASE WHEN @ClearAssignee = 1 THEN NULL ELSE COALESCE(@AssignedUserId, @OldAssignee) END,
           @NewDue      = CASE WHEN @ClearDueDate = 1 THEN NULL ELSE COALESCE(@DueDate, @OldDue) END,
           @NewEstimate = CASE WHEN @ClearEstimate = 1 THEN NULL ELSE COALESCE(@EstimatedHours, @OldEstimate) END;

    IF @NewStatus <> @OldStatus AND NOT EXISTS (SELECT 1 FROM lkp.TaskStatus WHERE TenantId = @TenantId AND Id = @NewStatus AND IsActive = 1)
        THROW 51344, N'Choose an active status.', 1;
    IF @NewAssignee IS NOT NULL AND ISNULL(@OldAssignee, 0) <> @NewAssignee
       AND NOT EXISTS (SELECT 1 FROM sec.AppUser WHERE TenantId = @TenantId AND Id = @NewAssignee AND Status <> 'DISABLED')
        THROW 51344, N'Choose someone who can be assigned.', 1;

    -- one chip per real change, with the values people see
    SELECT @Changes = (
        SELECT c.field, c.[from], c.[to]
        FROM (VALUES
            (1, N'Status',
                (SELECT Name FROM lkp.TaskStatus WHERE TenantId = @TenantId AND Id = @OldStatus),
                (SELECT Name FROM lkp.TaskStatus WHERE TenantId = @TenantId AND Id = @NewStatus),
                IIF(@NewStatus <> @OldStatus, 1, 0)),
            (2, N'Assignee',
                (SELECT DisplayName FROM sec.AppUser WHERE TenantId = @TenantId AND Id = @OldAssignee),
                (SELECT DisplayName FROM sec.AppUser WHERE TenantId = @TenantId AND Id = @NewAssignee),
                IIF(ISNULL(@NewAssignee, 0) <> ISNULL(@OldAssignee, 0), 1, 0)),
            (3, N'Due date', CONVERT(NVARCHAR(10), @OldDue, 23), CONVERT(NVARCHAR(10), @NewDue, 23),
                IIF(ISNULL(@NewDue, '19000101') <> ISNULL(@OldDue, '19000101'), 1, 0)),
            (4, N'Estimate',
                CASE WHEN @OldEstimate IS NOT NULL THEN CONCAT(FORMAT(@OldEstimate, '0.##'), N' h') END,
                CASE WHEN @NewEstimate IS NOT NULL THEN CONCAT(FORMAT(@NewEstimate, '0.##'), N' h') END,
                IIF(ISNULL(@NewEstimate, -1) <> ISNULL(@OldEstimate, -1), 1, 0))
        ) AS c (Seq, field, [from], [to], Changed)
        WHERE c.Changed = 1
        ORDER BY c.Seq
        FOR JSON PATH, INCLUDE_NULL_VALUES);

    IF @Changes IS NULL THROW 51345, N'Nothing changed. To add a note without changing details, post a comment.', 1;

    BEGIN TRAN;

    UPDATE crm.ClientTask
    SET TaskStatusId = @NewStatus, AssignedUserId = @NewAssignee, DueDate = @NewDue, EstimatedHours = @NewEstimate,
        ModifiedAt = @Now, ModifiedBy = @UserId
    WHERE TenantId = @TenantId AND Id = @TaskId;

    INSERT INTO crm.TaskComment (TenantId, TaskId, AuthorUserId, Body, ChangeJson)
    VALUES (@TenantId, @TaskId, @UserId, ISNULL(LTRIM(RTRIM(@Comment)), N''), @Changes);
    SET @CommentId = SCOPE_IDENTITY();

    INSERT INTO crm.TaskWatcher (TenantId, TaskId, AppUserId)
    SELECT @TenantId, @TaskId, @UserId
    WHERE NOT EXISTS (SELECT 1 FROM crm.TaskWatcher WHERE TenantId = @TenantId AND TaskId = @TaskId AND AppUserId = @UserId);

    -- status changes already notified watchers through the trigger; other detail changes do it here
    IF @NewStatus = @OldStatus
    BEGIN
        SELECT @Title = LEFT(CONCAT(DisplayName, N' updated ', @TaskKey, N': ', @TaskTitle), 200)
        FROM sec.AppUser WHERE TenantId = @TenantId AND Id = @UserId;
        EXEC sec.usp_Notification_Raise @NotificationType = 'WATCHED_TASK_CHANGED', @EntityType = 'TASK', @EntityId = @TaskId,
             @Title = @Title, @Body = @Comment;
    END;

    COMMIT;
END;
