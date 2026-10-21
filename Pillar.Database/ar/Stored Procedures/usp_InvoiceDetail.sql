-- The one dataset proc behind every invoice RDL (dataset "InvoiceDetail"), also usable from the API and SSMS.
-- @IncludeTimeDetail = 0 returns one row per line (S layout); 1 adds a row per time entry under each line (T layout).
-- Ordered by line, then work date. Pair with admin.usp_TenantLogo for the logo.
CREATE PROCEDURE ar.usp_InvoiceDetail
    @TenantId           INT,
    @InvoicePublicId    UNIQUEIDENTIFIER,
    @IncludeTimeDetail  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    EXEC sec.usp_ReportContext_Set @TenantId = @TenantId;

    SELECT
        d.InvoiceId, d.InvoicePublicId, d.InvoiceNumber, d.InvoiceStatus, d.InvoiceDate, d.DueDate,
        d.PeriodStart, d.PeriodEnd, d.PoNumber, d.PaymentTermName,
        d.ClientName, d.BillToName, d.BillToEmail, d.BillToAddress, d.InvoiceNotes,
        d.TaxExempt, d.TaxRate, d.SubTotal, d.TaxAmount, d.Total, d.AmountPaid, d.BalanceDue, d.CurrencyCode,
        d.InvoiceLayoutId, d.ReportCode, d.LayoutTitle, d.ShowRates, d.ShowUserNames, d.ShowTimeNotes, d.HeaderText, d.FooterText,
        d.CompanyName, d.CompanyAddress, d.CompanyContact, d.CompanyPhone, d.CompanyEmail, d.CompanyWebsite, d.CompanyTaxId, d.AccentColor,
        d.RemitPayableTo, d.RemitAddress, d.RemitEmail, d.RemitPhone, d.PaymentInstructions,
        d.LineId, d.LineNumber, d.LineType, d.ProjectId, d.ProjectCode, d.ProjectName, d.TaskKey, d.TaskTitle,
        d.LineDescription, d.Quantity, d.UnitPrice, d.LineAmount, d.LineAmountOnce, d.IsTaxable,
        d.ServicePeriodStart, d.ServicePeriodEnd,
        CASE WHEN @IncludeTimeDetail = 1 THEN d.TimeEntryId END     AS TimeEntryId,
        CASE WHEN @IncludeTimeDetail = 1 THEN d.WorkDate END        AS WorkDate,
        CASE WHEN @IncludeTimeDetail = 1 THEN d.AppUserId END       AS AppUserId,
        CASE WHEN @IncludeTimeDetail = 1 THEN d.UserName END        AS UserName,
        CASE WHEN @IncludeTimeDetail = 1 THEN d.Hours END           AS Hours,
        CASE WHEN @IncludeTimeDetail = 1 THEN d.RateApplied END     AS RateApplied,
        CASE WHEN @IncludeTimeDetail = 1 THEN d.AmountBillable END  AS AmountBillable,
        CASE WHEN @IncludeTimeDetail = 1 THEN d.TimeDescription END AS TimeDescription
    FROM ar.vw_InvoiceDetail AS d
    WHERE d.TenantId = @TenantId
      AND d.InvoicePublicId = @InvoicePublicId
      AND (@IncludeTimeDetail = 1 OR ISNULL(d.TimeEntrySeq, 1) = 1)
    ORDER BY d.LineNumber, d.WorkDate, d.TimeEntryId;
END;
