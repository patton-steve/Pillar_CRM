-- Recomputes Bill.AmountPaid and status (OPEN / PARTIAL / PAID) and BillPay.AmountApplied from active applications.
CREATE PROCEDURE ap.usp_BillApplicationTotals_Sync
    @BillId     INT = NULL,
    @BillPayId  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT), @Now DATETIME2(0) = SYSUTCDATETIME();

    UPDATE b
    SET AmountPaid = ISNULL(a.Paid, 0), BillStatusId = st.Id, ModifiedAt = @Now, ModifiedBy = @UserId
    FROM ap.Bill AS b
    OUTER APPLY (SELECT SUM(x.AmountApplied) AS Paid FROM ap.BillPayApplication AS x
                 WHERE x.TenantId = b.TenantId AND x.BillId = b.Id AND x.ReversedAt IS NULL) AS a
    JOIN lkp.BillStatus AS st ON st.TenantId = b.TenantId
        AND st.SystemCode = CASE WHEN ISNULL(a.Paid, 0) = 0 THEN 'OPEN'
                                 WHEN ISNULL(a.Paid, 0) >= b.Total THEN 'PAID'
                                 ELSE 'PARTIAL' END
    WHERE b.TenantId = @TenantId AND b.Id = @BillId;

    UPDATE p
    SET AmountApplied = ISNULL((SELECT SUM(x.AmountApplied) FROM ap.BillPayApplication AS x
                                WHERE x.TenantId = p.TenantId AND x.BillPayId = p.Id AND x.ReversedAt IS NULL), 0),
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM ap.BillPay AS p
    WHERE p.TenantId = @TenantId AND p.Id = @BillPayId;
END;
