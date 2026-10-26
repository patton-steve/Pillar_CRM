-- Internal: recomputes a timesheet's status from its entries (see crm.Timesheet for the rules).
-- Called by every proc that changes an entry's status or week.
-- Handoff 23: the week's expense report (ap.Bill.TimesheetId, with lines) counts like one more entry: DRAFT is OPEN
-- (REJECTED when it was sent back), SUBMITTED is SUBMITTED, and OPEN, PARTIAL or PAID is approved.
CREATE PROCEDURE crm.usp_Timesheet_SyncStatus
    @TenantId       INT,
    @TimesheetId    INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Code VARCHAR(30);

    SELECT @Code = CASE
            WHEN SUM(CASE WHEN x.StatusCode = 'DRAFT' AND x.RejectedAt IS NOT NULL THEN 1 ELSE 0 END) > 0 THEN 'REJECTED'
            WHEN SUM(CASE WHEN x.StatusCode = 'DRAFT' THEN 1 ELSE 0 END) > 0 THEN 'OPEN'
            WHEN SUM(CASE WHEN x.StatusCode = 'SUBMITTED' THEN 1 ELSE 0 END) > 0 THEN 'SUBMITTED'
            WHEN COUNT(*) > 0 THEN 'APPROVED'
            ELSE 'OPEN' END
    FROM (
        SELECT s.SystemCode AS StatusCode, e.RejectedAt
        FROM crm.TimeEntry AS e
        JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
        WHERE e.TenantId = @TenantId AND e.TimesheetId = @TimesheetId AND e.DeletedAt IS NULL
        UNION ALL
        SELECT CASE WHEN s.SystemCode = 'DRAFT' OR s.SystemCode = 'SUBMITTED' THEN s.SystemCode ELSE 'APPROVED' END, b.RejectedAt
        FROM ap.Bill AS b
        JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
        WHERE b.TenantId = @TenantId AND b.TimesheetId = @TimesheetId AND b.VoidedAt IS NULL
          AND EXISTS (SELECT 1 FROM ap.BillLine AS l WHERE l.TenantId = b.TenantId AND l.BillId = b.Id)
    ) AS x;

    UPDATE t
    SET TimesheetStatusId = s.Id, ModifiedAt = SYSUTCDATETIME(), ModifiedBy = CONVERT(INT, SESSION_CONTEXT(N'UserId'))
    FROM crm.Timesheet AS t
    JOIN lkp.TimesheetStatus AS s ON s.TenantId = t.TenantId AND s.SystemCode = ISNULL(@Code, 'OPEN')
    WHERE t.TenantId = @TenantId AND t.Id = @TimesheetId AND t.TimesheetStatusId <> s.Id;
END;
