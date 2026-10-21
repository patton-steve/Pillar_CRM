-- Dataset "StatementDetail" for PlatformStatement.rdl (and the API's statement screen): header columns repeated on every line.
CREATE PROCEDURE admin.usp_PlatformStatementDetail
    @TenantId           INT,
    @StatementPublicId  UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    EXEC sec.usp_ReportContext_Set @TenantId = @TenantId;

    SELECT
        s.Id AS StatementId, s.StatementNumber, s.PeriodStart, s.PeriodEnd, s.StatementDate, s.DueDate, s.Status,
        s.FeeTotal, s.MinimumAdjustment, s.CreditApplied, s.AmountDue, s.CreditForward, s.AmountPaid, s.BalanceDue, s.PaidAt,
        pay.MethodDisplay AS PaidWith,
        dm.MethodDisplay AS ChargeTo,
        COALESCE(b.CompanyName, t.Name) AS TenantName,
        CONCAT_WS(CHAR(13) + CHAR(10), b.AddressLine1, b.AddressLine2,
                  NULLIF(CONCAT(b.City, N', ' + b.Region, N' ' + b.PostalCode), N''),
                  CASE WHEN b.CountryCode <> 'US' THEN b.CountryCode END) AS TenantAddress,
        b.Email AS TenantEmail,
        l.LineNumber, l.LineType, l.InvoiceNumber, l.ClientName, l.InvoiceDate, l.Description,
        l.FeeBaseAmount, l.FeeRate, l.Amount
    FROM admin.PlatformStatement AS s
    JOIN admin.Tenant AS t ON t.Id = s.TenantId
    LEFT JOIN admin.TenantBranding AS b ON b.TenantId = s.TenantId
    OUTER APPLY (SELECT TOP (1) p.MethodDisplay FROM admin.PlatformPayment AS p
                 WHERE p.TenantId = s.TenantId AND p.StatementId = s.Id AND p.Succeeded = 1
                 ORDER BY p.AttemptedAt DESC) AS pay
    OUTER APPLY (SELECT TOP (1) CONCAT(m.Brand, N' ending ', m.Last4) AS MethodDisplay FROM admin.TenantPaymentMethod AS m
                 WHERE m.TenantId = s.TenantId AND m.IsDefault = 1 AND m.IsActive = 1) AS dm
    LEFT JOIN admin.PlatformStatementLine AS l ON l.TenantId = s.TenantId AND l.StatementId = s.Id
    WHERE s.TenantId = @TenantId AND s.PublicId = @StatementPublicId
    ORDER BY l.LineNumber;
END;
