-- Gives a tenant Pillar's default INVOICE email template if it has no INVOICE template yet. Run at sign-up;
-- @TenantId NULL = every tenant (needs IsPlatformAdmin; the post-deploy does this).
CREATE PROCEDURE admin.usp_SeedTenantEmailTemplates
    @TenantId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO admin.EmailTemplate (TenantId, TemplateType, Name, Subject, BodyHtml, IsDefault)
    SELECT t.Id, 'INVOICE', N'Standard invoice', N'Invoice {InvoiceNumber} from {TenantName}',
           N'<p>Hello {ClientName},</p><p>Please find invoice {InvoiceNumber} attached. The amount due is {AmountDue}, due {DueDate}.</p><p>Thank you,<br>{TenantName}</p>',
           1
    FROM admin.Tenant AS t
    WHERE (@TenantId IS NULL OR t.Id = @TenantId)
      AND NOT EXISTS (SELECT 1 FROM admin.EmailTemplate AS x WHERE x.TenantId = t.Id AND x.TemplateType = 'INVOICE' AND x.DeletedAt IS NULL);
END;
