-- Recomputes SubTotal and TaxAmount of a draft from its lines. Call after editing draft lines.
CREATE PROCEDURE ar.usp_Invoice_Recalculate
    @InvoiceId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT);

    UPDATE i
    SET SubTotal  = ISNULL(l.SubTotal, 0),
        TaxAmount = CASE WHEN i.TaxExempt = 1 THEN 0 ELSE ROUND(ISNULL(l.Taxable, 0) * i.TaxRate, 2) END,
        ModifiedAt = SYSUTCDATETIME(), ModifiedBy = CAST(SESSION_CONTEXT(N'UserId') AS INT)
    FROM ar.Invoice AS i
    JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId AND s.SystemCode = 'DRAFT'
    OUTER APPLY (
        SELECT SUM(e.Amount) AS SubTotal, SUM(CASE WHEN e.IsTaxable = 1 THEN e.Amount ELSE 0 END) AS Taxable
        FROM ar.InvoiceEntry AS e WHERE e.TenantId = i.TenantId AND e.InvoiceId = i.Id
    ) AS l
    WHERE i.TenantId = @TenantId AND i.Id = @InvoiceId;
END;
