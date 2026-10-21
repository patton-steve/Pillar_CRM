-- Everything an invoice prints, one row per time entry under each line (one row for a line with no time,
-- one row for an invoice with no lines). Header columns repeat on every row.
-- Issued invoices print their snapshot; drafts fall back to the live billing profile, so previews work.
-- Layout and remit resolve as invoice -> billing profile -> tenant default; with no remit profile the company address is used.
-- LineAmountOnce carries the line amount on the first row of each line only, so Sum() over it is safe.
-- Feeds ar.usp_InvoiceDetail and every invoice RDL; RLS applies, so it can also be queried directly in SSMS.
CREATE VIEW ar.vw_InvoiceDetail
AS
SELECT
    -- invoice
    i.TenantId,
    i.Id                    AS InvoiceId,
    i.PublicId              AS InvoicePublicId,
    COALESCE(i.InvoiceNumber, N'DRAFT') AS InvoiceNumber,
    st.SystemCode           AS InvoiceStatus,
    i.InvoiceDate,
    i.DueDate,
    i.PeriodStart,
    i.PeriodEnd,
    i.PoNumber,
    pt.Name                 AS PaymentTermName,
    COALESCE(i.ClientName, cl.Name)       AS ClientName,
    COALESCE(i.BillToName, c.DisplayName) AS BillToName,
    COALESCE(i.BillToEmail, c.Email)      AS BillToEmail,
    COALESCE(i.BillToAddress,
        CONCAT_WS(CHAR(13) + CHAR(10), a.Line1, a.Line2, a.Line3,
                  NULLIF(CONCAT(a.City, N', ' + a.Region, N' ' + a.PostalCode), N''),
                  CASE WHEN a.CountryCode <> 'US' THEN a.CountryCode END)) AS BillToAddress,
    COALESCE(i.InvoiceNotes, bp.InvoiceNotes) AS InvoiceNotes,
    i.TaxExempt,
    i.TaxRate,
    i.SubTotal,
    i.TaxAmount,
    i.Total,
    i.AmountPaid,
    i.BalanceDue,
    tn.CurrencyCode,
    -- layout
    lay.Id                  AS InvoiceLayoutId,
    rpt.Code                AS ReportCode,
    COALESCE(lay.Title, N'INVOICE') AS LayoutTitle,
    CAST(COALESCE(lay.ShowRates, 1) AS BIT) AS ShowRates,
    CAST(COALESCE(lay.ShowUserNames, 1) AS BIT) AS ShowUserNames,
    CAST(COALESCE(lay.ShowTimeNotes, 1) AS BIT) AS ShowTimeNotes,
    lay.HeaderText,
    lay.FooterText,
    -- company (admin.TenantBranding)
    COALESCE(b.CompanyName, tn.Name) AS CompanyName,
    CONCAT_WS(CHAR(13) + CHAR(10), b.AddressLine1, b.AddressLine2,
              NULLIF(CONCAT(b.City, N', ' + b.Region, N' ' + b.PostalCode), N''),
              CASE WHEN b.CountryCode <> 'US' THEN b.CountryCode END) AS CompanyAddress,
    NULLIF(CONCAT_WS(CHAR(13) + CHAR(10),
        NULLIF(CONCAT_WS(N'  |  ', b.Phone, b.Email, b.Website), N''),
        CASE WHEN lay.ShowTaxId = 1 THEN N'Tax ID ' + b.TaxId END), N'') AS CompanyContact,   -- phone | email | web, then tax ID
    b.Phone                 AS CompanyPhone,
    b.Email                 AS CompanyEmail,
    b.Website               AS CompanyWebsite,
    CASE WHEN lay.ShowTaxId = 1 THEN b.TaxId END AS CompanyTaxId,
    COALESCE(b.AccentColor, '#1F3A5F') AS AccentColor,
    -- remit to
    COALESCE(rp.PayableTo, b.CompanyName, tn.Name) AS RemitPayableTo,
    CASE WHEN rp.Id IS NOT NULL THEN
        CONCAT_WS(CHAR(13) + CHAR(10), rp.AddressLine1, rp.AddressLine2,
                  NULLIF(CONCAT(rp.City, N', ' + rp.Region, N' ' + rp.PostalCode), N''),
                  CASE WHEN rp.CountryCode <> 'US' THEN rp.CountryCode END)
    ELSE
        CONCAT_WS(CHAR(13) + CHAR(10), b.AddressLine1, b.AddressLine2,
                  NULLIF(CONCAT(b.City, N', ' + b.Region, N' ' + b.PostalCode), N''),
                  CASE WHEN b.CountryCode <> 'US' THEN b.CountryCode END)
    END                     AS RemitAddress,
    COALESCE(rp.Email, b.Email) AS RemitEmail,
    COALESCE(rp.Phone, b.Phone) AS RemitPhone,
    rp.PaymentInstructions,
    -- line
    l.Id                    AS LineId,
    l.LineNumber,
    lt.SystemCode           AS LineType,
    l.ProjectId,
    p.ProjectCode,
    p.Name                  AS ProjectName,
    tk.TaskKey,
    tk.Title                AS TaskTitle,
    l.Description           AS LineDescription,
    l.Quantity,
    l.UnitPrice,
    l.Amount                AS LineAmount,
    CAST(CASE WHEN ISNULL(te.Seq, 1) = 1 THEN ISNULL(l.Amount, 0) ELSE 0 END AS DECIMAL(19,2)) AS LineAmountOnce,
    l.IsTaxable,
    l.ServicePeriodStart,
    l.ServicePeriodEnd,
    -- time entry detail (T layout)
    te.Id                   AS TimeEntryId,
    te.Seq                  AS TimeEntrySeq,
    te.WorkDate,
    te.AppUserId,
    au.DisplayName          AS UserName,
    te.Hours,
    te.RateApplied,
    te.AmountBillable,
    te.Description          AS TimeDescription
FROM ar.Invoice AS i
JOIN admin.Tenant AS tn ON tn.Id = i.TenantId
JOIN lkp.InvoiceStatus AS st ON st.TenantId = i.TenantId AND st.Id = i.InvoiceStatusId
JOIN lkp.PaymentTerm AS pt ON pt.TenantId = i.TenantId AND pt.Id = i.PaymentTermId
JOIN crm.Client AS cl ON cl.TenantId = i.TenantId AND cl.Id = i.ClientId
JOIN crm.ClientBillingProfile AS bp ON bp.TenantId = i.TenantId AND bp.Id = i.BillingProfileId
LEFT JOIN crm.Contact AS c ON c.TenantId = bp.TenantId AND c.Id = bp.BillingContactId
LEFT JOIN crm.Address AS a ON a.TenantId = bp.TenantId AND a.Id = bp.BillingAddressId
LEFT JOIN admin.TenantBranding AS b ON b.TenantId = i.TenantId
OUTER APPLY (
    SELECT TOP (1) x.*
    FROM ar.InvoiceLayout AS x
    WHERE x.TenantId = i.TenantId
      AND (x.Id = COALESCE(i.InvoiceLayoutId, bp.InvoiceLayoutId) OR (x.IsDefault = 1 AND x.IsActive = 1))
    ORDER BY CASE WHEN x.Id = COALESCE(i.InvoiceLayoutId, bp.InvoiceLayoutId) THEN 0 ELSE 1 END
) AS lay
LEFT JOIN admin.Report AS rpt ON rpt.Id = lay.ReportId
OUTER APPLY (
    SELECT TOP (1) x.*
    FROM admin.RemitProfile AS x
    WHERE x.TenantId = i.TenantId
      AND (x.Id = COALESCE(i.RemitProfileId, bp.RemitProfileId) OR (x.IsDefault = 1 AND x.IsActive = 1))
    ORDER BY CASE WHEN x.Id = COALESCE(i.RemitProfileId, bp.RemitProfileId) THEN 0 ELSE 1 END
) AS rp
LEFT JOIN ar.InvoiceEntry AS l ON l.TenantId = i.TenantId AND l.InvoiceId = i.Id
LEFT JOIN lkp.InvoiceLineType AS lt ON lt.TenantId = l.TenantId AND lt.Id = l.LineTypeId
LEFT JOIN crm.ClientProject AS p ON p.TenantId = l.TenantId AND p.Id = l.ProjectId
LEFT JOIN crm.ClientTask AS tk ON tk.TenantId = l.TenantId AND tk.Id = l.TaskId
LEFT JOIN (
    SELECT e.TenantId, e.Id, e.InvoiceEntryId, e.WorkDate, e.AppUserId, e.Hours, e.RateApplied, e.AmountBillable, e.Description,
           ROW_NUMBER() OVER (PARTITION BY e.TenantId, e.InvoiceEntryId ORDER BY e.WorkDate, e.Id) AS Seq
    FROM crm.TimeEntry AS e
    WHERE e.InvoiceEntryId IS NOT NULL AND e.DeletedAt IS NULL
) AS te ON te.TenantId = l.TenantId AND te.InvoiceEntryId = l.Id
LEFT JOIN sec.AppUser AS au ON au.TenantId = te.TenantId AND au.Id = te.AppUserId;
