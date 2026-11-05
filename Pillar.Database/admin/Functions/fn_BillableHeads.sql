-- Billable heads for the per-head fee cap (handoff 26, Steve 2026-11-04): distinct people (with or without a login) whose billable
-- time is on an invoice issued in the month starting @PeriodStart (UTC) that hasn't been voided.
CREATE FUNCTION admin.fn_BillableHeads (@TenantId INT, @PeriodStart DATE)
RETURNS TABLE
AS
RETURN
    SELECT COUNT(DISTINCT te.AppUserId) AS Heads
    FROM ar.Invoice AS i
    JOIN lkp.InvoiceStatus AS st ON st.TenantId = i.TenantId AND st.Id = i.InvoiceStatusId AND st.SystemCode <> 'VOID' AND st.SystemCode <> 'DRAFT'
    JOIN ar.InvoiceEntry AS l ON l.TenantId = i.TenantId AND l.InvoiceId = i.Id
    JOIN crm.TimeEntry AS te ON te.TenantId = l.TenantId AND te.InvoiceEntryId = l.Id
    WHERE i.TenantId = @TenantId
      AND i.IssuedAt >= CONVERT(DATETIME2(0), @PeriodStart) AND i.IssuedAt < DATEADD(MONTH, 1, CONVERT(DATETIME2(0), @PeriodStart))
      AND te.IsBillable = 1 AND te.DeletedAt IS NULL;
