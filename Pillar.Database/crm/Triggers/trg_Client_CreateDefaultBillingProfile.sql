-- Every new client gets a "Default" billing profile using the tenant's default payment term
-- (falls back to the first active term). Contact and address stay NULL until they exist.
CREATE TRIGGER crm.trg_Client_CreateDefaultBillingProfile
ON crm.Client
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1 FROM inserted AS i
        WHERE NOT EXISTS (SELECT 1 FROM lkp.PaymentTerm AS p WHERE p.TenantId = i.TenantId AND p.IsActive = 1)
    )
        THROW 50101, N'Cannot create a client: the tenant has no active payment term for the default billing profile.', 1;

    INSERT INTO crm.ClientBillingProfile (TenantId, ClientId, ProfileCode, Name, PaymentTermId, IsDefault)
    SELECT i.TenantId, i.Id, N'DEFAULT', N'Default', pt.Id, 1
    FROM inserted AS i
    CROSS APPLY (
        SELECT TOP (1) p.Id
        FROM lkp.PaymentTerm AS p
        WHERE p.TenantId = i.TenantId AND p.IsActive = 1
        ORDER BY p.IsDefault DESC, p.SortOrder, p.Id
    ) AS pt
    WHERE NOT EXISTS (SELECT 1 FROM crm.ClientBillingProfile AS b WHERE b.TenantId = i.TenantId AND b.ClientId = i.Id);
END;
