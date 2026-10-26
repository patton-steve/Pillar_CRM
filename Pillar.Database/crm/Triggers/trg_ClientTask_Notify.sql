-- Keeps the assignee and reporter on a task's watcher list, and raises the task notifications:
--   new task                -> TASK_CREATED_ON_MY_PROJECT (project manager) and TASK_ASSIGNED_TO_ME (assignee)
--   assignee changed        -> TASK_ASSIGNED_TO_ME (new assignee)
--   status changed          -> WATCHED_TASK_CHANGED (watchers)
-- The person making the change is never notified (sec.usp_Notification_Raise skips SESSION_CONTEXT UserId).
CREATE TRIGGER crm.trg_ClientTask_Notify
ON crm.ClientTask
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    INSERT INTO crm.TaskWatcher (TenantId, TaskId, AppUserId)
    SELECT DISTINCT i.TenantId, i.Id, w.AppUserId
    FROM inserted AS i
    CROSS APPLY (VALUES (i.AssignedUserId), (i.ReporterUserId)) AS w (AppUserId)
    WHERE w.AppUserId IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM crm.TaskWatcher AS x WHERE x.TenantId = i.TenantId AND x.TaskId = i.Id AND x.AppUserId = w.AppUserId);

    IF SESSION_CONTEXT(N'TenantId') IS NULL RETURN;   -- platform-admin maintenance: no notifications

    DECLARE @ev TABLE (Seq INT IDENTITY(1,1) PRIMARY KEY, TaskId INT, NotificationType VARCHAR(40), Title NVARCHAR(200));

    INSERT INTO @ev (TaskId, NotificationType, Title)
    SELECT i.Id, e.NotificationType, LEFT(e.Title, 200)
    FROM inserted AS i
    LEFT JOIN deleted AS d ON d.Id = i.Id
    JOIN crm.ClientProject AS p ON p.TenantId = i.TenantId AND p.Id = i.ProjectId
    JOIN lkp.TaskStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.TaskStatusId
    CROSS APPLY (VALUES
        ('TASK_CREATED_ON_MY_PROJECT', CONCAT(N'New task on ', p.Name, N': ', i.TaskKey, N' ', i.Title),
         IIF(d.Id IS NULL, 1, 0)),
        ('TASK_ASSIGNED_TO_ME', CONCAT(i.TaskKey, N' was assigned to you: ', i.Title),
         IIF(i.AssignedUserId IS NOT NULL AND (d.Id IS NULL OR d.AssignedUserId IS NULL OR d.AssignedUserId <> i.AssignedUserId), 1, 0)),
        ('WATCHED_TASK_CHANGED', CONCAT(i.TaskKey, N' moved to ', s.Name, N': ', i.Title),
         IIF(d.Id IS NOT NULL AND d.TaskStatusId <> i.TaskStatusId, 1, 0))
    ) AS e (NotificationType, Title, Fire)
    WHERE e.Fire = 1 AND i.DeletedAt IS NULL;

    DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @ev), @TaskId INT, @Type VARCHAR(40), @Title NVARCHAR(200);
    WHILE @i <= @n
    BEGIN
        SELECT @TaskId = TaskId, @Type = NotificationType, @Title = Title FROM @ev WHERE Seq = @i;
        EXEC sec.usp_Notification_Raise @NotificationType = @Type, @EntityType = 'TASK', @EntityId = @TaskId, @Title = @Title;
        SET @i += 1;
    END;
END;
