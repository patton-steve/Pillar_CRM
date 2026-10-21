-- Time on an issued invoice is locked: no edits to what was billed and no deletes.
-- Status and the invoice link may change (void returns entries to APPROVED and unlinks them).
CREATE TRIGGER crm.trg_TimeEntry_LockInvoiced
ON crm.TimeEntry
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM deleted AS d
        JOIN lkp.TimeEntryStatus AS s ON s.TenantId = d.TenantId AND s.Id = d.TimeEntryStatusId AND s.SystemCode = 'INVOICED'
        LEFT JOIN inserted AS i ON i.Id = d.Id
        WHERE i.Id IS NULL
           OR EXISTS (SELECT d.ProjectId, d.TaskId, d.AppUserId, d.WorkDate, d.EnteredMinutes, d.BilledMinutes,
                             d.Description, d.IsBillable, d.RateApplied, d.DeletedAt
                      EXCEPT
                      SELECT i.ProjectId, i.TaskId, i.AppUserId, i.WorkDate, i.EnteredMinutes, i.BilledMinutes,
                             i.Description, i.IsBillable, i.RateApplied, i.DeletedAt)
    )
        THROW 50651, N'Invoiced time cannot be changed. Void the invoice first.', 1;
END;
