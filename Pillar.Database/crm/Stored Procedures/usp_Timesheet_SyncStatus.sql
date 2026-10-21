-- Internal: recomputes a timesheet's status from its entries (see crm.Timesheet for the rules).
-- Called by every proc that changes an entry's status or week.
CREATE PROCEDURE crm.usp_Timesheet_SyncStatus
    @TenantId       INT,
    @TimesheetId    INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Code VARCHAR(30);

    SELECT @Code = CASE
            WHEN SUM(CASE WHEN s.SystemCode = 'DRAFT' AND e.RejectedAt IS NOT NULL THEN 1 ELSE 0 END) > 0 THEN 'REJECTED'
            WHEN SUM(CASE WHEN s.SystemCode = 'DRAFT' THEN 1 ELSE 0 END) > 0 THEN 'OPEN'
            WHEN SUM(CASE WHEN s.SystemCode = 'SUBMITTED' THEN 1 ELSE 0 END) > 0 THEN 'SUBMITTED'
            WHEN COUNT(*) > 0 THEN 'APPROVED'
            ELSE 'OPEN' END
    FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
    WHERE e.TenantId = @TenantId AND e.TimesheetId = @TimesheetId AND e.DeletedAt IS NULL;

    UPDATE t
    SET TimesheetStatusId = s.Id, ModifiedAt = SYSUTCDATETIME(), ModifiedBy = CONVERT(INT, SESSION_CONTEXT(N'UserId'))
    FROM crm.Timesheet AS t
    JOIN lkp.TimesheetStatus AS s ON s.TenantId = t.TenantId AND s.SystemCode = ISNULL(@Code, 'OPEN')
    WHERE t.TenantId = @TenantId AND t.Id = @TimesheetId AND t.TimesheetStatusId <> s.Id;
END;
