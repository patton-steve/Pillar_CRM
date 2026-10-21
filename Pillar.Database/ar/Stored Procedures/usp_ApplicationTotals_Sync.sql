-- Recomputes, from active ar.InvoicePayApplication rows, Invoice.AmountPaid and status (ISSUED / PARTIAL / PAID)
-- and the AmountApplied of the payment and/or credit memo involved. Called by apply, unapply and void procs.
CREATE PROCEDURE ar.usp_ApplicationTotals_Sync
    @InvoiceId      INT = NULL,
    @InvoicePayId   INT = NULL,
    @CreditMemoId   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME();

    UPDATE i
    SET AmountPaid = ISNULL(a.Paid, 0),
        InvoiceStatusId = st.Id,
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM ar.Invoice AS i
    OUTER APPLY (SELECT SUM(x.AmountApplied) AS Paid FROM ar.InvoicePayApplication AS x
                 WHERE x.TenantId = i.TenantId AND x.InvoiceId = i.Id AND x.ReversedAt IS NULL) AS a
    JOIN lkp.InvoiceStatus AS st ON st.TenantId = i.TenantId
        AND st.SystemCode = CASE WHEN ISNULL(a.Paid, 0) = 0 THEN 'ISSUED'
                                 WHEN ISNULL(a.Paid, 0) >= i.Total THEN 'PAID'
                                 ELSE 'PARTIAL' END
    WHERE i.TenantId = @TenantId AND i.Id = @InvoiceId;

    UPDATE p
    SET AmountApplied = ISNULL((SELECT SUM(x.AmountApplied) FROM ar.InvoicePayApplication AS x
                                WHERE x.TenantId = p.TenantId AND x.InvoicePayId = p.Id AND x.ReversedAt IS NULL), 0),
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM ar.InvoicePay AS p
    WHERE p.TenantId = @TenantId AND p.Id = @InvoicePayId;

    UPDATE c
    SET AmountApplied = ISNULL((SELECT SUM(x.AmountApplied) FROM ar.InvoicePayApplication AS x
                                WHERE x.TenantId = c.TenantId AND x.CreditMemoId = c.Id AND x.ReversedAt IS NULL), 0),
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM ar.CreditMemo AS c
    WHERE c.TenantId = @TenantId AND c.Id = @CreditMemoId;
END;
