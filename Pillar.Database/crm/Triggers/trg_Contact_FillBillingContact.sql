-- When a client gets contacts, any of its billing profiles still missing a billing contact
-- picks one up: the primary contact if one was inserted, otherwise the first inserted.
CREATE TRIGGER crm.trg_Contact_FillBillingContact
ON crm.Contact
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    WITH pick AS (
        SELECT i.TenantId, i.ClientId, i.Id,
               ROW_NUMBER() OVER (PARTITION BY i.TenantId, i.ClientId ORDER BY i.IsPrimary DESC, i.Id) AS rn
        FROM inserted AS i
        WHERE i.IsActive = 1 AND i.DeletedAt IS NULL
    )
    UPDATE b
    SET BillingContactId = pick.Id,
        ModifiedAt = SYSUTCDATETIME()
    FROM crm.ClientBillingProfile AS b
    JOIN pick ON pick.TenantId = b.TenantId AND pick.ClientId = b.ClientId AND pick.rn = 1
    WHERE b.BillingContactId IS NULL
      AND b.DeletedAt IS NULL;
END;
