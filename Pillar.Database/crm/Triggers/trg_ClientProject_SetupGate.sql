-- A project can't move out of PLANNED while any BLOCK setup check fails (crm.fn_ProjectSetupIssues; Steve 2026-10-21).
-- Projects created in another status aren't gated here, but still can't get tasks until they are ready.
CREATE TRIGGER crm.trg_ClientProject_SetupGate
ON crm.ClientProject
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(ProjectStatusId) RETURN;

    DECLARE @Msg NVARCHAR(2048);
    SELECT TOP (1) @Msg = CONCAT(N'Finish setting up ', i.ProjectCode, N' before moving it out of Planned: ',
                                 (SELECT STRING_AGG(x.Message, N' ') WITHIN GROUP (ORDER BY x.SortOrder)
                                  FROM crm.fn_ProjectSetupIssues(i.TenantId, i.Id) AS x WHERE x.Severity = 'BLOCK'))
    FROM inserted AS i
    JOIN deleted AS d ON d.Id = i.Id
    JOIN lkp.ProjectStatus AS was ON was.TenantId = d.TenantId AND was.Id = d.ProjectStatusId AND was.SystemCode = 'PLANNED'
    JOIN lkp.ProjectStatus AS now ON now.TenantId = i.TenantId AND now.Id = i.ProjectStatusId AND now.SystemCode <> 'PLANNED'
    WHERE EXISTS (SELECT 1 FROM crm.fn_ProjectSetupIssues(i.TenantId, i.Id) AS x WHERE x.Severity = 'BLOCK');

    IF @Msg IS NOT NULL THROW 51401, @Msg, 1;
END;
