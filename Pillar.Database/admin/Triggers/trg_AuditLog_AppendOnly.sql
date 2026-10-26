-- The audit log is append-only.
CREATE TRIGGER admin.trg_AuditLog_AppendOnly
ON admin.AuditLog
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted) THROW 51701, N'The audit log can''t be changed.', 1;
END;
