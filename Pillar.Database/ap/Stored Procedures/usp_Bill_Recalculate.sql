-- Recomputes a draft bill's SubTotal from its lines. Call after editing draft lines.
-- (TaxAmount is entered as billed by the vendor and kept as is.)
CREATE PROCEDURE ap.usp_Bill_Recalculate
    @BillId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT);

    UPDATE b
    SET SubTotal = ISNULL((SELECT SUM(l.Amount) FROM ap.BillLine AS l WHERE l.TenantId = b.TenantId AND l.BillId = b.Id), 0),
        ModifiedAt = SYSUTCDATETIME(), ModifiedBy = CAST(SESSION_CONTEXT(N'UserId') AS INT)
    FROM ap.Bill AS b
    JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId AND s.SystemCode = 'DRAFT'
    WHERE b.TenantId = @TenantId AND b.Id = @BillId;
END;
