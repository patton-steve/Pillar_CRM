-- Recomputes, from active ar.InvoicePayApplication rows, Invoice.AmountPaid and status (ISSUED / PARTIAL / PAID)
-- and the AmountApplied of the payment and/or credit memo involved. Called by apply, unapply and void procs.
-- An invoice that becomes PAID notifies the client's account manager (INVOICE_PAID).
CREATE PROCEDURE ar.usp_ApplicationTotals_Sync
    @InvoiceId      INT = NULL,
    @InvoicePayId   INT = NULL,
    @CreditMemoId   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @WasPaid BIT, @IsPaid BIT, @Title NVARCHAR(200);

    SELECT @WasPaid = IIF(s.SystemCode = 'PAID', 1, 0)
    FROM ar.Invoice AS i JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
    WHERE i.TenantId = @TenantId AND i.Id = @InvoiceId;

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

    SELECT @IsPaid = IIF(s.SystemCode = 'PAID', 1, 0),
           @Title = CONCAT(N'Invoice ', i.InvoiceNumber, N' for ', c.Name, N' is paid')
    FROM ar.Invoice AS i
    JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
    JOIN crm.Client AS c ON c.TenantId = i.TenantId AND c.Id = i.ClientId
    WHERE i.TenantId = @TenantId AND i.Id = @InvoiceId;
    IF @IsPaid = 1 AND @WasPaid = 0
        EXEC sec.usp_Notification_Raise @NotificationType = 'INVOICE_PAID', @EntityType = 'INVOICE',
             @EntityId = @InvoiceId, @Title = @Title;

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
