-- Waives (@Waive = 1) or restores (@Waive = 0) the card processing fee on one draft, then recalculates it (handoff 25).
-- Waiving is the same as deleting the SURCHARGE line. Restoring adds it back only when the billing profile has
-- ApplyCardSurcharge = 1 and Invoice.CardSurchargeRate is above 0. Needs invoice.run, like other draft edits.
CREATE PROCEDURE ar.usp_Invoice_SetCardSurcharge
    @InvoiceId  INT,
    @Waive      BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT);
    IF @TenantId IS NULL THROW 52501, N'SESSION_CONTEXT TenantId is not set.', 1;
    IF @Waive IS NULL THROW 52503, N'Say whether to waive the fee or add it back.', 1;
    IF @UserId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'invoice.run'))
        THROW 52504, N'You need permission to edit invoices.', 1;

    BEGIN TRAN;
    UPDATE i SET CardSurchargeWaived = @Waive, ModifiedAt = SYSUTCDATETIME(), ModifiedBy = @UserId
    FROM ar.Invoice AS i
    JOIN lkp.InvoiceStatus AS st ON st.TenantId = i.TenantId AND st.Id = i.InvoiceStatusId AND st.SystemCode = 'DRAFT'
    WHERE i.TenantId = @TenantId AND i.Id = @InvoiceId;
    IF @@ROWCOUNT = 0 THROW 52502, N'Only a draft invoice''s card fee can be changed.', 1;

    EXEC ar.usp_Invoice_Recalculate @InvoiceId = @InvoiceId;
    COMMIT;
END;
