-- Pillar's audit trail is append-only.
CREATE TRIGGER admin.trg_PlatformAudit_AppendOnly
ON admin.PlatformAudit
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted) THROW 52299, N'The platform audit trail can''t be changed.', 1;
END;
