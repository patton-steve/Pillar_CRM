-- Settings > Billing, "this month so far": fees not yet on a statement, per tenant. RLS limits a tenant to its own row.
-- The monthly minimum is not applied here; the statement adds it.
CREATE VIEW admin.vw_PlatformFeeToDate
AS
SELECT f.TenantId,
       COUNT(CASE WHEN f.ReversalOfFeeId IS NULL THEN 1 END) AS InvoiceCount,
       CAST(SUM(CASE WHEN f.ReversalOfFeeId IS NULL THEN f.FeeBaseAmount ELSE 0 END) AS DECIMAL(19,2)) AS InvoicedSubtotal,
       CAST(SUM(f.FeeAmount) AS DECIMAL(19,2)) AS FeesToDate,
       MIN(f.AccruedAt) AS FirstAccruedAt
FROM admin.PlatformFee AS f
WHERE f.PlatformStatementId IS NULL
GROUP BY f.TenantId;
