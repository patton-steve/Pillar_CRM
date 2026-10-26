-- The template to use for an email: the billing profile's own INVOICE template when it has one (and it isn't deleted),
-- otherwise the tenant's default for @TemplateType. @BillingProfileId NULL = the default.
CREATE FUNCTION admin.fn_EmailTemplateFor (@TenantId INT, @TemplateType VARCHAR(20), @BillingProfileId INT)
RETURNS TABLE
AS
RETURN
    SELECT TOP (1) t.Id, t.Name, t.Subject, t.BodyHtml
    FROM admin.EmailTemplate AS t
    LEFT JOIN crm.ClientBillingProfile AS p
        ON @TemplateType = 'INVOICE' AND p.TenantId = @TenantId AND p.Id = @BillingProfileId AND p.InvoiceEmailTemplateId = t.Id
    WHERE t.TenantId = @TenantId AND t.TemplateType = @TemplateType AND t.DeletedAt IS NULL
      AND (p.Id IS NOT NULL OR t.IsDefault = 1)
    ORDER BY IIF(p.Id IS NOT NULL, 0, 1);
