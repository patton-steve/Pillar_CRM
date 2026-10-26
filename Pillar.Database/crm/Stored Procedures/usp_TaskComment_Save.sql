-- Adds a comment to a task (@CommentId NULL) or edits one (author only; change comments from details edits can't be edited). @Body is sanitized HTML from the API; inline
-- images are crm.TaskAttachment rows it references. @MentionUserIds is a JSON array of the user ids @mentioned in the body.
-- The author and everyone mentioned become watchers. Newly mentioned people get MENTIONED; a new comment also tells
-- the other watchers (WATCHED_TASK_CHANGED). Needs task.edit.
CREATE PROCEDURE crm.usp_TaskComment_Save
    @CommentId          INT = NULL OUTPUT,
    @TaskId             INT,
    @Body               NVARCHAR(MAX),
    @MentionUserIds     NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @IsNew BIT = IIF(@CommentId IS NULL, 1, 0),
            @TaskKey VARCHAR(20), @TaskTitle NVARCHAR(200), @Title NVARCHAR(200), @Others NVARCHAR(MAX), @AuthorName NVARCHAR(201);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51311, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'task.edit'))
        THROW 51312, N'You don''t have permission to comment on tasks.', 1;
    IF NULLIF(LTRIM(RTRIM(@Body)), N'') IS NULL THROW 51313, N'A comment can''t be empty.', 1;
    IF @MentionUserIds IS NOT NULL AND ISJSON(@MentionUserIds) = 0 THROW 51314, N'Mentions must be a JSON array of user ids.', 1;

    SELECT @TaskKey = TaskKey, @TaskTitle = Title FROM crm.ClientTask
    WHERE TenantId = @TenantId AND Id = @TaskId AND DeletedAt IS NULL;
    IF @TaskKey IS NULL THROW 51315, N'Task not found.', 1;
    IF @IsNew = 0 AND NOT EXISTS (SELECT 1 FROM crm.TaskComment WHERE TenantId = @TenantId AND Id = @CommentId
                                  AND TaskId = @TaskId AND AuthorUserId = @UserId AND DeletedAt IS NULL AND ChangeJson IS NULL)
        THROW 51316, N'You can only edit your own comments.', 1;

    CREATE TABLE #m (AppUserId INT PRIMARY KEY, IsNew BIT NOT NULL DEFAULT (1));
    INSERT INTO #m (AppUserId)
    SELECT DISTINCT u.Id
    FROM OPENJSON(ISNULL(@MentionUserIds, N'[]')) AS j
    JOIN sec.AppUser AS u ON u.TenantId = @TenantId AND u.Id = TRY_CONVERT(INT, j.value);

    BEGIN TRAN;

    IF @IsNew = 1
    BEGIN
        INSERT INTO crm.TaskComment (TenantId, TaskId, AuthorUserId, Body) VALUES (@TenantId, @TaskId, @UserId, @Body);
        SET @CommentId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE crm.TaskComment SET Body = @Body, EditedAt = @Now WHERE TenantId = @TenantId AND Id = @CommentId;
        UPDATE m SET IsNew = 0 FROM #m AS m
        WHERE EXISTS (SELECT 1 FROM crm.TaskCommentMention AS x WHERE x.TenantId = @TenantId AND x.CommentId = @CommentId AND x.AppUserId = m.AppUserId);
        DELETE x FROM crm.TaskCommentMention AS x
        WHERE x.TenantId = @TenantId AND x.CommentId = @CommentId AND NOT EXISTS (SELECT 1 FROM #m AS m WHERE m.AppUserId = x.AppUserId);
    END;

    INSERT INTO crm.TaskCommentMention (TenantId, CommentId, AppUserId)
    SELECT @TenantId, @CommentId, AppUserId FROM #m WHERE IsNew = 1;

    INSERT INTO crm.TaskWatcher (TenantId, TaskId, AppUserId)
    SELECT @TenantId, @TaskId, w.AppUserId
    FROM (SELECT @UserId AS AppUserId UNION SELECT AppUserId FROM #m) AS w
    WHERE NOT EXISTS (SELECT 1 FROM crm.TaskWatcher AS x WHERE x.TenantId = @TenantId AND x.TaskId = @TaskId AND x.AppUserId = w.AppUserId);

    SELECT @AuthorName = DisplayName FROM sec.AppUser WHERE TenantId = @TenantId AND Id = @UserId;

    IF EXISTS (SELECT 1 FROM #m WHERE IsNew = 1)
    BEGIN
        SET @Title = LEFT(CONCAT(@AuthorName, N' mentioned you on ', @TaskKey, N': ', @TaskTitle), 200);
        SELECT @Others = CONCAT(N'[', STRING_AGG(CONVERT(VARCHAR(12), AppUserId), ','), N']') FROM #m WHERE IsNew = 1;
        EXEC sec.usp_Notification_Raise @NotificationType = 'MENTIONED', @EntityType = 'COMMENT', @EntityId = @CommentId,
             @Title = @Title, @RecipientUserIds = @Others;
    END;

    IF @IsNew = 1
    BEGIN
        -- watchers who weren't just mentioned (they already heard about it)
        SET @Others = NULL;
        SELECT @Others = CONCAT(N'[', STRING_AGG(CONVERT(VARCHAR(12), w.AppUserId), ','), N']')
        FROM crm.TaskWatcher AS w
        WHERE w.TenantId = @TenantId AND w.TaskId = @TaskId AND NOT EXISTS (SELECT 1 FROM #m AS m WHERE m.AppUserId = w.AppUserId);
        SET @Title = LEFT(CONCAT(@AuthorName, N' commented on ', @TaskKey, N': ', @TaskTitle), 200);
        IF @Others IS NOT NULL
            EXEC sec.usp_Notification_Raise @NotificationType = 'WATCHED_TASK_CHANGED', @EntityType = 'TASK', @EntityId = @TaskId,
                 @Title = @Title, @RecipientUserIds = @Others;
    END;

    COMMIT;
END;
