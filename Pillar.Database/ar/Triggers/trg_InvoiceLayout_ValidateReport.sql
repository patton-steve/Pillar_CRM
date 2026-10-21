-- A layout must point at an INVOICE report that is Pillar's or built for this tenant;
-- a tenant-specific (custom) report also needs Feature.CustomInvoiceLayouts = 1.
CREATE TRIGGER ar.trg_InvoiceLayout_ValidateReport
ON ar.InvoiceLayout
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(ReportId) RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN admin.Report AS r ON r.Id = i.ReportId
        WHERE r.ReportType <> 'INVOICE'
           OR (r.OwnerTenantId IS NOT NULL AND r.OwnerTenantId <> i.TenantId))
        THROW 50921, N'An invoice layout must use an invoice report available to this tenant.', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN admin.Report AS r ON r.Id = i.ReportId
        OUTER APPLY admin.fn_Setting(i.TenantId, NULL, 'Feature.CustomInvoiceLayouts') AS f
        WHERE r.OwnerTenantId IS NOT NULL AND ISNULL(f.Value, N'0') <> N'1')
        THROW 50922, N'Custom invoice layouts are not enabled for this tenant.', 1;
END;
