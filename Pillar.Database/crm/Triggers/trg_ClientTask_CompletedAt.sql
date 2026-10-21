-- Stamps CompletedAt when a task moves to a DONE status and clears it if the task is reopened.
CREATE TRIGGER crm.trg_ClientTask_CompletedAt
ON crm.ClientTask
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(TaskStatusId) RETURN;

    UPDATE t
    SET CompletedAt = CASE WHEN s.SystemCode = 'DONE' THEN COALESCE(t.CompletedAt, SYSUTCDATETIME()) END
    FROM crm.ClientTask AS t
    JOIN inserted AS i ON i.Id = t.Id
    JOIN lkp.TaskStatus AS s ON s.TenantId = t.TenantId AND s.Id = t.TaskStatusId
    WHERE (s.SystemCode = 'DONE' AND t.CompletedAt IS NULL)
       OR (s.SystemCode <> 'DONE' AND t.CompletedAt IS NOT NULL);
END;
