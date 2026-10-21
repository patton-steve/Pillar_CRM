-- Deletes one draft invoice (@InvoiceId) or every remaining draft in a run (@InvoiceRunId),
-- unlinking their time, rebilled expenses and milestones so they are picked up again. Issued invoices are never deleted; void them.
CREATE PROCEDURE ar.usp_Invoice_DeleteDraft
    @InvoiceId      INT = NULL,
    @InvoiceRunId   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT);
    DECLARE @ids TABLE (InvoiceId INT PRIMARY KEY);

    IF (@InvoiceId IS NULL AND @InvoiceRunId IS NULL) OR (@InvoiceId IS NOT NULL AND @InvoiceRunId IS NOT NULL)
        THROW 50631, N'Pass either @InvoiceId or @InvoiceRunId.', 1;

    BEGIN TRAN;

    INSERT INTO @ids
    SELECT i.Id
    FROM ar.Invoice AS i WITH (UPDLOCK)
    JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId AND s.SystemCode = 'DRAFT'
    WHERE i.TenantId = @TenantId
      AND (i.Id = @InvoiceId OR i.InvoiceRunId = @InvoiceRunId);

    IF @InvoiceId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @ids)
        THROW 50632, N'Only draft invoices can be deleted.', 1;

    UPDATE e SET InvoiceEntryId = NULL
    FROM crm.TimeEntry AS e
    JOIN ar.InvoiceEntry AS l ON l.TenantId = e.TenantId AND l.Id = e.InvoiceEntryId
    WHERE e.TenantId = @TenantId AND l.InvoiceId IN (SELECT InvoiceId FROM @ids);

    UPDATE bl SET InvoiceEntryId = NULL
    FROM ap.BillLine AS bl
    JOIN ar.InvoiceEntry AS l ON l.TenantId = bl.TenantId AND l.Id = bl.InvoiceEntryId
    WHERE bl.TenantId = @TenantId AND l.InvoiceId IN (SELECT InvoiceId FROM @ids);

    -- fixed-fee milestones become billable again
    UPDATE m SET InvoiceEntryId = NULL
    FROM crm.ProjectBillingMilestone AS m
    JOIN ar.InvoiceEntry AS l ON l.TenantId = m.TenantId AND l.Id = m.InvoiceEntryId
    WHERE m.TenantId = @TenantId AND l.InvoiceId IN (SELECT InvoiceId FROM @ids);

    DELETE FROM ar.InvoiceEntry WHERE TenantId = @TenantId AND InvoiceId IN (SELECT InvoiceId FROM @ids);
    DELETE FROM ar.Invoice WHERE TenantId = @TenantId AND Id IN (SELECT InvoiceId FROM @ids);

    COMMIT;
END;
