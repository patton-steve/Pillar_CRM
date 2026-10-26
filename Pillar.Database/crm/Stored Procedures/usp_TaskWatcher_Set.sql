-- Follow or unfollow a task. @AppUserId NULL = the signed-in user; adding or removing someone else needs task.edit.
CREATE PROCEDURE crm.usp_TaskWatcher_Set
    @TaskId         INT,
    @Watch          BIT = 1,
    @AppUserId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51311, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    SET @AppUserId = COALESCE(@AppUserId, @UserId);
    IF @AppUserId <> @UserId AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'task.edit'))
        THROW 51317, N'You can only follow or unfollow tasks for yourself.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.ClientTask WHERE TenantId = @TenantId AND Id = @TaskId AND DeletedAt IS NULL)
        THROW 51315, N'Task not found.', 1;

    IF @Watch = 1
        INSERT INTO crm.TaskWatcher (TenantId, TaskId, AppUserId)
        SELECT @TenantId, @TaskId, @AppUserId
        WHERE NOT EXISTS (SELECT 1 FROM crm.TaskWatcher WHERE TenantId = @TenantId AND TaskId = @TaskId AND AppUserId = @AppUserId);
    ELSE
        DELETE FROM crm.TaskWatcher WHERE TenantId = @TenantId AND TaskId = @TaskId AND AppUserId = @AppUserId;
END;
