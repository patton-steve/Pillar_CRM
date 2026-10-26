-- Takes the sample company out (setup wizard, or Settings > Company): deletes every IsSample client and everything under it,
-- including anything people added to those clients since (projects, tasks, comments, time, notes, custom field values, recent
-- items and notifications). Refused while any invoice, credit memo, payment or bill touches the sample clients or their projects.
-- Needs client.edit and project.edit. Returns how many clients were removed.
CREATE PROCEDURE admin.usp_SampleData_Remove
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Count INT;

    IF @TenantId IS NULL OR @UserId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'client.edit'))
       OR NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'project.edit'))
        THROW 52283, N'You need to be able to edit clients and projects to remove the sample company.', 1;

    CREATE TABLE #c (Id INT PRIMARY KEY, PublicId UNIQUEIDENTIFIER);
    CREATE TABLE #p (Id INT PRIMARY KEY, PublicId UNIQUEIDENTIFIER);
    CREATE TABLE #t (Id INT PRIMARY KEY, PublicId UNIQUEIDENTIFIER);

    BEGIN TRAN;

    INSERT INTO #c SELECT Id, PublicId FROM crm.Client WITH (UPDLOCK) WHERE TenantId = @TenantId AND IsSample = 1;
    SET @Count = @@ROWCOUNT;
    IF @Count = 0 THROW 52282, N'There is no sample company to remove.', 1;
    INSERT INTO #p SELECT p.Id, p.PublicId FROM crm.ClientProject AS p JOIN #c ON #c.Id = p.ClientId WHERE p.TenantId = @TenantId;
    INSERT INTO #t SELECT t.Id, t.PublicId FROM crm.ClientTask AS t JOIN #p ON #p.Id = t.ProjectId WHERE t.TenantId = @TenantId;

    IF EXISTS (SELECT 1 FROM ar.Invoice AS i JOIN #c ON #c.Id = i.ClientId WHERE i.TenantId = @TenantId)
       OR EXISTS (SELECT 1 FROM ar.CreditMemo AS m JOIN #c ON #c.Id = m.ClientId WHERE m.TenantId = @TenantId)
       OR EXISTS (SELECT 1 FROM ar.InvoicePay AS y JOIN #c ON #c.Id = y.ClientId WHERE y.TenantId = @TenantId)
       OR EXISTS (SELECT 1 FROM ap.BillLine AS b JOIN #p ON #p.Id = b.ProjectId WHERE b.TenantId = @TenantId)
        THROW 52281, N'The sample company has invoices, payments or bills, so it can''t be removed automatically.', 1;

    DELETE x FROM crm.TimeEntryChange AS x
    JOIN crm.TimeEntry AS e ON e.TenantId = x.TenantId AND e.Id = x.TimeEntryId
    JOIN #p ON #p.Id = e.ProjectId
    WHERE x.TenantId = @TenantId;
    DELETE e FROM crm.TimeEntry AS e JOIN #p ON #p.Id = e.ProjectId WHERE e.TenantId = @TenantId;

    DELETE a FROM crm.TaskAttachment AS a JOIN #t ON #t.Id = a.TaskId WHERE a.TenantId = @TenantId;
    DELETE m FROM crm.TaskCommentMention AS m
    JOIN crm.TaskComment AS c ON c.TenantId = m.TenantId AND c.Id = m.CommentId
    JOIN #t ON #t.Id = c.TaskId
    WHERE m.TenantId = @TenantId;
    DELETE c FROM crm.TaskComment AS c JOIN #t ON #t.Id = c.TaskId WHERE c.TenantId = @TenantId;
    DELETE i FROM crm.TaskChecklistItem AS i JOIN #t ON #t.Id = i.TaskId WHERE i.TenantId = @TenantId;
    DELETE w FROM crm.TaskWatcher AS w JOIN #t ON #t.Id = w.TaskId WHERE w.TenantId = @TenantId;
    DELETE m FROM crm.ProjectBillingMilestone AS m JOIN #p ON #p.Id = m.ProjectId WHERE m.TenantId = @TenantId;
    DELETE t FROM crm.ClientTask AS t JOIN #t ON #t.Id = t.Id WHERE t.TenantId = @TenantId;

    DELETE a FROM crm.ProjectBudgetAlert AS a JOIN #p ON #p.Id = a.ProjectId WHERE a.TenantId = @TenantId;
    DELETE r FROM crm.ProjectRate AS r JOIN #p ON #p.Id = r.ProjectId WHERE r.TenantId = @TenantId;
    DELETE u FROM crm.ProjectUser AS u JOIN #p ON #p.Id = u.ProjectId WHERE u.TenantId = @TenantId;
    DELETE p FROM crm.ClientProject AS p JOIN #p ON #p.Id = p.Id WHERE p.TenantId = @TenantId;

    DELETE m FROM crm.ClientNoteMention AS m
    JOIN crm.ClientNote AS n ON n.TenantId = m.TenantId AND n.Id = m.NoteId
    JOIN #c ON #c.Id = n.ClientId
    WHERE m.TenantId = @TenantId;
    DELETE n FROM crm.ClientNote AS n JOIN #c ON #c.Id = n.ClientId WHERE n.TenantId = @TenantId;
    DELETE r FROM crm.ClientBillingProfileRecipient AS r JOIN #c ON #c.Id = r.ClientId WHERE r.TenantId = @TenantId;
    DELETE b FROM crm.ClientBillingProfile AS b JOIN #c ON #c.Id = b.ClientId WHERE b.TenantId = @TenantId;

    DELETE v FROM admin.CustomFieldValue AS v
    WHERE v.TenantId = @TenantId
      AND ((v.EntityType = 'CLIENT' AND v.RecordId IN (SELECT Id FROM #c))
        OR (v.EntityType = 'PROJECT' AND v.RecordId IN (SELECT Id FROM #p))
        OR (v.EntityType = 'TASK' AND v.RecordId IN (SELECT Id FROM #t))
        OR (v.EntityType = 'CONTACT' AND v.RecordId IN (SELECT k.Id FROM crm.Contact AS k JOIN #c ON #c.Id = k.ClientId WHERE k.TenantId = @TenantId)));
    DELETE k FROM crm.Contact AS k JOIN #c ON #c.Id = k.ClientId WHERE k.TenantId = @TenantId;
    DELETE a FROM crm.ClientAddress AS a JOIN #c ON #c.Id = a.ClientId WHERE a.TenantId = @TenantId;

    DELETE r FROM sec.UserRecentItem AS r
    WHERE r.TenantId = @TenantId
      AND r.EntityPublicId IN (SELECT PublicId FROM #c UNION ALL SELECT PublicId FROM #p UNION ALL SELECT PublicId FROM #t);
    DELETE n FROM sec.Notification AS n
    WHERE n.TenantId = @TenantId
      AND ((n.EntityType = 'PROJECT' AND n.EntityId IN (SELECT Id FROM #p)) OR (n.EntityType = 'TASK' AND n.EntityId IN (SELECT Id FROM #t)));

    DELETE c FROM crm.Client AS c JOIN #c ON #c.Id = c.Id WHERE c.TenantId = @TenantId;

    EXEC admin.usp_Audit_Write @Area = 'company', @EntityType = 'SAMPLE_DATA', @Action = 'DELETE', @Summary = N'Removed the sample company';
    COMMIT;

    SELECT @Count AS SampleClientsRemoved;
END;
