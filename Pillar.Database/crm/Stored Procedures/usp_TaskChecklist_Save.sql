-- Replaces a task's checklist in one step. @Items is a JSON array in display order:
--   [{"id": 31, "text": "Back up the database", "isDone": true}, {"text": "Run the migration"}]
-- Items with an id are updated, items left out are deleted, items without an id are added. Checking an item stamps
-- DoneAt/DoneBy; unchecking clears them. An empty array removes the checklist. Needs task.edit.
CREATE PROCEDURE crm.usp_TaskChecklist_Save
    @TaskId     INT,
    @Items      NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME();

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51311, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'task.edit'))
        THROW 51318, N'You don''t have permission to edit tasks.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.ClientTask WHERE TenantId = @TenantId AND Id = @TaskId AND DeletedAt IS NULL)
        THROW 51315, N'Task not found.', 1;
    IF ISJSON(@Items) = 0 OR LEFT(LTRIM(@Items), 1) <> N'[' THROW 51319, N'Checklist items must be a JSON array.', 1;

    CREATE TABLE #c (Seq INT NOT NULL, Id INT NULL, ItemText NVARCHAR(500) NULL, IsDone BIT NOT NULL);
    INSERT INTO #c (Seq, Id, ItemText, IsDone)
    SELECT CONVERT(INT, j.[key]) + 1, x.id, LTRIM(RTRIM(x.[text])), ISNULL(x.isDone, 0)
    FROM OPENJSON(@Items) AS j
    CROSS APPLY OPENJSON(j.value) WITH (id INT, [text] NVARCHAR(500), isDone BIT) AS x;

    IF EXISTS (SELECT 1 FROM #c WHERE NULLIF(ItemText, N'') IS NULL) THROW 51320, N'Checklist items need text.', 1;
    IF EXISTS (SELECT 1 FROM #c AS c WHERE c.Id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM crm.TaskChecklistItem AS t WHERE t.TenantId = @TenantId AND t.TaskId = @TaskId AND t.Id = c.Id))
        THROW 51319, N'A checklist item doesn''t belong to this task.', 1;

    BEGIN TRAN;

    DELETE t FROM crm.TaskChecklistItem AS t
    WHERE t.TenantId = @TenantId AND t.TaskId = @TaskId AND NOT EXISTS (SELECT 1 FROM #c AS c WHERE c.Id = t.Id);

    UPDATE t
    SET ItemText = c.ItemText, SortOrder = c.Seq * 10, IsDone = c.IsDone,
        DoneAt = CASE WHEN c.IsDone = 0 THEN NULL WHEN t.IsDone = 1 THEN t.DoneAt ELSE @Now END,
        DoneBy = CASE WHEN c.IsDone = 0 THEN NULL WHEN t.IsDone = 1 THEN t.DoneBy ELSE @UserId END
    FROM crm.TaskChecklistItem AS t
    JOIN #c AS c ON c.Id = t.Id
    WHERE t.TenantId = @TenantId AND t.TaskId = @TaskId;

    INSERT INTO crm.TaskChecklistItem (TenantId, TaskId, ItemText, IsDone, SortOrder, DoneAt, DoneBy)
    SELECT @TenantId, @TaskId, c.ItemText, c.IsDone, c.Seq * 10, IIF(c.IsDone = 1, @Now, NULL), IIF(c.IsDone = 1, @UserId, NULL)
    FROM #c AS c WHERE c.Id IS NULL;

    COMMIT;
END;
