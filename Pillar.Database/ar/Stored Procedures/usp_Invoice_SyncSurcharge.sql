-- Keeps the card processing fee (a SURCHARGE line) current on drafts (handoff 25, Steve 2026-11-04). Internal: called by
-- ar.usp_Invoice_Recalculate (one draft) and ar.usp_InvoiceRun_Generate (a run's drafts), before their totals.
-- A draft gets exactly one SURCHARGE line when all of these hold, and none otherwise:
--   its billing profile has ApplyCardSurcharge = 1, Invoice.CardSurchargeRate is above 0,
--   nobody waived it on this draft (Invoice.CardSurchargeWaived = 0), and the other lines plus their tax come to more than 0.
-- Amount = ROUND(rate x (other lines + their tax), 2). The line is never taxable, so it doesn't change the tax.
-- Description is Invoice.CardSurchargeLabel; Invoice.CardSurchargeNote is filled in with {rate} as a percent.
-- Hand edits to the line's amount are overwritten. Deleting it is the way to waive it (ar.trg_InvoiceEntry_SurchargeWaive).
CREATE PROCEDURE ar.usp_Invoice_SyncSurcharge
    @InvoiceId      INT = NULL,
    @InvoiceRunId   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @Rate DECIMAL(9,6), @Label NVARCHAR(400), @Note NVARCHAR(400), @TypeId INT, @RatePct NVARCHAR(20);
    IF @TenantId IS NULL THROW 52501, N'SESSION_CONTEXT TenantId is not set.', 1;
    IF @InvoiceId IS NULL AND @InvoiceRunId IS NULL RETURN;

    SELECT @Rate = ISNULL(TRY_CONVERT(DECIMAL(9,6), Value), 0) FROM admin.fn_Setting(@TenantId, NULL, 'Invoice.CardSurchargeRate');
    SELECT @Label = COALESCE(NULLIF(LTRIM(Value), N''), N'Credit card processing fee') FROM admin.fn_Setting(@TenantId, NULL, 'Invoice.CardSurchargeLabel');
    SELECT @Note = NULLIF(LTRIM(Value), N'') FROM admin.fn_Setting(@TenantId, NULL, 'Invoice.CardSurchargeNote');
    SELECT @TypeId = Id FROM lkp.InvoiceLineType WHERE TenantId = @TenantId AND SystemCode = 'SURCHARGE';
    SET @Rate = ISNULL(@Rate, 0);
    IF @Rate > 0.04 SET @Rate = 0.04;
    SET @RatePct = FORMAT(@Rate * 100, N'0.##');
    SET @Label = LEFT(ISNULL(@Label, N'Credit card processing fee'), 1000);

    CREATE TABLE #surcharge (InvoiceId INT PRIMARY KEY, Base DECIMAL(19,2), Amount DECIMAL(19,2) NULL);
    INSERT INTO #surcharge (InvoiceId, Base, Amount)
    SELECT i.Id,
           ISNULL(l.Other, 0) + CASE WHEN i.TaxExempt = 1 THEN 0 ELSE ROUND(ISNULL(l.Taxable, 0) * i.TaxRate, 2) END,
           NULL
    FROM ar.Invoice AS i
    JOIN lkp.InvoiceStatus AS st ON st.TenantId = i.TenantId AND st.Id = i.InvoiceStatusId AND st.SystemCode = 'DRAFT'
    OUTER APPLY (
        SELECT SUM(e.Amount) AS Other, SUM(CASE WHEN e.IsTaxable = 1 THEN e.Amount ELSE 0 END) AS Taxable
        FROM ar.InvoiceEntry AS e
        WHERE e.TenantId = i.TenantId AND e.InvoiceId = i.Id AND (@TypeId IS NULL OR e.LineTypeId <> @TypeId)
    ) AS l
    WHERE i.TenantId = @TenantId
      AND (i.Id = @InvoiceId OR (@InvoiceId IS NULL AND i.InvoiceRunId = @InvoiceRunId));

    IF @TypeId IS NOT NULL AND @Rate > 0
        UPDATE s SET Amount = ROUND(s.Base * @Rate, 2)
        FROM #surcharge AS s
        JOIN ar.Invoice AS i ON i.TenantId = @TenantId AND i.Id = s.InvoiceId
        JOIN crm.ClientBillingProfile AS bp ON bp.TenantId = i.TenantId AND bp.Id = i.BillingProfileId
        WHERE bp.ApplyCardSurcharge = 1 AND i.CardSurchargeWaived = 0 AND s.Base > 0;
    UPDATE #surcharge SET Amount = NULL WHERE Amount <= 0;

    IF @TypeId IS NOT NULL
    BEGIN
        -- tells ar.trg_InvoiceEntry_SurchargeWaive that these deletes aren't a person waiving the fee
        EXEC sys.sp_set_session_context N'ArSurchargeSync', 1;

        DELETE e
        FROM ar.InvoiceEntry AS e
        JOIN #surcharge AS s ON s.InvoiceId = e.InvoiceId
        WHERE e.TenantId = @TenantId AND e.LineTypeId = @TypeId
          AND (s.Amount IS NULL
               OR e.Id <> (SELECT MIN(x.Id) FROM ar.InvoiceEntry AS x WHERE x.TenantId = @TenantId AND x.InvoiceId = e.InvoiceId AND x.LineTypeId = @TypeId));

        UPDATE e
        SET Description = @Label, Quantity = 1, UnitPrice = s.Amount, Amount = s.Amount, IsTaxable = 0,
            ProjectId = NULL, TaskId = NULL, ServicePeriodStart = NULL, ServicePeriodEnd = NULL,
            ModifiedAt = SYSUTCDATETIME(), ModifiedBy = CAST(SESSION_CONTEXT(N'UserId') AS INT)
        FROM ar.InvoiceEntry AS e
        JOIN #surcharge AS s ON s.InvoiceId = e.InvoiceId
        WHERE e.TenantId = @TenantId AND e.LineTypeId = @TypeId AND s.Amount IS NOT NULL
          AND (e.Amount <> s.Amount OR e.Description <> @Label OR e.IsTaxable = 1 OR e.Quantity <> 1);

        INSERT INTO ar.InvoiceEntry (TenantId, InvoiceId, LineNumber, LineTypeId, Description, Quantity, UnitPrice, Amount, IsTaxable)
        SELECT @TenantId, s.InvoiceId,
               ISNULL((SELECT MAX(x.LineNumber) FROM ar.InvoiceEntry AS x WHERE x.TenantId = @TenantId AND x.InvoiceId = s.InvoiceId), 0) + 1,
               @TypeId, @Label, 1, s.Amount, s.Amount, 0
        FROM #surcharge AS s
        WHERE s.Amount IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM ar.InvoiceEntry AS x WHERE x.TenantId = @TenantId AND x.InvoiceId = s.InvoiceId AND x.LineTypeId = @TypeId);

        EXEC sys.sp_set_session_context N'ArSurchargeSync', NULL;
    END;

    UPDATE i
    SET CardSurchargeRate = CASE WHEN s.Amount IS NULL THEN NULL ELSE @Rate END,
        CardSurchargeNote = CASE WHEN s.Amount IS NULL THEN NULL ELSE LEFT(REPLACE(@Note, N'{rate}', @RatePct), 400) END
    FROM ar.Invoice AS i
    JOIN #surcharge AS s ON s.InvoiceId = i.Id
    WHERE i.TenantId = @TenantId
      AND (ISNULL(i.CardSurchargeRate, -1) <> ISNULL(CASE WHEN s.Amount IS NULL THEN NULL ELSE @Rate END, -1)
           OR ISNULL(i.CardSurchargeNote, N'') <> ISNULL(CASE WHEN s.Amount IS NULL THEN NULL ELSE LEFT(REPLACE(@Note, N'{rate}', @RatePct), 400) END, N''));
END;
