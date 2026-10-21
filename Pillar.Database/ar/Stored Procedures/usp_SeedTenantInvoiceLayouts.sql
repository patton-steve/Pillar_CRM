-- Gives a tenant the Pillar invoice layouts it is missing: SUMMARY (S, the default) and TIME_DETAIL (T).
-- Run at sign-up after lkp.usp_SyncTenantLookups and admin.usp_SeedTenantSettings.
-- @TenantId NULL = every tenant (needs IsPlatformAdmin), e.g. after Pillar adds a layout. Never changes existing rows.
CREATE PROCEDURE ar.usp_SeedTenantInvoiceLayouts
    @TenantId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    INSERT INTO ar.InvoiceLayout (TenantId, Code, Name, ReportId, IsDefault)
    SELECT t.Id, v.Code, v.Name, r.Id,
           CASE WHEN v.IsDefault = 1
                 AND NOT EXISTS (SELECT 1 FROM ar.InvoiceLayout AS d WHERE d.TenantId = t.Id AND d.IsDefault = 1)
                THEN 1 ELSE 0 END
    FROM admin.Tenant AS t
    CROSS JOIN (VALUES
        (N'SUMMARY',     N'Summary',                 'INVOICE_S', 1),
        (N'TIME_DETAIL', N'Time & materials detail', 'INVOICE_T', 0)
    ) AS v (Code, Name, ReportCode, IsDefault)
    JOIN admin.Report AS r ON r.Code = v.ReportCode
    WHERE (@TenantId IS NULL OR t.Id = @TenantId)
      AND NOT EXISTS (SELECT 1 FROM ar.InvoiceLayout AS x WHERE x.TenantId = t.Id AND x.Code = v.Code);
END;
