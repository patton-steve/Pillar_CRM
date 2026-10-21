-- Lines can only be added, changed or removed while their invoice is a draft.
CREATE TRIGGER ar.trg_InvoiceEntry_DraftOnly
ON ar.InvoiceEntry
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM (SELECT TenantId, InvoiceId FROM inserted UNION SELECT TenantId, InvoiceId FROM deleted) AS x
        JOIN ar.Invoice AS i ON i.TenantId = x.TenantId AND i.Id = x.InvoiceId
        JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
        WHERE s.SystemCode <> 'DRAFT'
    )
        THROW 50641, N'Lines of an issued or void invoice cannot be changed.', 1;
END;
