-- Deleting a draft's SURCHARGE line waives the card processing fee for that invoice (handoff 25): CardSurchargeWaived = 1,
-- so ar.usp_Invoice_SyncSurcharge doesn't add it back. The sync proc's own deletes are skipped (SESSION_CONTEXT ArSurchargeSync).
-- ar.usp_Invoice_SetCardSurcharge @Waive = 0 brings it back.
CREATE TRIGGER ar.trg_InvoiceEntry_SurchargeWaive
ON ar.InvoiceEntry
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF SESSION_CONTEXT(N'ArSurchargeSync') IS NOT NULL RETURN;

    UPDATE i SET CardSurchargeWaived = 1, CardSurchargeRate = NULL, CardSurchargeNote = NULL
    FROM ar.Invoice AS i
    JOIN lkp.InvoiceStatus AS st ON st.TenantId = i.TenantId AND st.Id = i.InvoiceStatusId AND st.SystemCode = 'DRAFT'
    WHERE i.CardSurchargeWaived = 0
      AND EXISTS (SELECT 1 FROM deleted AS d
                  JOIN lkp.InvoiceLineType AS lt ON lt.TenantId = d.TenantId AND lt.Id = d.LineTypeId AND lt.SystemCode = 'SURCHARGE'
                  WHERE d.TenantId = i.TenantId AND d.InvoiceId = i.Id);
END;
